#!/bin/bash

# SPDX-FileCopyrightText: Copyright (c) 2023-2024 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: Apache-2.0
#
# Shutdown script for Autonomous 5G Slicing Lab (Dockerized)
# Stops all components in reverse order

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

LOG_DIR="../logs"
mkdir -p "$LOG_DIR"

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_FILE="$LOG_DIR/lab_stop_${TIMESTAMP}.log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] ✅ $1${NC}" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ❌ $1${NC}" | tee -a "$LOG_FILE"
}

echo "========================================"
echo "  Autonomous 5G Slicing Lab - Shutdown"
echo "  Dockerized Version"
echo "========================================"
echo ""
log "Starting lab shutdown..."
log "Log file: $LOG_FILE"
echo ""

# Step 0: Stop Traffic Generator and Log Streaming
log "Step 0: Stopping traffic generator and log streaming..."
TRAFFIC_PIDS=$(pgrep -f "generate_traffic.py" || echo "")
LOG_STREAM_PIDS=$(pgrep -f "tail -f.*traffic_gen_final.log" || echo "")

if [ -n "$TRAFFIC_PIDS" ]; then
    pkill -f "generate_traffic.py" >> "$LOG_FILE" 2>&1 || true
    log_success "Traffic generator stopped"
else
    log "No traffic generator running"
fi

if [ -n "$LOG_STREAM_PIDS" ]; then
    pkill -f "tail -f.*traffic_gen_final.log" >> "$LOG_FILE" 2>&1 || true
    log_success "Log streaming stopped"
else
    log "No log streaming running"
fi

sleep 1
echo ""

# Step 1: Stop Monitoring Stack
log "Step 1: Stopping Monitoring Stack..."
docker compose -f docker-compose-monitoring.yaml down >> "$LOG_FILE" 2>&1 || true
log_success "Monitoring Stack stopped"
echo ""

# Step 2: Stop UE processes and clean up namespaces
log "Step 2: Stopping UE processes and cleaning up namespaces..."

# Kill UE processes
UE1_PIDS=$(sudo ip netns pids ue1 2>/dev/null || echo "")
UE2_PIDS=$(sudo ip netns pids ue2 2>/dev/null || echo "")

if [ -n "$UE1_PIDS" ]; then
    log "Stopping UE1 processes..."
    for pid in $UE1_PIDS; do
        sudo kill -9 $pid 2>/dev/null || true
    done
    log_success "UE1 processes stopped"
else
    log "No UE1 processes running"
fi

if [ -n "$UE2_PIDS" ]; then
    log "Stopping UE2 processes..."
    for pid in $UE2_PIDS; do
        sudo kill -9 $pid 2>/dev/null || true
    done
    log_success "UE2 processes stopped"
else
    log "No UE2 processes running"
fi

sleep 2

# Delete namespaces
cd ..
log "Deleting namespace ue1..."
sudo ./multi_ue.sh -d 1 >> "$LOG_FILE" 2>&1 || true
log "Deleting namespace ue2..."
sudo ./multi_ue.sh -d 2 >> "$LOG_FILE" 2>&1 || true

# Verify namespaces are deleted
if ! ip netns list | grep -q "ue1" && ! ip netns list | grep -q "ue2"; then
    log_success "UE namespaces cleaned up"
else
    log_error "Warning: Some namespaces still exist"
    ip netns list | grep -E "ue1|ue2" || true
fi

cd docker
echo ""

# Step 3: Stop gNodeB and FlexRIC
log "Step 3: Stopping gNodeB and FlexRIC..."
docker compose -f docker-compose-gnb.yaml down >> "$LOG_FILE" 2>&1 || true
log_success "gNodeB and FlexRIC stopped"
echo ""

# Step 4: Stop 5G Core Network (Slice 2)
log "Step 4: Stopping 5G Core Network (Slice 2)..."
cd ..
docker compose -f docker-compose-oai-cn-slice2.yaml down >> "$LOG_FILE" 2>&1 || true
log_success "5G Core Network (Slice 2) stopped"
echo ""

# Step 5: Stop 5G Core Network (Slice 1)
log "Step 5: Stopping 5G Core Network (Slice 1)..."
docker compose -f docker-compose-oai-cn-slice1.yaml down >> "$LOG_FILE" 2>&1 || true
log_success "5G Core Network (Slice 1) stopped"
echo ""

# Step 6: Check for remaining containers
log "Step 6: Checking for remaining containers..."
remaining=$(docker ps -q --filter "name=oai-" --filter "name=flexric" --filter "name=influx" --filter "name=grafana" --filter "name=kinetica" --filter "name=streamlit" | wc -l)
if [ "$remaining" -gt 0 ]; then
    log "Found $remaining remaining containers, stopping them..."
    docker ps --filter "name=oai-" --filter "name=flexric" --filter "name=influx" --filter "name=grafana" --filter "name=kinetica" --filter "name=streamlit" --format "{{.Names}}" | xargs -r docker stop >> "$LOG_FILE" 2>&1 || true
    docker ps -a --filter "name=oai-" --filter "name=flexric" --filter "name=influx" --filter "name=grafana" --filter "name=kinetica" --filter "name=streamlit" --format "{{.Names}}" | xargs -r docker rm >> "$LOG_FILE" 2>&1 || true
fi
log_success "All containers stopped and removed"
echo ""

# Step 7: Display final status
log "Step 7: Final Status"
echo ""
running_containers=$(docker ps --filter "name=oai-" --filter "name=flexric" --filter "name=influx" --filter "name=grafana" --filter "name=kinetica" --filter "name=streamlit" --format "{{.Names}}" | wc -l)
if [ "$running_containers" -eq 0 ]; then
    log_success "No lab containers are running"
else
    log_error "Warning: Some containers are still running:"
    docker ps --filter "name=oai-" --filter "name=flexric" --filter "name=influx" --filter "name=grafana" --filter "name=kinetica" --filter "name=streamlit"
fi
echo ""

echo "========================================"
log_success "Lab shutdown completed!"
echo "========================================"
echo ""
echo "To start the lab again: ./lab_start.sh"
echo "Full log: $LOG_FILE"
