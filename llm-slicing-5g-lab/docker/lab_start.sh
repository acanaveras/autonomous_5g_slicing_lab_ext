#!/bin/bash

# SPDX-FileCopyrightText: Copyright (c) 2023-2024 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: Apache-2.0
#
# Master orchestration script for Autonomous 5G Slicing Lab (Dockerized)
# Starts all components in the correct order with health checks

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Define root directory dynamically (2 levels up from docker/)
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

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

# Step 1: Install System Build Dependencies
log "Step 1: Checking System Build Dependencies..."
# Check if autoreconf exists, if not, install the suite
if ! command -v autoreconf &> /dev/null; then
    log "Installing autoconf, automake, libtool, autotools, bison, flex, build-essential, cmake"
    # Using sudo as this modifies the system
    sudo apt-get update
    sudo apt-get install -y autoconf automake libtool bison flex build-essential cmake
    
    if [ $? -eq 0 ]; then
        log_success "System build dependencies installed"
    else
        log_error "Failed to install system dependencies. Please run manually."
        exit 1
    fi
else
    log_success "System build dependencies already present"
fi
echo ""

# Step 2: Install Python dependencies
log "Checking Python dependencies..."
# --- ADDED: FIX FOR BROKEN VENV/MISSING PIP ---
log "Ensuring pip is installed and up to date..."
# This fixes the "No module named pip" error
python3 -m ensurepip --upgrade 2>/dev/null || true
# This ensures we have the latest pip
python3 -m pip install --upgrade pip 2>/dev/null || true
# ---------------------------------------------
if [ -f "$ROOT_DIR/requirements.txt" ]; then
    log "Installing Python dependencies from requirements.txt..."
    pip3 install -r "$ROOT_DIR/requirements.txt" 2>&1 | tee -a "$LOG_FILE"
    if [ ${PIPESTATUS[0]} -eq 0 ]; then
        log_success "Python dependencies installed"
    else
        log_warning "Failed to install some Python dependencies"
    fi
else
    log_warning "requirements.txt not found in parent directory"
fi

# --- NAT Wrapper Installation ---
log "Installing NAT (NeMo Agent Toolkit) wrapper..."

# Install uv if not present (faster package installer)
if ! command -v uv &>/dev/null; then
    log "Installing uv package manager..."
    pip3 install uv 2>&1 | tee -a "$LOG_FILE"
    if [ $? -eq 0 ]; then
        log_success "uv installed"
    else
        log_warning "Failed to install uv, falling back to pip"
    fi
fi

# Install NVIDIA NAT with LangChain support
log "Installing nvidia-nat[langchain]..."
if command -v uv &>/dev/null; then
    uv pip install nvidia-nat[langchain] 2>&1 | tee -a "$LOG_FILE"
else
    pip3 install nvidia-nat[langchain] 2>&1 | tee -a "$LOG_FILE"
fi

if [ $? -eq 0 ]; then
    log_success "nvidia-nat[langchain] installed"
else
    log_warning "Failed to install nvidia-nat[langchain]"
fi

# Install NAT wrapper in editable mode
NAT_WRAPPER_DIR="$ROOT_DIR/agentic-llm/nat_wrapper"
if [ -d "$NAT_WRAPPER_DIR" ]; then
    log "Installing nat_5g_slicing wrapper in editable mode..."
    cd "$NAT_WRAPPER_DIR"
    
    # Install Phoenix observability dependencies first
    log "Installing Phoenix observability dependencies..."
    if command -v uv &>/dev/null; then
        # Install specific versions to avoid compatibility issues
        uv pip install "arize-phoenix>=4.0.0" "arize-phoenix-otel>=0.1.0" "openinference-instrumentation-langchain>=0.1.0" 2>&1 | tee -a "$LOG_FILE"
    else
        pip3 install "arize-phoenix>=4.0.0" "arize-phoenix-otel>=0.1.0" "openinference-instrumentation-langchain>=0.1.0" 2>&1 | tee -a "$LOG_FILE"
    fi
    
    if [ $? -eq 0 ]; then
        log_success "Phoenix dependencies installed"
    else
        log_warning "Failed to install Phoenix dependencies"
    fi
    
    # Install NAT wrapper
    if command -v uv &>/dev/null; then
        uv pip install -e . 2>&1 | tee -a "$LOG_FILE"
    else
        pip3 install -e . 2>&1 | tee -a "$LOG_FILE"
    fi
    
    if [ $? -eq 0 ]; then
        log_success "nat_5g_slicing wrapper installed"
    else
        log_warning "Failed to install nat_5g_slicing wrapper"
    fi
    cd "$SCRIPT_DIR"
