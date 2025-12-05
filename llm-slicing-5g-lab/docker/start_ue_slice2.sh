#!/bin/bash
# Script to start UE Slice 2 (oai-ue-slice2) on a running system
# This allows adding the second UE without restarting the entire lab

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log() {
    echo -e "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

log_success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️  $1${NC}"
}

wait_for_healthy() {
    local container=$1
    local timeout=${2:-60}
    local elapsed=0

    log "Waiting for $container to be healthy..."
    while [ $elapsed -lt $timeout ]; do
        if [ "$(docker inspect --format='{{.State.Health.Status}}' $container 2>/dev/null)" = "healthy" ]; then
            return 0
        fi
        sleep 2
        elapsed=$((elapsed + 2))
    done
    return 1
}

echo "========================================"
log "Starting UE Slice 2 (oai-ue-slice2)"
echo "========================================"
echo ""

# Check if oai-ue-slice1 is running
if ! docker ps | grep -q "oai-ue-slice1"; then
    log_error "oai-ue-slice1 is not running! Please start the lab first with lab_start.sh"
    exit 1
fi

# Check if oai-ue-slice2 is already running
if docker ps | grep -q "oai-ue-slice2"; then
    log_warning "oai-ue-slice2 is already running!"
    echo ""
    docker ps --filter "name=oai-ue-slice2" --format "table {{.Names}}\t{{.Status}}"
    exit 0
fi

# Start oai-ue-slice2
log "Starting oai-ue-slice2 container..."
docker compose -f docker-compose-ue-host.yaml up -d oai-ue-slice2

# Wait for it to be healthy
if wait_for_healthy "oai-ue-slice2" 60; then
    log_success "oai-ue-slice2 is running and healthy"
else
    log_error "oai-ue-slice2 failed to become healthy within 60 seconds"
    log "Check logs with: docker logs oai-ue-slice2"
    exit 1
fi

# Check registration
log "Verifying UE registration..."
sleep 10

if docker logs oai-ue-slice2 2>&1 | grep -q "REGISTRATION ACCEPT"; then
    log_success "UE3 successfully registered with 5G Core (Slice 2)"

    # Check for IP address assignment
    if docker logs oai-ue-slice2 2>&1 | grep -q "Interface oaitun_ue3 successfully configured"; then
        ue3_ip=$(docker logs oai-ue-slice2 2>&1 | grep "Interface oaitun_ue3 successfully configured" | tail -1 | grep -oP 'ip address \K[0-9.]+' || echo "unknown")
        log_success "UE3 assigned IP address: $ue3_ip"
    fi
else
    log_warning "UE3 registration not confirmed yet, check logs: docker logs oai-ue-slice2"
fi

# Test connectivity
log "Testing UE3 connectivity..."
sleep 5
if docker exec oai-ue-slice2 ping -I oaitun_ue3 -c 2 8.8.8.8 &>/dev/null; then
    log_success "UE3 has internet connectivity!"
else
    log_warning "UE3 connectivity test failed"
fi

echo ""
echo "========================================"
log_success "UE Slice 2 startup completed!"
echo "========================================"
echo ""
echo "Next steps:"
echo "  1. View UE3 logs: docker logs -f oai-ue-slice2"
echo "  2. Restart traffic generator to use both UE1 and UE3:"
echo "     pkill -f generate_traffic.py"
echo "     cd ../llm-slicing-5g-lab"
echo "     python generate_traffic.py > logs/traffic_generator.log 2>&1 &"
echo ""
