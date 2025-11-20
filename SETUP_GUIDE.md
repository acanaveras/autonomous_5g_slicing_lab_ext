# Autonomous 5G Slicing Lab - Setup Guide

## Quick Start (One Command)

The lab has been updated with a **single-script startup** that handles everything automatically:

```bash
cd /home/ubuntu/autonomous_5g_slicing_lab_ext/llm-slicing-5g-lab/docker
./lab_start.sh
```

This single command will:
1. ✅ Build all Docker images (FlexRIC, gNodeB, UE, Streamlit) - **only if not already built**
2. ✅ Start 5G Core Network (both slices)
3. ✅ Start FlexRIC and gNodeB
4. ✅ Start UE and verify registration
5. ✅ Start monitoring stack (InfluxDB, Grafana, Kinetica, Streamlit)
6. ✅ **Automatically start iperf3 servers** on the external data network
7. ✅ **Automatically start traffic generation** with real-time metrics

## What's New?

### Before (Multiple Steps)
```bash
# You had to run all these commands manually:
./llm-slicing-5g-lab/build_flexRIC.sh
./llm-slicing-5g-lab/build_gnb.sh
./llm-slicing-5g-lab/build_ue.sh
./llm-slicing-5g-lab/build_streamlit.sh
./llm-slicing-5g-lab/lab_start.sh
docker exec -d oai-ext-dn iperf3 -s -p 5201
docker exec -d oai-ext-dn iperf3 -s -p 5202
python3 traffic_gen_FINAL.py > logs/traffic_gen_final.log 2>&1 &
```

### Now (Single Command)
```bash
cd llm-slicing-5g-lab/docker
./lab_start.sh  # That's it!
```

## Why No Traffic Before?

The issue was that **iperf3 servers and traffic generator were not started automatically**. The updated `lab_start.sh` now:

1. **Starts iperf3 servers** on `oai-ext-dn` container (ports 5201 and 5202)
2. **Starts traffic generator** (`traffic_gen_FINAL.py`) automatically
3. **Verifies** that traffic is flowing to InfluxDB/Kinetica

## Monitoring the Lab

Once started, access the following:

- **Streamlit UI**: http://localhost:8501
- **Grafana**: http://localhost:9002 (admin/admin)
- **InfluxDB**: http://localhost:9001
- **Kinetica Workbench**: http://localhost:8000 (admin/Admin123!)

### View Traffic Generator Logs
```bash
tail -f /home/ubuntu/autonomous_5g_slicing_lab_ext/llm-slicing-5g-lab/logs/traffic_gen_final.log
```

### View Network Logs
```bash
docker logs -f flexric
docker logs -f oai-gnb
docker logs -f oai-ue-slice1
```

## Stopping the Lab

```bash
cd /home/ubuntu/autonomous_5g_slicing_lab_ext/llm-slicing-5g-lab/docker
./lab_stop.sh  # Stops everything including traffic generator
```

## Checking Status

```bash
cd /home/ubuntu/autonomous_5g_slicing_lab_ext/llm-slicing-5g-lab/docker
./lab_status.sh
```

## Build Images Separately (Optional)

If you want to rebuild images with `--no-cache` option:

```bash
cd /home/ubuntu/autonomous_5g_slicing_lab_ext/llm-slicing-5g-lab/docker

# Rebuild specific components
./build_flexric.sh --no-cache
./build_gnb.sh --no-cache
./build_ue.sh --no-cache
./build_streamlit.sh --no-cache
```

## Troubleshooting

### Traffic Not Showing in Grafana/Streamlit

**Wait 30-60 seconds** after startup for data to appear. The traffic generator runs in 60-second iterations.

Check if traffic generator is running:
```bash
ps aux | grep traffic_gen_FINAL.py
tail -f /home/ubuntu/autonomous_5g_slicing_lab_ext/llm-slicing-5g-lab/logs/traffic_gen_final.log
```

Check if iperf3 servers are running:
```bash
docker exec oai-ext-dn pgrep iperf3
# Should show 2 processes
```

### UE Not Registered

Check UE logs:
```bash
docker logs oai-ue-slice1 | grep "REGISTRATION"
```

### Container Health Issues

Check container status:
```bash
docker ps --format "table {{.Names}}\t{{.Status}}"
```

View specific container logs:
```bash
docker logs <container-name>
```

## Technical Details

### Image Build Times (First Run)
- FlexRIC: ~10-15 minutes
- gNodeB: ~15-20 minutes
- UE: ~2-3 minutes
- Streamlit: ~2-3 minutes

**Total first run**: ~30-40 minutes

### Subsequent Runs
- Images are already built, so startup takes ~2-3 minutes
- The script checks if images exist and skips building

### Traffic Generator
- Runs continuously in 60-second intervals
- Sends UDP traffic from UE1 to external DN (192.168.70.135)
- Metrics are written to:
  - InfluxDB (for Grafana/Streamlit visualization)
  - Kinetica (for data analytics)
  - Log file (`logs/traffic_gen_final.log`)

### Network Architecture
```
UE1 (12.1.1.4)
  → gNodeB → FlexRIC (RAN slicing)
  → 5G Core (Slice 1: SMF/UPF)
  → External DN (192.168.70.135:5201)
```

## Summary

✅ **One command to start everything**: `./lab_start.sh`
✅ **One command to stop everything**: `./lab_stop.sh`
✅ **Traffic automatically generated** and visible in Grafana/Streamlit
✅ **No manual steps required** for iperf3 or traffic generation
✅ **Smart image building** - only builds if images don't exist

Enjoy your autonomous 5G slicing lab!
