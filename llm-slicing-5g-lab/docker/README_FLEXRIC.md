# FlexRIC Docker Setup

This directory contains the Docker configuration for running FlexRIC (Flexible RAN Intelligent Controller) in a containerized environment.

## 📁 Files

- **Dockerfile.flexric** - Multi-stage Dockerfile for building FlexRIC with custom xApp
- **docker-compose-flexric.yaml** - Docker Compose configuration for FlexRIC service
- **change_rc_slice_docker.sh** - Helper script to change slice bandwidth allocation
- **.dockerignore** - Files to exclude from Docker build context

## 🏗️ Architecture

### Build Stages

1. **flexric-base**: Base image with build dependencies (gcc-12, SWIG, CMake, etc.)
2. **flexric-builder**: Builds FlexRIC from source with custom xApp integration
3. **flexric-runtime**: Minimal runtime image with only necessary binaries and libraries

### Custom xApp Integration

The Dockerfile includes the custom `xapp_rc_slice_dynamic` application that allows dynamic bandwidth allocation between network slices. The xApp is built from:
- `extra_files/xapp_rc_slice_dynamic.c`
- `extra_files/CMakeLists.txt`

## 🚀 Quick Start

### 1. Build the FlexRIC Image

```bash
cd /home/ubuntu/autonomous_5g_slicing_lab_ext/llm-slicing-5g-lab/docker
docker-compose -f docker-compose-flexric.yaml build
```

**Build time:** ~10-15 minutes (depending on system)

### 2. Start FlexRIC Container

**Prerequisites:** 5G Core Network must be running first
```bash
# Start 5G Core Network
cd /home/ubuntu/autonomous_5g_slicing_lab_ext/llm-slicing-5g-lab
docker-compose -f docker-compose-oai-cn-slice1.yaml up -d
docker-compose -f docker-compose-oai-cn-slice2.yaml up -d

# Start FlexRIC
cd docker
docker-compose -f docker-compose-flexric.yaml up -d
```

### 3. Check FlexRIC Status

```bash
# View logs
docker logs -f flexric

# Check if nearRT-RIC is running
docker exec flexric ps aux | grep nearRT-RIC

# Health check
docker inspect flexric | grep -A5 Health
```

### 4. Change Slice Bandwidth Allocation

Use the helper script to dynamically adjust bandwidth ratios:

```bash
# Example: Set Slice 1 to 60%, Slice 2 to 40%
./change_rc_slice_docker.sh 60 40

# Example: Set Slice 1 to 30%, Slice 2 to 70%
./change_rc_slice_docker.sh 30 70
```

This script executes the xApp inside the running FlexRIC container.

## 🔧 Configuration

### Environment Variables

You can customize FlexRIC behavior via environment variables in `docker-compose-flexric.yaml`:

```yaml
environment:
  - TZ=Europe/Paris
  - SLICE1_RATIO=50  # Initial Slice 1 bandwidth ratio
  - SLICE2_RATIO=50  # Initial Slice 2 bandwidth ratio
```

### Network Configuration

FlexRIC connects to the 5G network via the `demo-oai-public-net` bridge network:
- **IP Address:** 192.168.70.150
- **E2 Port:** 36421/sctp (RAN ↔ RIC communication)
- **E42 Port:** 36422/sctp (xApp ↔ RIC communication)

**Alternative:** If you experience SCTP connectivity issues, you can use host networking:

```yaml
services:
  flexric:
    network_mode: host
    # Comment out the networks section
```

### Volume Mounts

- **Logs:** `../logs:/flexric/logs` - FlexRIC logs persisted on host
- **Config:** `./flexric-config:/usr/local/etc/flexric:ro` - Custom configuration (optional)

## 🧪 Testing

### 1. Verify E2 Connection with gNodeB

Once both FlexRIC and gNodeB are running, check logs for E2 SETUP messages:

```bash
docker logs flexric | grep "E2 SETUP"
```

Expected output:
```
[E2AP]: E2 SETUP-REQUEST rx from PLMN 1.1 Node ID 3584 RAN type ngran_gNB
[NEAR-RIC]: Accepting RAN function ID 2 with def = ORAN-E2SM-KPM
[NEAR-RIC]: Accepting RAN function ID 3 with def = ORAN-E2SM-RC
...
```

### 2. Test xApp Execution

```bash
# Manually execute xApp inside container
docker exec -e SLICE1_RATIO=70 -e SLICE2_RATIO=30 flexric \
  /usr/local/bin/xapp_rc_slice_dynamic
```

### 3. Inspect Container

```bash
# Enter container shell
docker exec -it flexric /bin/bash

# Check installed binaries
ls -lh /usr/local/bin/
ls -lh /usr/local/lib/flexric/

# Verify library dependencies
ldd /usr/local/bin/nearRT-RIC
```

## 📊 Monitoring

### View Real-time Logs

```bash
# FlexRIC daemon logs
docker logs -f flexric

# Follow last 100 lines
docker logs --tail=100 -f flexric
```

### Check Resource Usage

```bash
docker stats flexric
```

## 🐛 Troubleshooting

### Issue: Container exits immediately

**Cause:** nearRT-RIC process fails to start

**Solution:**
```bash
# Check logs for errors
docker logs flexric

# Common issues:
# 1. Configuration file missing
# 2. SCTP module not loaded on host
sudo modprobe sctp
```

### Issue: E2 connection fails with gNodeB

**Cause:** Network connectivity or SCTP issues

**Solution:**
```bash
# 1. Verify networks
docker network inspect demo-oai-public-net

# 2. Check if gNodeB can reach FlexRIC
docker exec <gnb-container> ping 192.168.70.150

# 3. Use host networking mode (edit docker-compose-flexric.yaml)
network_mode: host
```

### Issue: xApp execution fails

**Cause:** Missing environment variables or RIC not ready

**Solution:**
```bash
# Verify RIC is running
docker exec flexric pgrep -f nearRT-RIC

# Check if xApp binary exists
docker exec flexric ls -lh /usr/local/bin/xapp_rc_slice_dynamic

# Execute with explicit environment variables
docker exec -e SLICE1_RATIO=50 -e SLICE2_RATIO=50 flexric \
  /usr/local/bin/xapp_rc_slice_dynamic
```

## 🔄 Updating FlexRIC

### Rebuild After Code Changes

```bash
# Rebuild image
docker-compose -f docker-compose-flexric.yaml build --no-cache

# Restart container
docker-compose -f docker-compose-flexric.yaml down
docker-compose -f docker-compose-flexric.yaml up -d
```

### Update xApp Only

If you only changed xApp files (`xapp_rc_slice_dynamic.c`):

```bash
# Update files in extra_files/
# Rebuild
docker-compose -f docker-compose-flexric.yaml build

# Restart
docker-compose -f docker-compose-flexric.yaml restart
```

## 🧹 Cleanup

### Stop FlexRIC

```bash
docker-compose -f docker-compose-flexric.yaml down
```

### Remove Image

```bash
docker rmi flexric-5g-slicing:latest
```

### Clean Build Cache

```bash
docker builder prune -a
```

## 📚 Additional Resources

- [FlexRIC Documentation](https://gitlab.eurecom.fr/mosaic5g/flexric)
- [O-RAN E2 Interface Specification](https://www.o-ran.org/specifications)
- [OpenAirInterface](https://openairinterface.org/)

## 🔐 Security Notes

- Container runs as root (required for SCTP operations)
- `NET_ADMIN` capability is required for network operations
- Consider using secrets management for production deployments
- Logs may contain sensitive network information

## 📝 License

SPDX-License-Identifier: Apache-2.0
Copyright (c) 2023-2024 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
