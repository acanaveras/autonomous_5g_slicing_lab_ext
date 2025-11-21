#!/bin/bash

# SPDX-FileCopyrightText: Copyright (c) 2023-2024 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: Apache-2.0
#
# Status monitoring script for Autonomous 5G Slicing Lab (Dockerized)

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Function to check container status
check_container() {
    local container_name=$1
    local component_label=$2

    if docker inspect "$container_name" &>/dev/null; then
        is_running=$(docker inspect --format='{{.State.Running}}' "$container_name")
        health_status=$(docker inspect --format='{{.State.Health.Status}}' "$container_name" 2>/dev/null || echo "none")

        if [ "$is_running" = "true" ]; then
            if [ "$health_status" = "healthy" ]; then
                echo -e "${GREEN}●${NC} $component_label: ${GREEN}Running (Healthy)${NC}"
                return 0
            elif [ "$health_status" = "unhealthy" ]; then
                echo -e "${RED}●${NC} $component_label: ${YELLOW}Running (Unhealthy)${NC}"
                return 1
            elif [ "$health_status" = "starting" ]; then
                echo -e "${YELLOW}●${NC} $component_label: ${YELLOW}Running (Starting...)${NC}"
                return 2
            else
                echo -e "${GREEN}●${NC} $component_label: ${GREEN}Running${NC}"
                return 0
            fi
        else
            echo -e "${RED}○${NC} $component_label: ${RED}Stopped${NC}"
            return 1
        fi
    else
        echo -e "${RED}○${NC} $component_label: ${RED}Not Found${NC}"
        return 1
    fi
}

# Function to get container IP
get_container_ip() {
    docker inspect --format='{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$1" 2>/dev/null || echo "N/A"
}

# Function to check E2 connection
check_e2_connection() {
    if docker logs oai-gnb 2>&1 | tail -100 | grep -q "E2 SETUP"; then
        echo -e "${GREEN}✓${NC} E2 Connection: ${GREEN}Established${NC}"
        return 0
    else
        echo -e "${YELLOW}✗${NC} E2 Connection: ${YELLOW}Not confirmed${NC}"
        return 1
    fi
}

# Function to check UE registration
check_ue_registration() {
    local ue_name=$1
    if docker logs "$ue_name" 2>&1 | tail -100 | grep -q "REGISTRATION ACCEPT"; then
        # Get UE IP address
        ue_ip=$(docker logs "$ue_name" 2>&1 | grep "Interface oaitun_ue1 successfully configured" | tail -1 | grep -oP 'ip address \K[0-9.]+' || echo "N/A")
        echo -e "${GREEN}✓${NC} $ue_name Registration: ${GREEN}Registered${NC} (IP: $ue_ip)"
        return 0
    else
        echo -e "${YELLOW}✗${NC} $ue_name Registration: ${YELLOW}Not registered${NC}"
        return 1
    fi
}

# Header
echo "========================================"
echo "  Autonomous 5G Slicing Lab - Status"
echo "  Dockerized Version"
echo "========================================"
echo ""
echo -e "${CYAN}System Status as of $(date)${NC}"
echo ""

# Network Status
echo -e "${BLUE}═══ Docker Network ═══${NC}"
if docker network inspect demo-oai-public-net &>/dev/null; then
    echo -e "${GREEN}✓${NC} demo-oai-public-net: ${GREEN}Present${NC}"
else
    echo -e "${RED}✗${NC} demo-oai-public-net: ${RED}Missing${NC}"
fi
echo ""

# 5G Core Network (Slice 1)
echo -e "${BLUE}═══ 5G Core Network (Slice 1) ═══${NC}"
check_container "mysql" "MySQL Database"
check_container "oai-nrf" "NRF (Network Repository Function)"
check_container "oai-udr" "UDR (Unified Data Repository)"
check_container "oai-udm" "UDM (Unified Data Management)"
check_container "oai-ausf" "AUSF (Authentication Server Function)"
check_container "oai-amf" "AMF (Access and Mobility Management)"
check_container "oai-smf-slice1" "SMF Slice 1"
check_container "oai-upf-slice1" "UPF Slice 1"
echo ""

# 5G Core Network (Slice 2)
echo -e "${BLUE}═══ 5G Core Network (Slice 2) ═══${NC}"
check_container "oai-smf-slice2" "SMF Slice 2"
check_container "oai-upf-slice2" "UPF Slice 2"
echo ""

# RAN Components
echo -e "${BLUE}═══ RAN Components ═══${NC}"
check_container "flexric" "FlexRIC"
check_container "oai-gnb" "gNodeB"
check_e2_connection
echo ""

# UE Components
echo -e "${BLUE}═══ User Equipment ═══${NC}"
check_container "oai-ue-slice1" "UE Slice 1"
if docker inspect "oai-ue-slice1" &>/dev/null && [ "$(docker inspect --format='{{.State.Running}}' oai-ue-slice1)" = "true" ]; then
    check_ue_registration "oai-ue-slice1"
fi

check_container "oai-ue-slice2" "UE Slice 2"
if docker inspect "oai-ue-slice2" &>/dev/null && [ "$(docker inspect --format='{{.State.Running}}' oai-ue-slice2)" = "true" ]; then
    check_ue_registration "oai-ue-slice2"
fi
echo ""

# Monitoring & Visualization Stack
echo -e "${BLUE}═══ Monitoring & Visualization ═══${NC}"
check_container "influxdb" "InfluxDB (Metrics Database)"
check_container "grafana" "Grafana (Dashboards)"
check_container "kinetica" "Kinetica (Analytics Database)"
check_container "streamlit" "Streamlit (Web UI)"
echo ""

# Container Resource Usage
echo -e "${BLUE}═══ Resource Usage ═══${NC}"
docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}" | grep -E "NAME|oai-|flexric|influx|grafana|kinetica|streamlit" | head -15
echo ""

# Quick Summary
echo -e "${BLUE}═══ Quick Summary ═══${NC}"
total_containers=$(docker ps -a --filter "name=oai-" --filter "name=flexric" --filter "name=mysql" --filter "name=influx" --filter "name=grafana" --filter "name=kinetica" --filter "name=streamlit" | wc -l)
running_containers=$(docker ps --filter "name=oai-" --filter "name=flexric" --filter "name=mysql" --filter "name=influx" --filter "name=grafana" --filter "name=kinetica" --filter "name=streamlit" | wc -l)
echo "Total lab containers: $((total_containers - 1))"  # Subtract header line
echo "Running containers: $((running_containers - 1))"
echo ""

# Suggested actions
if [ "$((running_containers - 1))" -lt 10 ]; then
    echo -e "${YELLOW}⚠️  Not all components are running. Start the lab with: ./lab_start.sh${NC}"
elif [ "$((running_containers - 1))" -gt 0 ]; then
    echo -e "${GREEN}✓ Lab is operational!${NC}"
    echo ""
    echo "5G Network:"
    echo "  - View logs: docker logs -f <container-name>"
    echo "  - Test UE connectivity: docker exec oai-ue-slice1 ping -I oaitun_ue1 -c 4 8.8.8.8"
    echo ""
    echo "Monitoring & Visualization:"
    echo "  - Streamlit UI: http://localhost:8501"
    echo "  - Grafana: http://localhost:9002 (admin/admin)"
    echo "  - InfluxDB: http://localhost:9001"
    echo "  - Kinetica Workbench: http://localhost:8000 (admin/Admin123!)"
    echo ""
    echo "Management:"
    echo "  - Stop lab: ./lab_stop.sh"
fi