else
    log_warning "NAT wrapper directory not found at $NAT_WRAPPER_DIR, skipping..."
fi
# --- END NAT Wrapper Installation ---

echo ""

# Step 2: Build RIC and OAI Network Elements (if not already built)
log "Step 3: Building RIC and OAI Network Elements..."
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

# Step 4: Build FlexRIC Docker Image
log "Step 4: Building FlexRIC Docker Image..."
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

# Step 5: Build gNodeB Docker Image
log "Step 5: Building gNodeB Docker Image..."
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

# Step 6: Build UE Docker Image
log "Step 6: Building UE Docker Image..."
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

# Step 7: Build Streamlit Docker Image
log "Step 7: Building Streamlit UI Docker Image..."
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

# Step 8: Check if Docker network exists
log "Step 8: Checking Docker network..."
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

# Step 9: Start 5G Core Network (Slice 1)
log "Step 9: Starting 5G Core Network (Slice 1)..."
cd ..
docker compose -f docker-compose-oai-cn-slice1.yaml up -d 2>&1 | tee -a "$LOG_FILE"
wait_for_healthy "oai-amf"
wait_for_healthy "oai-smf-slice1"
wait_for_healthy "oai-upf-slice1"
log_success "5G Core Network (Slice 1) is running"
echo ""

# Step 10: Start 5G Core Network (Slice 2)
log "Step 10: Starting 5G Core Network (Slice 2)..."
docker compose -f docker-compose-oai-cn-slice2.yaml up -d 2>&1 | tee -a "$LOG_FILE"
wait_for_healthy "oai-smf-slice2"
wait_for_healthy "oai-upf-slice2"
log_success "5G Core Network (Slice 2) is running"
echo ""

# Step 11: Start FlexRIC and gNodeB
log "Step 11: Starting FlexRIC and gNodeB..."
cd docker
docker compose -f docker-compose-gnb.yaml up -d 2>&1 | tee -a "$LOG_FILE"
wait_for_healthy "flexric" 60
wait_for_healthy "oai-gnb" 60
log_success "FlexRIC and gNodeB are running"
echo ""

# Step 12: Wait for E2 connection
log "Step 12: Verifying E2 connection between gNodeB and FlexRIC..."
sleep 5
if docker logs oai-gnb 2>&1 | grep -q "E2 SETUP"; then
    log_success "E2 connection established"
else
    log_warning "E2 connection not confirmed, continuing anyway..."
fi
echo ""

# Step 13: Create network namespace for UE1
log "Step 13: Creating network namespace for UE1..."
cd ..  # Go to project root where multi_ue.sh is located

# Check if namespace already exists
if sudo ip netns list | grep -q "ue1"; then
    log_warning "Network namespace 'ue1' already exists, deleting and recreating..."
    sudo ./multi_ue.sh -d 1 2>/dev/null || true
    sleep 1
fi

if sudo ./multi_ue.sh -c1 >> "$LOG_FILE" 2>&1; then
    log_success "Network namespace 'ue1' created"
else
    log_error "Failed to create network namespace 'ue1'"
    cd docker
    exit 1
fi
echo ""

# Step 13b: Start UE1 in network namespace
log "Starting UE1 in network namespace 'ue1'..."
sudo ip netns exec ue1 bash -c \
    "LD_LIBRARY_PATH=. ./openairinterface5g/cmake_targets/ran_build/build/nr-uesoftmodem \
    --rfsimulator.serveraddr 10.201.1.100 \
    -r 106 \
    --numerology 1 \
    --band 78 \
    -C 3619200000 \
    --rfsim \
    --sa \
    -O ran-conf/ue_1.conf \
    -E" > "$LOG_DIR/UE1.log" 2>&1 &

UE1_PID=$!
log_success "UE1 started with PID $UE1_PID in namespace 'ue1'"
sleep 10
echo ""

# Step 14: Create network namespace for UE3
log "Step 14: Creating network namespace for UE3..."

# Check if namespace already exists
if sudo ip netns list | grep -q "ue3"; then
    log_warning "Network namespace 'ue3' already exists, deleting and recreating..."
    sudo ./multi_ue.sh -d 3 2>/dev/null || true
    sleep 1
fi

if sudo ./multi_ue.sh -c3 >> "$LOG_FILE" 2>&1; then
    log_success "Network namespace 'ue3' created"
else
    log_error "Failed to create network namespace 'ue3'"
    cd docker
    exit 1
fi
echo ""

