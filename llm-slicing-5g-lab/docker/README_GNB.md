# gNodeB Docker Setup

This directory contains the Docker configuration for running OpenAirInterface gNodeB with E2 support for FlexRIC integration.

## 📁 Files

- **Dockerfile.gnb** - Multi-stage Dockerfile for building OAI gNodeB with E2 support
- **docker-compose-gnb.yaml** - Docker Compose configuration for gNodeB + FlexRIC
- **gnb-docker.conf** - gNodeB configuration file
- **build_gnb.sh** - Helper script to build the gNodeB image

## 🏗️ Architecture

### Build Stages

1. **gnb-base**: Base image with build dependencies (gcc-12, CMake, libuhd, etc.)
2. **gnb-builder**: Builds OpenAirInterface from slicing-spring-of-code branch
3. **oai-gnb**: Minimal runtime image with binaries and required libraries

### Key Features

- **E2 Support**: Connects to FlexRIC for RAN control
- **RF Simulator**: No hardware required (rfsimulator mode)
- **Multi-Slice Support**: Two network slices (SST=1, SD=0x000001 and SST=1, SD=0x000005)
- **5G SA Mode**: Standalone 5G (not NSA)

## 🚀 Quick Start

### 1. Build the gNodeB Image

```bash
cd /home/ubuntu/autonomous_5g_slicing_lab_ext/llm-slicing-5g-lab/docker
./build_gnb.sh
```

**Build time:** ~15-20 minutes

### 2. Prerequisites

Before starting gNodeB, ensure these services are running:

#### a. 5G Core Network
```bash
cd /home/ubuntu/autonomous_5g_slicing_lab_ext/llm-slicing-5g-lab
docker-compose -f docker-compose-oai-cn-slice1.yaml up -d
docker-compose -f docker-compose-oai-cn-slice2.yaml up -d

# Wait for core network to be ready (~30 seconds)
sleep 30
```

#### b. FlexRIC
```bash
cd docker
docker-compose -f docker-compose-gnb.yaml up -d flexric

# Wait for FlexRIC to initialize (~10 seconds)
sleep 10
```

### 3. Start gNodeB

```bash
docker-compose -f docker-compose-gnb.yaml up -d oai-gnb
```

### 4. Verify Operation

```bash
# Check gNodeB logs
docker logs -f oai-gnb

# Check E2 connection in FlexRIC logs
docker logs flexric | grep "E2 SETUP"

# Check gNodeB-AMF connection
docker logs oai-gnb | grep "Received NGSetupResponse"
```

**Expected Output:**
- **FlexRIC:** `[E2AP]: E2 SETUP-REQUEST rx from PLMN 1.1 Node ID 3584 RAN type ngran_gNB`
- **gNodeB:** `Received NGSetupResponse` (confirms AMF connection)

---

## 🔧 Configuration

### Network Configuration

| Component | IP Address | Network | Port |
|---|---|---|---|
| gNodeB | 192.168.70.151 | demo-oai-public-net | - |
| FlexRIC | 192.168.70.150 | demo-oai-public-net | 36421/sctp (E2) |
| AMF | 192.168.70.132 | demo-oai-public-net | 38412/sctp (NGAP) |

### gNodeB Parameters

Edit `gnb-docker.conf` to customize:

```conf
# E2 Agent configuration
e2_agent = {
  near_ric_ip_addr = "192.168.70.150";  # FlexRIC IP
  sm_dir = "/usr/local/lib/flexric/"
}

# Network slices
plmn_list = ({
  mcc = 001;
  mnc = 01;
  mnc_length = 2;
  snssaiList = (
    {sst = 1; sd = 0x000001; },  # Slice 1
    {sst = 1; sd = 0x000005; }   # Slice 2
  )
});

# AMF connection
amf_ip_address = ({
  ipv4 = "192.168.70.132";
  active = "yes";
  preference = "ipv4";
});
```

### Environment Variables

In `docker-compose-gnb.yaml`:

```yaml
environment:
  - USE_SA_TDD_MONO=yes
  - MCC=001
  - MNC=01
  - TAC=1
  - AMF_IP_ADDRESS=192.168.70.132
  - E2_AGENT_ENABLED=yes
  - E2_NEAR_RIC_IP=192.168.70.150
```

---

## 🧪 Testing

### 1. Check Container Status

```bash
docker ps | grep oai-gnb
```

**Expected:**
```
STATUS: Up X seconds (healthy)
```

### 2. Verify E2 Connection

```bash
# Check gNodeB side
docker logs oai-gnb 2>&1 | grep -i "e2"

# Check FlexRIC side
docker logs flexric 2>&1 | grep -i "e2 setup"
```

**Success Indicators:**
- gNodeB: `E2 Agent enabled`
- gNodeB: `E2 Setup Request sent`
- FlexRIC: `E2 SETUP-REQUEST rx from PLMN 1.1 Node ID 3584`
- FlexRIC: `Accepting RAN function ID...`

### 3. Verify AMF Connection

