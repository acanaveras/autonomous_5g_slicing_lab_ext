#!/bin/bash

# SPDX-FileCopyrightText: Copyright (c) 2023-2024 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: Apache-2.0
#
# Stop UE processes and cleanup network namespaces

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
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

# Check if running as root
if [[ $(id -u) -ne 0 ]]; then
    log_error "This script must be run as root (sudo)"
    exit 1
fi

log "Stopping UE processes and cleaning up namespaces..."

# Kill any existing nr-uesoftmodem processes
if pgrep -f "nr-uesoftmodem" > /dev/null; then
    log "Stopping nr-uesoftmodem processes..."
    pkill -f "nr-uesoftmodem" 2>/dev/null
    sleep 2
    # Force kill if still running
    pkill -9 -f "nr-uesoftmodem" 2>/dev/null || true
    log_success "nr-uesoftmodem processes stopped"
else
    log "No nr-uesoftmodem processes found"
fi

# Delete namespaces
for ue_id in 1 3; do
    ns="ue$ue_id"
    if ip netns list | grep -q "^$ns "; then
        log "Deleting namespace $ns..."
        
        # Delete veth interface first
        if ip link show v-eth$ue_id &>/dev/null; then
            ip link delete v-eth$ue_id 2>/dev/null || true
        fi
        
        # Delete namespace
        ip netns delete $ns 2>/dev/null || true
        log_success "Namespace $ns deleted"
    else
        log "Namespace $ns not found (already deleted)"
    fi
done

# Clean up any remaining iptables rules
for ue_id in 1 3; do
    BASE_IP=$((200+ue_id))
    iptables -t nat -D POSTROUTING -s 10.$BASE_IP.1.0/255.255.255.0 -o lo -j MASQUERADE 2>/dev/null || true
    iptables -D FORWARD -i lo -o v-eth$ue_id -j ACCEPT 2>/dev/null || true
    iptables -D FORWARD -o lo -i v-eth$ue_id -j ACCEPT 2>/dev/null || true
done

log_success "UE cleanup complete!"
echo ""
log "Remaining namespaces:"
ip netns list || echo "  (none)"
echo ""
log "Remaining nr-uesoftmodem processes:"
pgrep -a nr-uesoftmodem || echo "  (none)"