# Step 14b: Start UE3 in network namespace
log "Starting UE3 in network namespace 'ue3'..."
sudo ip netns exec ue3 bash -c \
    "LD_LIBRARY_PATH=. ./openairinterface5g/cmake_targets/ran_build/build/nr-uesoftmodem \
    --rfsimulator.serveraddr 10.203.1.100 \
    -r 106 \
    --numerology 1 \
    --band 78 \
    -C 3619200000 \
    --rfsim \
    --sa \
    -O ran-conf/ue_2.conf \
    -E" > "$LOG_DIR/UE2.log" 2>&1 &

UE3_PID=$!
log_success "UE3 started with PID $UE3_PID in namespace 'ue3'"
sleep 10
echo ""

# Step 14c: Verify both UE connections
log "Verifying UE registrations..."
sleep 5

UE1_REGISTERED=false
UE3_REGISTERED=false

# Check UE1 registration
if grep -q "REGISTRATION ACCEPT" "$LOG_DIR/UE1.log" 2>/dev/null; then
    log_success "UE1 successfully registered with 5G Core"
    UE1_REGISTERED=true

    # Check for IP assignment
    if grep -q "Interface oaitun_ue1 successfully configured" "$LOG_DIR/UE1.log"; then
        ue1_ip=$(grep "Interface oaitun_ue1 successfully configured" "$LOG_DIR/UE1.log" | tail -1 | grep -oP 'ip address \K[0-9.]+' || echo "12.1.1.2")
        log_success "UE1 assigned IP address: $ue1_ip"
    fi
else
    log_warning "UE1 registration not confirmed yet, check $LOG_DIR/UE1.log"
fi

# Check UE3 registration
if grep -q "REGISTRATION ACCEPT" "$LOG_DIR/UE2.log" 2>/dev/null; then
    log_success "UE3 successfully registered with 5G Core"
    UE3_REGISTERED=true

    # Check for IP assignment
    if grep -q "Interface oaitun_ue3 successfully configured" "$LOG_DIR/UE2.log"; then
        ue3_ip=$(grep "Interface oaitun_ue3 successfully configured" "$LOG_DIR/UE2.log" | tail -1 | grep -oP 'ip address \K[0-9.]+' || echo "12.1.1.130")
        log_success "UE3 assigned IP address: $ue3_ip"
    fi
else
    log_warning "UE3 registration not confirmed yet, check $LOG_DIR/UE2.log"
fi

if [ "$UE1_REGISTERED" = true ] && [ "$UE3_REGISTERED" = true ]; then
    log_success "Both UEs successfully registered!"
elif [ "$UE1_REGISTERED" = true ] || [ "$UE3_REGISTERED" = true ]; then
    log_warning "At least one UE registered, continuing..."
else
    log_error "Neither UE registered successfully"
    log "Check logs at:"
    log "  - $LOG_DIR/UE1.log"
    log "  - $LOG_DIR/UE2.log"
fi

cd docker  # Return to docker directory
echo ""

# Step 15: Start Monitoring Stack (Optional)
log "Step 15: Starting Monitoring Stack (InfluxDB, Grafana, Kinetica, Streamlit)..."
if docker compose -f docker-compose-monitoring.yaml up -d 2>&1 | tee -a "$LOG_FILE"; then
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

# Step 16: Start iperf3 servers on external DN
log "Step 16: Starting iperf3 servers on external data network..."

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

# Step 17: Start traffic generator (FIXED VERSION with real iperf3 for both UEs)
log "Step 17: Starting traffic generator..."
cd ..
TRAFFIC_LOG="$LOG_DIR/traffic_gen_final.log"
AGENT_LOG="$LOG_DIR/agent.log"

# Kill any existing traffic generator and log streaming
pkill -f "generate_traffic.*.py" 2>/dev/null || true
pkill -f "tail -f.*traffic_gen_final.log" 2>/dev/null || true
sleep 1

# Initialize agent.log with header
echo "=== 5G Network Traffic Generation Log ===" > "$AGENT_LOG"
echo "=== Started: $(date) ===" >> "$AGENT_LOG"
echo "" >> "$AGENT_LOG"
chmod 666 "$AGENT_LOG" 2>/dev/null || true

# Determine which traffic generator to use
if [ -f "generate_traffic_fixed.py" ]; then
    TRAFFIC_SCRIPT="generate_traffic_fixed.py"
    log "Using FIXED traffic generator (real iperf3 for both UEs)"
elif [ -f "generate_traffic.py" ]; then
    TRAFFIC_SCRIPT="generate_traffic.py"
    log_warning "Using OLD traffic generator (may have simulated UE3)"
else
    log_error "No traffic generator script found!"
    cd docker
    exit 1
fi

