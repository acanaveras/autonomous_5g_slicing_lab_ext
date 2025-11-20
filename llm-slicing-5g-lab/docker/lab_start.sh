#!/bin/bash

# SPDX-FileCopyrightText: Copyright (c) 2023-2024 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: Apache-2.0
#
# Master orchestration script for Autonomous 5G Slicing Lab (Dockerized)
# Starts all components in the correct order with health checks

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

LOG_DIR="$SCRIPT_DIR/../logs"
mkdir -p "$LOG_DIR"

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_FILE="$LOG_DIR/lab_start_${TIMESTAMP}.log"

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

log_warning() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] ⚠️  $1${NC}" | tee -a "$LOG_FILE"
}

# Wait for container to be healthy
wait_for_healthy() {
    local container_name=$1
    local max_attempts=${2:-30}
    local attempt=0

    log "Waiting for $container_name to become healthy..."

    while [ $attempt -lt $max_attempts ]; do
        if docker inspect "$container_name" &>/dev/null; then
            health_status=$(docker inspect --format='{{.State.Health.Status}}' "$container_name" 2>/dev/null || echo "none")

            if [ "$health_status" = "healthy" ]; then
                log_success "$container_name is healthy"
                return 0
            elif [ "$health_status" = "none" ]; then
                # Container has no healthcheck, check if it's running
                if [ "$(docker inspect --format='{{.State.Running}}' "$container_name")" = "true" ]; then
                    log_success "$container_name is running (no healthcheck)"
                    return 0
                fi
            fi
        fi

        attempt=$((attempt + 1))
        sleep 2
    done

    log_error "$container_name did not become healthy in time"
    return 1
}

echo "========================================"
echo "  Autonomous 5G Slicing Lab - Startup"
echo "  Dockerized Version"
echo "========================================"
echo ""
log "Starting lab initialization..."
log "Log file: $LOG_FILE"
echo ""

# Step 0: Build RIC and OAI Network Elements (if not already built)
log "Step 0: Building RIC and OAI Network Elements..."
cd ..
# Check if binaries actually exist, not just directories
if [ -f "flexric/build/examples/ric/nearRT-RIC" ] && [ -f "openairinterface5g/cmake_targets/ran_build/build/nr-softmodem" ]; then
    log_success "RIC and OAI already built, skipping..."
else
    log "Building RIC and OAI Network Elements (this may take 30-60 minutes)..."
    chmod +x build_ric_oai_ne.sh
    ./build_ric_oai_ne.sh 2>&1 | tee -a "$LOG_FILE"
    if [ ${PIPESTATUS[0]} -eq 0 ]; then
        log_success "RIC and OAI Network Elements built successfully"
    else
        log_error "RIC and OAI Network Elements build failed"
        exit 1
    fi
fi
cd docker
echo ""

# Step 0.1: Build FlexRIC Docker Image
log "Step 0.1: Building FlexRIC Docker Image..."
if docker images | grep -q "flexric-5g-slicing"; then
    log_success "FlexRIC image already exists, skipping build..."
else
    log "Building FlexRIC image (this may take 10-15 minutes)..."
    chmod +x build_flexric.sh
    ./build_flexric.sh 2>&1 | tee -a "$LOG_FILE"
    if [ ${PIPESTATUS[0]} -eq 0 ]; then
        log_success "FlexRIC image built successfully"
    else
        log_error "FlexRIC image build failed, check logs"
        exit 1
    fi
fi
echo ""

# Step 0.2: Build gNodeB Docker Image
log "Step 0.2: Building gNodeB Docker Image..."
if docker images | grep -q "oai-gnb-5g-slicing"; then
    log_success "gNodeB image already exists, skipping build..."
else
    log "Building gNodeB image (this may take 15-20 minutes)..."
    chmod +x build_gnb.sh
    ./build_gnb.sh 2>&1 | tee -a "$LOG_FILE"
    if [ ${PIPESTATUS[0]} -eq 0 ]; then
        log_success "gNodeB image built successfully"
    else
        log_error "gNodeB image build failed, check logs"
        exit 1
    fi
fi
echo ""

# Step 0.3: Build UE Docker Image
log "Step 0.3: Building UE Docker Image..."
if docker images | grep -q "oai-ue-5g-slicing"; then
    log_success "UE image already exists, skipping build..."
else
    log "Building UE image (this may take 2-3 minutes)..."
    chmod +x build_ue.sh
    ./build_ue.sh 2>&1 | tee -a "$LOG_FILE"
    if [ ${PIPESTATUS[0]} -eq 0 ]; then
        log_success "UE image built successfully"
    else
        log_error "UE image build failed, check logs"
        exit 1
    fi
fi
echo ""

