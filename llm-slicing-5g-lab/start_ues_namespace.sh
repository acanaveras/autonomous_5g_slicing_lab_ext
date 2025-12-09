#!/bin/bash

# SPDX-FileCopyrightText: Copyright (c) 2023-2024 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: Apache-2.0
#
# Start UEs using Linux network namespaces (solves Docker TUN interface conflicts)
# This script replaces Docker-based UE containers with native namespace execution

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

LOG_DIR="$SCRIPT_DIR/logs"
mkdir -p "$LOG_DIR"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

log_error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] ⚠️  $1${NC}"
}

# Check if running as root
if [[ $(id -u) -ne 0 ]]; then
    log_error "This script must be run as root (sudo)"
    exit 1
fi

# Paths to binaries
NR_UESOFTMODEM="$SCRIPT_DIR/openairinterface5g/cmake_targets/ran_build/build/nr-uesoftmodem"
MULTI_UE_SCRIPT="$SCRIPT_DIR/multi_ue.sh"

# Check prerequisites
if [ ! -f "$NR_UESOFTMODEM" ]; then
    log_error "nr-uesoftmodem not found at $NR_UESOFTMODEM"
    log_error "Please run build_ric_oai_ne.sh first"
    exit 1
fi

if [ ! -f "$MULTI_UE_SCRIPT" ]; then
    log_error "multi_ue.sh not found at $MULTI_UE_SCRIPT"
    exit 1
fi

# Ensure iperf3 is installed on host
if ! command -v iperf3 &> /dev/null; then
    log_warning "iperf3 not found on host, installing..."
    apt-get update && apt-get install -y iperf3
    log_success "iperf3 installed"
fi

# Cleanup function to remove namespaces and kill processes
cleanup() {
    log "Cleaning up UE processes and namespaces..."
    
    # Kill any existing nr-uesoftmodem processes
    pkill -f "nr-uesoftmodem" 2>/dev/null || true
    sleep 2
    
    # Delete namespaces if they exist
    for ns in ue1 ue3; do
        if ip netns list | grep -q "^$ns "; then
            log "Deleting namespace $ns..."
            "$MULTI_UE_SCRIPT" -d ${ns#ue} 2>/dev/null || ip netns delete $ns 2>/dev/null || true
        fi
    done
    
    # Clean up veth interfaces
    for iface in v-eth1 v-eth3; do
        if ip link show $iface &>/dev/null; then
            ip link delete $iface 2>/dev/null || true
        fi
    done
    
    log_success "Cleanup complete"
}

# Trap to cleanup on exit
trap cleanup EXIT

# Function to start a UE
start_ue() {
    local ue_id=$1
    local config_file=$2
    local namespace="ue$ue_id"
    local server_addr=$3
    local log_file="$LOG_DIR/UE${ue_id}.log"
    
    log "Creating namespace for UE$ue_id..."
    
    # Create namespace using multi_ue.sh
    "$MULTI_UE_SCRIPT" -c$ue_id &
    sleep 3
    
    # Verify namespace was created
    if ! ip netns list | grep -q "^$namespace "; then
        log_error "Failed to create namespace $namespace"
        return 1
    fi
    
    log_success "Namespace $namespace created"
    
    # Start nr-uesoftmodem in the namespace
    log "Starting UE$ue_id in namespace $namespace..."
    
    (
        cd "$SCRIPT_DIR"
        export LD_LIBRARY_PATH="."
        
        ip netns exec $namespace bash -c "
            cd $SCRIPT_DIR
            export LD_LIBRARY_PATH=.
            $NR_UESOFTMODEM \
                --rfsimulator.serveraddr $server_addr \
                -r 106 \
                --numerology 1 \
                --band 78 \
                -C 3619200000 \
                --rfsim \
                --sa \
                -O $config_file \
                -E \
                --log_config.global_log_level info \
                2>&1 | tee $log_file
        " &
    )
    
    log_success "UE$ue_id process started, logging to $log_file"
}

# Main execution
log "========================================"
log "Starting UEs using Network Namespaces"
log "========================================"

# First cleanup any existing state
cleanup

# Remove trap temporarily during startup
trap - EXIT

# Start UE1 (Slice 1)
log ""
log "Starting UE1 (Slice 1)..."
start_ue 1 "ran-conf/ue_1.conf" "10.201.1.100"

# Wait for UE1 to initialize before starting UE2
log "Waiting 10 seconds for UE1 to initialize..."
sleep 10

# Start UE2 (Slice 2) - uses namespace ue3 like in the notebook
log ""
log "Starting UE2 (Slice 2) in namespace ue3..."
start_ue 3 "ran-conf/ue_2.conf" "10.203.1.100"

# Restore cleanup trap
trap cleanup EXIT

# Wait for UEs to register with the network
log ""
log "Waiting 20 seconds for UEs to register with 5G core..."
sleep 20

# Verify UE interfaces
log ""
log "Verifying UE interfaces..."

for ns in ue1 ue3; do
    if ip netns exec $ns ip addr show oaitun_ue1 2>/dev/null | grep -q "inet "; then
        ip_addr=$(ip netns exec $ns ip addr show oaitun_ue1 | grep "inet " | awk '{print $2}' | cut -d'/' -f1)
        log_success "UE in namespace $ns: oaitun_ue1 has IP $ip_addr"
    else
        log_warning "UE in namespace $ns: oaitun_ue1 not yet configured (may still be registering)"
    fi
done

log ""
log "========================================"
log_success "UE startup complete!"
log "========================================"
log ""
log "Next steps:"
log "  - Check UE logs: tail -f $LOG_DIR/UE1.log"
log "  - Check UE logs: tail -f $LOG_DIR/UE3.log"
log "  - Run traffic: python3 generate_traffic.py"
log ""
log "To stop UEs, press Ctrl+C or run: sudo pkill -f nr-uesoftmodem"
log ""

# Keep script running to maintain namespaces
# When script exits, cleanup will be called
log "Press Ctrl+C to stop UEs and cleanup..."
wait
