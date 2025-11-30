# 5G Network Simulator Lab with Agentic Workflow

This project demonstrates autonomous 5G network slicing with AI-driven bandwidth allocation using two User Equipment (UE) instances connected to separate network slices.

## Features

- **Dual-UE Setup**: Two UEs (UE1 and UE2) each connected to separate network slices
- **Dynamic Bandwidth Allocation**: Real-time slice bandwidth control (50/50 default split)
- **AI-Driven Optimization**: Agentic workflow for intelligent bandwidth management
- **Real-Time Monitoring**: InfluxDB, Grafana, and Kinetica integration
- **Traffic Generation**: Automated iperf3 traffic generation for both UEs

## Quick Start

### 1. Clone the Project
```bash
git clone https://github.com/acanaveras/autonomous_5g_slicing_lab_ext.git
cd autonomous_5g_slicing_lab_ext
```

### 2. Configure Environment
```bash
# Copy the example environment file
cp .env.example .env

# Edit .env and add your credentials:
# - NVIDIA_API_KEY
# - GRAFANA_DASHBOARD_ID
```

### 3. Start the Lab
```bash
./llm-slicing-5g-lab/docker/lab_start.sh
```

This will:
- Build and start all 5G Core components (AMF, SMF, UPF for both slices)
- Start FlexRIC and gNodeB
- Configure initial 50/50 bandwidth split between slices
- Start both UE1 (Slice 1) and UE2 (Slice 2)
- Launch traffic generation for both UEs
- Start monitoring stack (InfluxDB, Grafana, Kinetica)

### 4. Validate Setup
```bash
./llm-slicing-5g-lab/docker/validate_dual_ue.sh
```

This validation script checks:
- Both UE containers are running
- UEs are registered with 5G Core
- Network connectivity for both UEs
- Traffic generation is active
- Monitoring stack is operational

### 5. Check Status
```bash
./llm-slicing-5g-lab/docker/lab_status.sh
```

### 6. Stop the Lab
```bash
./llm-slicing-5g-lab/docker/lab_stop.sh
```

## Network Slicing Configuration

### UE1 (Slice 1)
- **IMSI**: 001010000000001
- **DNN**: oai
- **NSSAI_SD**: 0x000001
- **TUN Interface**: oaitun_ue1
- **Traffic**: 30M bandwidth (configurable)

### UE2 (Slice 2)
- **IMSI**: 001010000000002
- **DNN**: oai2
- **NSSAI_SD**: 0x000005
- **TUN Interface**: oaitun_ue3
- **Traffic**: 120M bandwidth (configurable)

## Managing Bandwidth Allocation

Change the bandwidth allocation between slices dynamically:

```bash
cd llm-slicing-5g-lab/docker

# Example: Give 80% to Slice 1, 20% to Slice 2
./change_rc_slice_docker.sh 80 20

# Example: Equal split
./change_rc_slice_docker.sh 50 50

# Example: Give 30% to Slice 1, 70% to Slice 2
./change_rc_slice_docker.sh 30 70
```

## Monitoring and Visualization

### Access Points
- **Streamlit UI**: http://localhost:8501
- **Grafana**: http://localhost:9002 (admin/admin)
- **InfluxDB**: http://localhost:9001
- **Kinetica Workbench**: http://localhost:8000 (admin/admin)

### Logs
```bash
# View UE1 logs
docker logs -f oai-ue-slice1

# View UE2 logs
docker logs -f oai-ue-slice2

# View FlexRIC logs
docker logs -f flexric

# View gNodeB logs
docker logs -f oai-gnb

# View traffic generation logs
tail -f llm-slicing-5g-lab/logs/UE1_iperfc.log
tail -f llm-slicing-5g-lab/logs/UE2_iperfc.log
```

## Troubleshooting

### UE Registration Issues
If a UE fails to register:
```bash
# Check UE logs
docker logs oai-ue-slice1  # or oai-ue-slice2

# Check if SMF for the slice is running
docker ps | grep smf

# Restart the UE
docker restart oai-ue-slice1  # or oai-ue-slice2
```

### TUN Interface Issues
If TUN interfaces are not created:
```bash
# Verify the containers are using bridge networking (not host mode)
docker inspect oai-ue-slice1 | grep NetworkMode
docker inspect oai-ue-slice2 | grep NetworkMode

# Check interface inside container
docker exec oai-ue-slice1 ip addr show oaitun_ue1
docker exec oai-ue-slice2 ip addr show oaitun_ue3
```

### Traffic Generation Issues
If traffic is not flowing:
```bash
# Check if iperf3 servers are running
docker exec oai-ext-dn pgrep iperf3

# Check if traffic generator is running
pgrep -f generate_traffic.py

# Restart traffic generator
pkill -f generate_traffic.py
cd llm-slicing-5g-lab
python3 generate_traffic.py &
```

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                      5G Core Network                             │
│  ┌──────┐  ┌────────────┐  ┌────────────┐  ┌─────────────┐    │
│  │ AMF  │  │ SMF-Slice1 │  │ SMF-Slice2 │  │ oai-ext-dn  │    │
│  └──────┘  └────────────┘  └────────────┘  └─────────────┘    │
│               │                │                  │              │
│               │ DNN: oai       │ DNN: oai2        │              │
│               │ SD: 0x000001   │ SD: 0x000005     │              │
└───────────────┼────────────────┼──────────────────┼──────────────┘
                │                │                  │
         ┌──────┴────────────────┴──────┐          │
         │        gNodeB                 │          │
         │  (with FlexRIC control)       │          │
         └───────────┬───────────────────┘          │
                     │                              │
         ┌───────────┴───────────┐                  │
         │                       │                  │
    ┌────▼────┐            ┌────▼────┐             │
    │  UE1    │            │  UE2    │             │
    │ (Slice1)│            │ (Slice2)│             │
    │oaitun_ue1│          │oaitun_ue3│             │
    └────┬────┘            └────┬────┘             │
         │                      │                  │
         │    iperf3 traffic    │                  │
         └──────────────────────┴──────────────────┘
                  Port 5201 (UE1) / Port 5202 (UE2)
```

## Additional Resources

- **Analysis Document**: See `UE_SLICING_ISSUE_ANALYSIS.md` for detailed technical analysis
- **Validation Script**: `llm-slicing-5g-lab/docker/validate_dual_ue.sh`
- **OpenAirInterface**: https://openairinterface.org/
- **FlexRIC**: https://gitlab.eurecom.fr/mosaic5g/flexric