# Step 0.4: Build Streamlit Docker Image
log "Step 0.4: Building Streamlit UI Docker Image..."
if docker images | grep -q "streamlit-5g-ui"; then
    log_success "Streamlit image already exists, skipping build..."
else
    log "Building Streamlit image (this may take 2-3 minutes)..."
    chmod +x build_streamlit.sh
    ./build_streamlit.sh 2>&1 | tee -a "$LOG_FILE"
    if [ ${PIPESTATUS[0]} -eq 0 ]; then
        log_success "Streamlit image built successfully"
    else
        log_warning "Streamlit image build failed, continuing without it..."
    fi
fi
echo ""

# Step 1: Check if Docker network exists
log "Step 1: Checking Docker network..."
if docker network inspect demo-oai-public-net &>/dev/null; then
    log_success "Docker network demo-oai-public-net exists"
else
    log "Creating Docker network demo-oai-public-net..."
    docker network create \
        --driver=bridge \
        --subnet=192.168.70.128/26 \
        -o "com.docker.network.bridge.name"="demo-oai" \
        demo-oai-public-net
    log_success "Docker network created"
fi
echo ""

# Step 2: Start 5G Core Network (Slice 1)
log "Step 2: Starting 5G Core Network (Slice 1)..."
cd ..
docker-compose -f docker-compose-oai-cn-slice1.yaml up -d >> "$LOG_FILE" 2>&1
wait_for_healthy "oai-amf"
wait_for_healthy "oai-smf-slice1"
wait_for_healthy "oai-upf-slice1"
log_success "5G Core Network (Slice 1) is running"
echo ""

# Step 3: Start 5G Core Network (Slice 2)
log "Step 3: Starting 5G Core Network (Slice 2)..."
docker-compose -f docker-compose-oai-cn-slice2.yaml up -d >> "$LOG_FILE" 2>&1
wait_for_healthy "oai-smf-slice2"
wait_for_healthy "oai-upf-slice2"
log_success "5G Core Network (Slice 2) is running"
echo ""

# Step 4: Start FlexRIC and gNodeB
log "Step 4: Starting FlexRIC and gNodeB..."
cd docker
docker-compose -f docker-compose-gnb.yaml up -d >> "$LOG_FILE" 2>&1
wait_for_healthy "flexric" 60
wait_for_healthy "oai-gnb" 60
log_success "FlexRIC and gNodeB are running"
echo ""

# Step 5: Wait for E2 connection
log "Step 5: Verifying E2 connection between gNodeB and FlexRIC..."
sleep 5
if docker logs oai-gnb 2>&1 | grep -q "E2 SETUP"; then
    log_success "E2 connection established"
else
    log_warning "E2 connection not confirmed, continuing anyway..."
fi
echo ""

# Step 6: Start UE (Slice 1 only for now due to TUN interface limitation)
log "Step 6: Starting UE (Slice 1)..."
docker-compose -f docker-compose-ue-host.yaml up -d oai-ue-slice1 >> "$LOG_FILE" 2>&1
wait_for_healthy "oai-ue-slice1" 60
log_success "UE (Slice 1) is running"
echo ""

# Step 7: Verify UE connection
log "Step 7: Verifying UE connection..."
sleep 10
if docker logs oai-ue-slice1 2>&1 | grep -q "REGISTRATION ACCEPT"; then
    log_success "UE successfully registered with 5G Core"

    # Check for IP address assignment
    if docker logs oai-ue-slice1 2>&1 | grep -q "Interface oaitun_ue1 successfully configured"; then
        ue_ip=$(docker logs oai-ue-slice1 2>&1 | grep "Interface oaitun_ue1 successfully configured" | tail -1 | grep -oP 'ip address \K[0-9.]+')
        log_success "UE assigned IP address: $ue_ip"
    fi
else
    log_warning "UE registration not confirmed, checking logs..."
fi
echo ""

# Step 8: Start Monitoring Stack (Optional)
log "Step 8: Starting Monitoring Stack (InfluxDB, Grafana, Kinetica, Streamlit)..."
if docker-compose -f docker-compose-monitoring.yaml up -d >> "$LOG_FILE" 2>&1; then
    log "Monitoring services starting..."
    wait_for_healthy "influxdb" 60
    wait_for_healthy "grafana" 60
    wait_for_healthy "kinetica" 180
    wait_for_healthy "streamlit" 60
    log_success "Monitoring Stack is running"
else
    log_warning "Failed to start monitoring stack, continuing without it..."
fi
echo ""

# Step 8.1: Start iperf3 servers on external DN
log "Step 8.1: Starting iperf3 servers on external data network..."

# Kill any existing iperf3 servers first
docker exec oai-ext-dn pkill iperf3 2>/dev/null || true
sleep 1