# Start traffic generator in background (needs sudo for network namespaces)
if sudo python3 "$TRAFFIC_SCRIPT" > "$TRAFFIC_LOG" 2>&1 &
then
    TRAFFIC_PID=$!
    sleep 3

    # Verify traffic generator is still running
    if kill -0 $TRAFFIC_PID 2>/dev/null; then
        log_success "Traffic generator started (PID: $TRAFFIC_PID)"
        log "Traffic script: $TRAFFIC_SCRIPT"
        log "Traffic log: $TRAFFIC_LOG"

        # Wait a few seconds and check if traffic is being generated
        sleep 5
        if tail -10 "$TRAFFIC_LOG" | grep -q "ITERATION\|Starting iperf3\|records inserted"; then
            log_success "Traffic generation confirmed - data flowing to InfluxDB/Kinetica"

            # Start log streaming to agent.log for Streamlit
            tail -f "$TRAFFIC_LOG" >> "$AGENT_LOG" 2>&1 &
            LOG_STREAM_PID=$!
            log_success "Log streaming to Streamlit started (PID: $LOG_STREAM_PID)"
        else
            log_warning "Traffic generator running but no data flow detected yet"
            log "Check namespace verification in logs"
        fi
    else
        log_error "Traffic generator failed to start or crashed immediately"
        log "Check $TRAFFIC_LOG for errors"
    fi
else
    log_error "Failed to start traffic generator"
    log "Make sure network namespaces exist: sudo ip netns list"
fi
cd docker
echo ""

# Step 18: Start AI Agents (LangGraph)
log "Step 18: Starting AI Agents for autonomous network slicing..."
cd "$ROOT_DIR/agentic-llm"

# Create logs directory for agents with correct permissions
mkdir -p logs
sudo chmod 777 logs 2>/dev/null || chmod 777 logs
# Create agent.log with write permissions for all users
touch logs/agent.log 2>/dev/null || sudo touch logs/agent.log
sudo chmod 666 logs/agent.log 2>/dev/null || chmod 666 logs/agent.log

# Kill any existing agent process
pkill -f "langgraph_agent.py" 2>/dev/null || true
sleep 1

# Clear Python cache to ensure latest code is loaded
find . -type d -name __pycache__ -exec rm -rf {} + 2>/dev/null || true

# Start AI agents in background
AGENT_SCRIPT_LOG="$LOG_DIR/langgraph_agent.log"
if nohup python3 langgraph_agent.py > "$AGENT_SCRIPT_LOG" 2>&1 &
then
    AGENT_PID=$!
    sleep 3

    # Verify agent is still running
    if kill -0 $AGENT_PID 2>/dev/null; then
        log_success "AI Agents started (PID: $AGENT_PID)"
        log "Agent log: logs/agent.log"
        log "Agent script log: $AGENT_SCRIPT_LOG"
    else
        log_error "AI Agents failed to start, check $AGENT_SCRIPT_LOG for errors"
    fi
else
    log_error "Failed to start AI Agents"
fi

cd "$SCRIPT_DIR"
echo ""

# Step 19: Display system status
log "Step 19: System Status Summary"
echo ""
echo "Running Containers:"
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep -E "NAME|oai-|flexric|influx|grafana|kinetica|streamlit"
echo ""

# Step 19: Quick connectivity test
log "Step 19: Testing UE connectivity..."
if docker exec oai-ue-slice1 ping -I oaitun_ue1 -c 2 8.8.8.8 &>/dev/null; then
    log_success "UE has internet connectivity!"
else
    log_warning "UE connectivity test failed"
fi
echo ""

# Step 20: Start NAT Server (after all infrastructure is ready)
log "Step 20: Starting NAT Server with Phoenix observability..."
log "Note: NAT requires full system initialization (5G network + Kinetica)"

# Kill any existing NAT server process
pkill -f "nat serve" 2>/dev/null || true
sleep 1

# Ensure port 4999 is free (kill any process using it)
if lsof -ti:4999 > /dev/null 2>&1; then
    log "Port 4999 in use, killing process..."
    lsof -ti:4999 | xargs kill -9 2>/dev/null || true
    sleep 2
fi

# Create logs directory for NAT server
NAT_LOG_DIR="$ROOT_DIR/agentic-llm/nat_wrapper/logs"
mkdir -p "$NAT_LOG_DIR"

# Create profiles directory for NAT server
NAT_PROFILES_DIR="$ROOT_DIR/agentic-llm/nat_wrapper/profiles"
mkdir -p "$NAT_PROFILES_DIR"
chmod 755 "$NAT_PROFILES_DIR" 2>/dev/null || true

