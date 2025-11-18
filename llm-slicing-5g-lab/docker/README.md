# Autonomous 5G Slicing Lab - Dockerized Version

## Overview

This directory contains the complete Dockerized infrastructure for the Autonomous 5G Network Slicing Lab. All components have been containerized for simplified deployment, testing, and development.

## Architecture

The lab consists of the following Docker-based components:

```
┌─────────────────────────────────────────────────────────────┐
│                    5G Network Slicing Lab                    │
├─────────────────────────────────────────────────────────────┤
│                                                               │
│  ┌──────────────┐     ┌──────────────┐                      │
│  │   FlexRIC    │────▶│    gNodeB    │                      │
│  │   (RIC)      │ E2  │    (RAN)     │                      │
│  └──────────────┘     └──────┬───────┘                      │
│                              │ RF Simulator                  │
│                        ┌─────┴─────┐                        │
│                        │           │                         │
│                  ┌─────▼────┐ ┌───▼──────┐                  │
│                  │ UE Slice1│ │ UE Slice2│                  │
│                  │ (IMSI 01)│ │ (IMSI 02)│                  │
│                  └─────┬────┘ └───┬──────┘                  │
│                        │          │                          │
│  ┌─────────────────────┴──────────┴───────────────────┐     │
│  │           5G Core Network (Cloud Native)            │     │
│  ├──────────────────────────────────────────────────────┤   │
│  │  AMF │ SMF-S1 │ SMF-S2 │ UPF-S1 │ UPF-S2 │ AUSF ...│   │
│  └──────────────────────────────────────────────────────┘   │
│                                                               │
│  Network Slices:                                             │
│    • Slice 1: SST=1, SD=0x000001, DNN=oai                   │
│    • Slice 2: SST=1, SD=0x000005, DNN=oai2                  │
└───────────────────────────────────────────────────────────────┘
```

## Components

### Core Network (5G SA)
- **AMF**: Access and Mobility Management Function
- **SMF (x2)**: Session Management Function (one per slice)
- **UPF (x2)**: User Plane Function (one per slice)
- **AUSF**: Authentication Server Function
- **UDM**: Unified Data Management
- **UDR**: Unified Data Repository
- **NRF**: Network Repository Function
- **NSSF**: Network Slice Selection Function

### RAN (Radio Access Network)
- **FlexRIC**: Near-RT RIC with E2 interface support
- **gNodeB**: 5G base station with multi-slice support

### User Equipment
- **UE Slice 1**: Connected to Slice 1 (DNN: oai)
- **UE Slice 2**: Connected to Slice 2 (DNN: oai2)

## Quick Start

### Prerequisites
- Docker Engine 20.10+
- Docker Compose 1.29+
- At least 8GB RAM
- 50GB disk space

### Starting the Lab

```bash
cd /home/ubuntu/autonomous_5g_slicing_lab_ext/llm-slicing-5g-lab/docker

# Start all components
./lab_start.sh
```

The script will:
1. Create the Docker network
2. Start 5G Core Network (both slices)
3. Start FlexRIC and gNodeB
4. Wait for E2 connection establishment
5. Start UE and verify registration
6. Test end-to-end connectivity

### Checking Status

```bash
./lab_status.sh
```

This displays:
- Health status of all containers
- Network configuration
- E2 connection status
- UE registration status
- Resource usage

### Stopping the Lab

```bash
./lab_stop.sh
```

## Container Images

### Pre-built Images
- `oaisoftwarealliance/oai-amf:v2.1.0`
- `oaisoftwarealliance/oai-smf:v2.1.0`
- `oaisoftwarealliance/oai-upf:v2.1.0`
- And other OAI 5G Core components

### Custom Built Images
- `flexric-5g-slicing:latest` - FlexRIC with all Service Modules
- `oai-gnb-5g-slicing:latest` - gNodeB with E2 agent
- `oai-ue-5g-slicing:latest` - User Equipment simulator

## Building Custom Images

### FlexRIC
```bash
./build_flexric.sh
```

### gNodeB
```bash
./build_gnb.sh
```

### UE
```bash
./build_ue.sh
```

## Network Configuration

### Docker Network
- **Name**: `demo-oai-public-net`
- **Subnet**: `192.168.70.128/26`
- **Type**: Bridge

### IP Assignments
- gNodeB: `192.168.70.151`
- FlexRIC: `192.168.70.152`
- Core Network components: `192.168.70.128-150`
- UEs: Use host networking with dynamic IPs from 5G Core

## Network Slices

