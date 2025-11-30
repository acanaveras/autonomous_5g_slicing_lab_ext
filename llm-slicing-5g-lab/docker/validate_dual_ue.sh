#!/bin/bash

# SPDX-FileCopyrightText: Copyright (c) 2023-2024 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: Apache-2.0
#
# Validation script for dual-UE slicing setup
# Verifies that both UE1 (Slice 1) and UE2 (Slice 2) are functioning correctly

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

PASS_COUNT=0
FAIL_COUNT=0
WARN_COUNT=0

# Test result tracking
test_pass() {
    echo -e "${GREEN}✅ PASS${NC}: $1"
    PASS_COUNT=$((PASS_COUNT + 1))
}

test_fail() {
    echo -e "${RED}❌ FAIL${NC}: $1"
    FAIL_COUNT=$((FAIL_COUNT + 1))
}

test_warn() {
    echo -e "${YELLOW}⚠️  WARN${NC}: $1"
    WARN_COUNT=$((WARN_COUNT + 1))
}

test_info() {
    echo -e "${BLUE}ℹ️  INFO${NC}: $1"
}

echo "========================================"
echo "  Dual-UE Slicing Validation"
echo "========================================"
echo ""

# Test 1: Check if UE1 container is running
echo "[Test 1] Checking UE1 container status..."
if docker ps --format '{{.Names}}' | grep -q "^oai-ue-slice1$"; then
    test_pass "UE1 container (oai-ue-slice1) is running"
else
    test_fail "UE1 container (oai-ue-slice1) is not running"
fi

# Test 2: Check if UE2 container is running
echo "[Test 2] Checking UE2 container status..."
if docker ps --format '{{.Names}}' | grep -q "^oai-ue-slice2$"; then
    test_pass "UE2 container (oai-ue-slice2) is running"
else
    test_fail "UE2 container (oai-ue-slice2) is not running"
fi

# Test 3: Check UE1 registration
echo "[Test 3] Checking UE1 registration with 5G Core..."
if docker logs oai-ue-slice1 2>&1 | grep -q "REGISTRATION ACCEPT"; then
    test_pass "UE1 successfully registered with 5G Core"
else
    test_fail "UE1 not registered with 5G Core"
fi

# Test 4: Check UE2 registration
echo "[Test 4] Checking UE2 registration with 5G Core..."
if docker logs oai-ue-slice2 2>&1 | grep -q "REGISTRATION ACCEPT"; then
    test_pass "UE2 successfully registered with 5G Core"
else
    test_fail "UE2 not registered with 5G Core"
fi

# Test 5: Check UE1 interface and IP
echo "[Test 5] Checking UE1 TUN interface (oaitun_ue1)..."
if docker exec oai-ue-slice1 ip addr show oaitun_ue1 &>/dev/null; then
    UE1_IP=$(docker exec oai-ue-slice1 ip addr show oaitun_ue1 | grep 'inet ' | awk '{print $2}' | cut -d'/' -f1)
    if [ -n "$UE1_IP" ]; then
        test_pass "UE1 TUN interface configured with IP: $UE1_IP"
    else
        test_warn "UE1 TUN interface exists but no IP assigned"
    fi
else
    test_fail "UE1 TUN interface (oaitun_ue1) not found"
fi

# Test 6: Check UE2 interface and IP
echo "[Test 6] Checking UE2 TUN interface (oaitun_ue3)..."
if docker exec oai-ue-slice2 ip addr show oaitun_ue3 &>/dev/null; then
    UE2_IP=$(docker exec oai-ue-slice2 ip addr show oaitun_ue3 | grep 'inet ' | awk '{print $2}' | cut -d'/' -f1)
    if [ -n "$UE2_IP" ]; then
        test_pass "UE2 TUN interface configured with IP: $UE2_IP"
    else
        test_warn "UE2 TUN interface exists but no IP assigned"
    fi
else
    test_fail "UE2 TUN interface (oaitun_ue3) not found"
fi

# Test 7: Check UE1 connectivity
echo "[Test 7] Testing UE1 network connectivity..."
if docker exec oai-ue-slice1 ping -I oaitun_ue1 -c 2 8.8.8.8 &>/dev/null; then
    test_pass "UE1 has internet connectivity"
else
    test_fail "UE1 cannot reach internet (ping failed)"
fi

# Test 8: Check UE2 connectivity
echo "[Test 8] Testing UE2 network connectivity..."
if docker exec oai-ue-slice2 ping -I oaitun_ue3 -c 2 8.8.8.8 &>/dev/null; then
    test_pass "UE2 has internet connectivity"
else
    test_fail "UE2 cannot reach internet (ping failed)"
fi