# Start iperf3 servers with IPv4 flag (-4) to ensure proper listening
if docker exec -d oai-ext-dn iperf3 -s -p 5201 -4 >> "$LOG_FILE" 2>&1; then
    log_success "iperf3 server started on port 5201 (IPv4)"
else
    log_error "Failed to start iperf3 server on port 5201"
fi

if docker exec -d oai-ext-dn iperf3 -s -p 5202 -4 >> "$LOG_FILE" 2>&1; then
    log_success "iperf3 server started on port 5202 (IPv4)"
else
    log_error "Failed to start iperf3 server on port 5202"
fi

# Verify iperf3 servers are running
sleep 2
IPERF_PROCS=$(docker exec oai-ext-dn pgrep -c iperf3 || echo "0")
if [ "$IPERF_PROCS" -ge 2 ]; then
    log_success "iperf3 servers verified running ($IPERF_PROCS processes)"
else
    log_warning "Expected 2 iperf3 servers, found $IPERF_PROCS"
fi
echo ""

# Step 8.2: Start traffic generator
log "Step 8.2: Starting traffic generator..."
cd ..
TRAFFIC_LOG="$LOG_DIR/traffic_gen_final.log"
AGENT_LOG="$LOG_DIR/agent.log"

# Kill any existing traffic generator and log streaming
pkill -f "traffic_gen_FINAL.py" 2>/dev/null || true
pkill -f "tail -f.*traffic_gen_final.log" 2>/dev/null || true
sleep 1

# Initialize agent.log with header
echo "=== 5G Network Traffic Generation Log ===" > "$AGENT_LOG"
echo "=== Started: $(date) ===" >> "$AGENT_LOG"
echo "" >> "$AGENT_LOG"
chmod 666 "$AGENT_LOG" 2>/dev/null || true

# Start traffic generator in background
if python3 traffic_gen_FINAL.py > "$TRAFFIC_LOG" 2>&1 &
then
    TRAFFIC_PID=$!
    sleep 3

    # Verify traffic generator is still running
    if kill -0 $TRAFFIC_PID 2>/dev/null; then
        log_success "Traffic generator started (PID: $TRAFFIC_PID)"
        log "Traffic log: $TRAFFIC_LOG"

        # Wait a few seconds and check if traffic is being generated
        sleep 5
        if tail -10 "$TRAFFIC_LOG" | grep -q "Starting iteration\|records inserted"; then
            log_success "Traffic generation confirmed - data flowing to InfluxDB/Kinetica"

            # Start log streaming to agent.log for Streamlit
            tail -f "$TRAFFIC_LOG" >> "$AGENT_LOG" 2>&1 &
            LOG_STREAM_PID=$!
            log_success "Log streaming to Streamlit started (PID: $LOG_STREAM_PID)"
        else
            log_warning "Traffic generator running but no data flow detected yet"
        fi
    else
        log_error "Traffic generator failed to start or crashed immediately"
    fi
else
    log_error "Failed to start traffic generator"
fi
cd docker
echo ""

# Step 9: Display system status
log "Step 9: System Status Summary"
echo ""
echo "Running Containers:"
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep -E "NAME|oai-|flexric|influx|grafana|kinetica|streamlit"
echo ""

# Step 10: Quick connectivity test
log "Step 10: Testing UE connectivity..."
if docker exec oai-ue-slice1 ping -I oaitun_ue1 -c 2 8.8.8.8 &>/dev/null; then
    log_success "UE has internet connectivity!"
else
    log_warning "UE connectivity test failed"
fi
echo ""

echo "========================================"
log_success "Lab startup completed!"
echo "========================================"
echo ""
echo "5G Network Access:"
echo "  - View FlexRIC logs: docker logs -f flexric"
echo "  - View gNodeB logs: docker logs -f oai-gnb"
echo "  - View UE logs: docker logs -f oai-ue-slice1"
echo ""
echo "Traffic Generation:"
echo "  - Traffic generator log: tail -f $TRAFFIC_LOG"
echo "  - iperf3 servers running on: oai-ext-dn (192.168.70.135:5201, 5202)"
echo "  - Stop traffic: pkill -f traffic_gen_FINAL.py"
echo ""
echo "Monitoring & Visualization:"
echo "  - Streamlit UI: http://localhost:8501"
echo "  - Grafana: http://localhost:9002 (admin/admin)"
echo "  - InfluxDB: http://localhost:9001"
echo "  - Kinetica Workbench: http://localhost:8000 (admin/Admin123!)"
echo ""
echo "NOTE: It may take 30-60 seconds for traffic data to appear in Grafana/Streamlit"
echo ""
echo "Management:"
echo "  - Stop the lab: ./lab_stop.sh"
echo "  - Check status: ./lab_status.sh"
echo ""
echo "Full log: $LOG_FILE"