### Slice 1 (eMBB - Enhanced Mobile Broadband)
- **S-NSSAI**: SST=1, SD=0x000001
- **DNN**: oai
- **UE**: IMSI 001010000000001
- **Characteristics**: Standard connectivity

### Slice 2 (URLLC-like - Custom Slice)
- **S-NSSAI**: SST=1, SD=0x000005
- **DNN**: oai2
- **UE**: IMSI 001010000000002
- **Characteristics**: Separate slice with independent resources

## Testing

### Verify UE Connectivity
```bash
# Test UE Slice 1 internet access
docker exec oai-ue-slice1 ping -I oaitun_ue1 -c 4 8.8.8.8

# Check UE IP address
docker logs oai-ue-slice1 2>&1 | grep "Interface oaitun_ue1 successfully configured"
```

### View Logs
```bash
# FlexRIC logs
docker logs -f flexric

# gNodeB logs
docker logs -f oai-gnb

# UE logs
docker logs -f oai-ue-slice1

# Core Network logs
docker logs -f oai-amf
docker logs -f oai-smf-slice1
```

### E2 Interface Testing
```bash
# Check E2 connection
docker logs oai-gnb 2>&1 | grep "E2 SETUP"

# View FlexRIC Service Modules
docker exec flexric ls /usr/local/lib/flexric/
```

## Troubleshooting

### Container not starting
```bash
# Check container status
docker ps -a | grep <container-name>

# View detailed logs
docker logs <container-name>

# Inspect container
docker inspect <container-name>
```

### UE not connecting
```bash
# Verify gNodeB RF simulator is running
docker logs oai-gnb 2>&1 | grep "rfsimulator"

# Check UE configuration
docker exec oai-ue-slice1 cat /opt/oai-ue/etc/ue.conf

# Verify network connectivity
docker exec oai-ue-slice1 ping 192.168.70.151
```

### E2 connection issues
```bash
# Check FlexRIC is listening
docker exec flexric netstat -ln | grep 36421

# Verify gNodeB E2 agent
docker logs oai-gnb 2>&1 | grep "E2"
```

## File Structure

```
docker/
├── README.md                          # This file
├── lab_start.sh                       # Master startup script
├── lab_stop.sh                        # Shutdown script
├── lab_status.sh                      # Status monitoring script
│
├── build_flexric.sh                   # FlexRIC build script
├── build_gnb.sh                       # gNodeB build script
├── build_ue.sh                        # UE build script
│
├── Dockerfile.flexric                 # FlexRIC container image
├── Dockerfile.gnb                     # gNodeB container image
├── Dockerfile.ue                      # UE container image
│
├── docker-compose-gnb.yaml            # FlexRIC + gNodeB orchestration
├── docker-compose-ue-host.yaml        # UE orchestration (host networking)
│
├── gnb-docker.conf                    # gNodeB configuration
├── ue-slice1.conf                     # UE Slice 1 configuration
├── ue-slice2.conf                     # UE Slice 2 configuration
│
└── flexric-sm/                        # FlexRIC Service Module libraries
    ├── libkpm_sm.so
    ├── librc_sm.so
    └── ... (8 Service Modules total)
```

## Known Limitations

1. **Multiple UEs with Host Networking**: Both UEs attempt to create the same TUN interface. Currently, only UE Slice 1 runs by default. To run UE Slice 2, stop UE Slice 1 first or implement network namespace isolation.

2. **RF Simulator**: Uses host networking mode for proper TCP connection between gNodeB and UE. Bridge networking mode has connection issues with OAI RF simulator.

## Advanced Usage

### Running Traffic Tests
```bash
# Generate downlink traffic
docker exec oai-ue-slice1 iperf3 -c 8.8.8.8 -B 12.1.1.x -t 30

# Monitor throughput
docker stats oai-ue-slice1 oai-gnb
```

### Slice-specific Resource Control
FlexRIC can be used to dynamically adjust slice resources. See FlexRIC documentation for xApp development.

### Modifying Network Parameters
- gNodeB config: Edit `gnb-docker.conf`
- UE config: Edit `ue-slice1.conf` or `ue-slice2.conf`
- Rebuild affected containers after configuration changes

## Support and Documentation

- **OAI 5G Core**: https://gitlab.eurecom.fr/oai/cn5g
- **OAI RAN**: https://gitlab.eurecom.fr/oai/openairinterface5g
- **FlexRIC**: https://gitlab.eurecom.fr/mosaic5g/flexric

## License

SPDX-License-Identifier: Apache-2.0

Copyright (c) 2023-2024 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