```bash
docker logs oai-gnb 2>&1 | grep -i "ngsetup"
```

**Expected:**
```
Received NGSetupResponse
```

### 4. Test Slice Reconfiguration

```bash
cd /home/ubuntu/autonomous_5g_slicing_lab_ext/llm-slicing-5g-lab/docker

# Change slice allocation (60% Slice1, 40% Slice2)
./change_rc_slice_docker.sh 60 40
```

**Verification:**
```bash
docker logs flexric 2>&1 | tail -20
```

Should show xApp execution and slice control messages.

---

## 📊 Monitoring

### Real-time Logs

```bash
# gNodeB logs (console output)
docker logs -f oai-gnb

# gNodeB logs (file output)
tail -f ../logs/gNodeB_docker.log

# FlexRIC logs
docker logs -f flexric
```

### Log Files

- **gNodeB:** `/opt/oai-gnb/logs/gNodeB_docker.log` (inside container)
- **Host Mount:** `../logs/gNodeB_docker.log`

### Performance Metrics

```bash
# Container resource usage
docker stats oai-gnb

# gNodeB process
docker exec oai-gnb ps aux | grep nr-softmodem
```

---

## 🐛 Troubleshooting

### Issue: gNodeB Fails to Start

**Symptoms:**
```
Container exits immediately or restarts continuously
```

**Solution:**
```bash
# Check detailed logs
docker logs oai-gnb 2>&1 | tail -50

# Common issues:
# 1. AMF not reachable
docker exec oai-gnb ping 192.168.70.132

# 2. FlexRIC not running
docker ps | grep flexric

# 3. Configuration syntax error
docker exec oai-gnb cat /opt/oai-gnb/etc/gnb.conf
```

### Issue: E2 Connection Fails

**Symptoms:**
```
gNodeB: E2 Setup Request timeout
FlexRIC: No E2 SETUP messages
```

**Solution:**
```bash
# 1. Verify FlexRIC is reachable
docker exec oai-gnb ping 192.168.70.150

# 2. Check FlexRIC is listening
docker exec flexric netstat -ln | grep 36421

# 3. Verify E2 configuration
docker exec oai-gnb grep "e2_agent" /opt/oai-gnb/etc/gnb.conf

# 4. Check SCTP module
docker exec oai-gnb cat /proc/modules | grep sctp
```

### Issue: AMF Connection Fails

**Symptoms:**
```
gNodeB: NG Setup Request timeout
No NGSetupResponse received
```

**Solution:**
```bash
# 1. Verify AMF is running
docker ps | grep oai-amf

# 2. Check AMF logs
docker logs oai-amf 2>&1 | grep "NG-SETUP"

# 3. Verify network connectivity
docker exec oai-gnb ping 192.168.70.132

# 4. Check AMF IP configuration
docker exec oai-gnb grep "amf_ip_address" /opt/oai-gnb/etc/gnb.conf
```

### Issue: gNodeB Crashes

**Symptoms:**
```
Container running but nr-softmodem process dies
```

**Solution:**
```bash
# Check for segmentation faults
docker logs oai-gnb 2>&1 | grep -i "segmentation\|core dumped"

# Check system resources
docker stats oai-gnb

# Restart with debug logging
docker-compose -f docker-compose-gnb.yaml down
# Edit docker-compose-gnb.yaml: change log level to debug
docker-compose -f docker-compose-gnb.yaml up -d oai-gnb
```

---

## 🔄 Common Operations

### Restart gNodeB

```bash
docker-compose -f docker-compose-gnb.yaml restart oai-gnb
```

### Stop gNodeB

```bash
docker-compose -f docker-compose-gnb.yaml stop oai-gnb
```

### Remove gNodeB Container

```bash
docker-compose -f docker-compose-gnb.yaml down oai-gnb
```

### Rebuild Image

```bash
./build_gnb.sh --no-cache
```

### Update Configuration

```bash
# 1. Edit configuration
nano gnb-docker.conf

# 2. Restart container (will reload config)
docker-compose -f docker-compose-gnb.yaml restart oai-gnb
```

### View Configuration

```bash
docker exec oai-gnb cat /opt/oai-gnb/etc/gnb.conf
```

---

## 🔐 Security Notes

- Container runs in **privileged mode** (required for RF simulation and network operations)
- `NET_ADMIN` and `SYS_NICE` capabilities added for network configuration and real-time scheduling
- Logs may contain sensitive network information
- Default configuration is for lab/testing environments only

---

## 📚 Additional Resources

- [OpenAirInterface Documentation](https://gitlab.eurecom.fr/oai/openairinterface5g/-/wikis/home)
- [FlexRIC Documentation](https://gitlab.eurecom.fr/mosaic5g/flexric)
- [O-RAN E2 Interface Specification](https://www.o-ran.org/specifications)
- [3GPP 5G Standards](https://www.3gpp.org/)

---

## 📝 License

SPDX-License-Identifier: Apache-2.0
Copyright (c) 2023-2024 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