# Set NAT server configuration
NAT_CONFIG_FILE="$ROOT_DIR/agentic-llm/nat_wrapper/src/nat_5g_slicing/configs/config.yml"
NAT_LOG_FILE="$NAT_LOG_DIR/nat_server.log"

# Enable Phoenix observability for NAT server
export PHOENIX_ENABLED=true
export PHOENIX_ENDPOINT=http://0.0.0.0:6006

# Start NAT server in background with Phoenix enabled
cd "$ROOT_DIR/agentic-llm/nat_wrapper"

log "Starting NAT server with Phoenix observability enabled..."

if PHOENIX_ENABLED=true PHOENIX_ENDPOINT=http://0.0.0.0:6006 nohup nat serve \
    --config_file "$NAT_CONFIG_FILE" \
    --host 0.0.0.0 \
    --port 4999 > "$NAT_LOG_FILE" 2>&1 &
then
    NAT_PID=$!
    sleep 3

    # Verify NAT server is still running
    if kill -0 $NAT_PID 2>/dev/null; then
        log_success "NAT server started on port 4999 (PID: $NAT_PID)"
        log "NAT server log: $NAT_LOG_FILE"

        # Check for Phoenix initialization in logs
        sleep 2
        if grep -q "Phoenix observability enabled\|To view the Phoenix app" "$NAT_LOG_FILE" 2>/dev/null; then
            log_success "Phoenix launched with NAT server"
            log_success "Phoenix UI: http://localhost:6006"
            log "Note: Phoenix is embedded with NAT and will stop when NAT stops"
        else
            log_warning "Phoenix observability may not be enabled (check $NAT_LOG_FILE)"
        fi

        # Wait for NAT server to be fully initialized
        log "Waiting for NAT server to be ready (may take 30-60 seconds)..."
        NAT_READY=false

        for i in {1..30}; do
            if curl -s http://localhost:4999/health > /dev/null 2>&1; then
                log_success "NAT server is ready and responding"
                NAT_READY=true
                break
            fi

            # Show progress every 5 seconds
            if [ $((i % 5)) -eq 0 ]; then
                log "Still waiting for NAT... ($i/30 attempts)"
            fi

            sleep 2
        done

        if [ "$NAT_READY" = false ]; then
            log_warning "NAT health check timed out after 60 seconds"
            log "NAT may still be initializing. Check: curl http://localhost:4999/health"
            log "Monitor logs: tail -f $NAT_LOG_FILE"
        fi
    else
        log_error "NAT server failed to start, check $NAT_LOG_FILE for errors"
    fi
else
    log_error "Failed to start NAT server"
fi

cd "$SCRIPT_DIR"
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
echo "  - Stop traffic: pkill -f generate_traffic.py"
echo ""
echo "NAT Server & Observability:"
echo "  - NAT Server API: http://localhost:4999 (NeMo Agent Toolkit)"
echo "  - NAT Server logs: tail -f $ROOT_DIR/agentic-llm/nat_wrapper/logs/nat_server.log"
echo "  - Phoenix UI: http://localhost:6006 (Observability & Tracing - embedded with NAT)"
echo "  - Phoenix Status: Automatically launched with NAT server"
echo ""
echo "Management Commands:"
echo "  - Stop NAT + Phoenix: pkill -f 'nat serve' (stops both NAT and Phoenix)"
echo "  - Restart NAT + Phoenix: cd $ROOT_DIR/agentic-llm/nat_wrapper && PHOENIX_ENABLED=true nat serve --config_file src/nat_5g_slicing/configs/config.yml --port 4999"
echo ""
echo "Note: Phoenix is embedded with NAT. Stopping NAT will also stop Phoenix."
echo ""
echo "Monitoring & Visualization:"
echo "  - Streamlit UI: http://localhost:8501 (click 'Start Monitoring' to view AI agent logs)"
echo "  - Grafana: http://localhost:9002 (admin/admin)"
echo "  - InfluxDB: http://localhost:9001"
echo "  - Kinetica Workbench: http://localhost:8000 (admin/admin)"
echo ""
echo "AI Agents (Autonomous Network Slicing):"
echo "  - Agent logs: tail -f ../agentic-llm/logs/agent.log"
echo "  - Agent script log: tail -f $AGENT_SCRIPT_LOG"
echo "  - Agents monitor packet loss and automatically reconfigure network slices"
echo "  - Packet loss threshold: 1.5%, Check interval: 10 seconds"
echo ""
echo "NOTE: It may take 30-60 seconds for traffic data to appear in Grafana/Streamlit"
echo ""
echo "Management:"
echo "  - Stop the lab: ./lab_stop.sh"
echo "  - Check status: ./lab_status.sh"
echo ""
echo "Full log: $LOG_FILE"