# Test 9: Check FlexRIC container
echo "[Test 9] Checking FlexRIC container..."
if docker ps --format '{{.Names}}' | grep -q "^flexric$"; then
    test_pass "FlexRIC container is running"

    # Check if slice configuration is visible in logs
    if docker logs flexric 2>&1 | grep -q "SLICE"; then
        test_info "FlexRIC has slice-related logs (configuration likely active)"
    fi
else
    test_fail "FlexRIC container is not running"
fi

# Test 10: Check iperf3 servers
echo "[Test 10] Checking iperf3 servers on external DN..."
IPERF_COUNT=$(docker exec oai-ext-dn pgrep -c iperf3 2>/dev/null || echo "0")
if [ "$IPERF_COUNT" -ge 2 ]; then
    test_pass "iperf3 servers are running ($IPERF_COUNT processes)"
else
    test_warn "Expected 2 iperf3 servers, found $IPERF_COUNT"
fi

# Test 11: Check traffic generator
echo "[Test 11] Checking traffic generator process..."
if pgrep -f "generate_traffic.py" &>/dev/null; then
    test_pass "Traffic generator (generate_traffic.py) is running"

    # Check if logs exist for both UEs
    if [ -f "../logs/UE1_iperfc.log" ]; then
        UE1_LOG_SIZE=$(wc -l < "../logs/UE1_iperfc.log" 2>/dev/null || echo "0")
        if [ "$UE1_LOG_SIZE" -gt 0 ]; then
            test_info "UE1 traffic log has $UE1_LOG_SIZE lines"
        fi
    fi

    if [ -f "../logs/UE2_iperfc.log" ]; then
        UE2_LOG_SIZE=$(wc -l < "../logs/UE2_iperfc.log" 2>/dev/null || echo "0")
        if [ "$UE2_LOG_SIZE" -gt 0 ]; then
            test_info "UE2 traffic log has $UE2_LOG_SIZE lines"
        fi
    else
        test_warn "UE2 traffic log not found (../logs/UE2_iperfc.log)"
    fi
else
    test_warn "Traffic generator not running"
fi

# Test 12: Check monitoring stack
echo "[Test 12] Checking monitoring stack..."
MONITORING_COUNT=0
if docker ps --format '{{.Names}}' | grep -q "influxdb"; then
    MONITORING_COUNT=$((MONITORING_COUNT + 1))
fi
if docker ps --format '{{.Names}}' | grep -q "grafana"; then
    MONITORING_COUNT=$((MONITORING_COUNT + 1))
fi
if docker ps --format '{{.Names}}' | grep -q "kinetica"; then
    MONITORING_COUNT=$((MONITORING_COUNT + 1))
fi

if [ "$MONITORING_COUNT" -ge 2 ]; then
    test_pass "Monitoring stack is running ($MONITORING_COUNT/3 services)"
else
    test_warn "Monitoring stack partially running ($MONITORING_COUNT/3 services)"
fi

# Test 13: Verify network slicing
echo "[Test 13] Verifying network slicing configuration..."
test_info "Checking IMSI and DNN assignments..."

UE1_IMSI="001010000000001"
UE2_IMSI="001010000000002"

if docker logs oai-ue-slice1 2>&1 | grep -q "$UE1_IMSI"; then
    test_info "UE1 using IMSI: $UE1_IMSI (Slice 1)"
fi

if docker logs oai-ue-slice2 2>&1 | grep -q "$UE2_IMSI"; then
    test_info "UE2 using IMSI: $UE2_IMSI (Slice 2)"
fi

# Summary
echo ""
echo "========================================"
echo "  Validation Summary"
echo "========================================"
echo -e "${GREEN}✅ Passed${NC}: $PASS_COUNT"
echo -e "${YELLOW}⚠️  Warnings${NC}: $WARN_COUNT"
echo -e "${RED}❌ Failed${NC}: $FAIL_COUNT"
echo ""

if [ $FAIL_COUNT -eq 0 ]; then
    echo -e "${GREEN}🎉 All critical tests passed!${NC}"
    echo ""
    echo "Next steps:"
    echo "  1. Monitor traffic: tail -f ../logs/UE1_iperfc.log ../logs/UE2_iperfc.log"
    echo "  2. Change bandwidth: ./change_rc_slice_docker.sh 80 20"
    echo "  3. View Grafana: http://localhost:9002 (admin/admin)"
    echo "  4. View Streamlit: http://localhost:8501"
    exit 0
else
    echo -e "${RED}⚠️  Some tests failed. Please check the logs:${NC}"
    echo "  - UE1 logs: docker logs oai-ue-slice1"
    echo "  - UE2 logs: docker logs oai-ue-slice2"
    echo "  - FlexRIC logs: docker logs flexric"
    echo "  - gNodeB logs: docker logs oai-gnb"
    exit 1
fi
