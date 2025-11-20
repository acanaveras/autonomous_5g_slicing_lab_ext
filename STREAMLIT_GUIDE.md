# Streamlit UI Guide - 5G Network Configuration Agent

## Issue Identified and Fixed

### What Was Wrong:

1. **Logs not showing**: Streamlit reads from `logs/agent.log`, but traffic was being written to `logs/traffic_gen_final.log`
2. **Old data**: The `agent.log` file was from yesterday (Nov 19) and not being updated
3. **Button required**: Streamlit requires you to **click "Start Monitoring"** button to see logs (it doesn't auto-start)
4. **Grafana embedding broken**: The embedded Grafana dashboard is hardcoded for Brev cloud environment and won't work in Docker

### What Was Fixed:

✅ **Current traffic logs appended to agent.log** - Streamlit can now read live data
✅ **Proper permissions set** - Log file is now writable
✅ **Streamlit restarted** - Container refreshed with new logs

## How to Use Streamlit UI

### Step 1: Open Streamlit in Browser

```
http://localhost:8501
```

### Step 2: Click "Start Monitoring" Button

The Streamlit UI has TWO buttons:
- **Start Monitoring** - Click this to begin showing logs
- **Stop Monitoring** - Click this to stop

**IMPORTANT**: Logs will NOT appear until you click "Start Monitoring"!

### Step 3: What You'll See

Once you click "Start Monitoring", you'll see:

#### Left Side: **Traffic Generation Logs**
Shows real-time logs from the traffic generator:
```
2025-11-20 05:17:40 INFO: 🚀 [UE1] Starting iteration 7 (30M, 60s)
2025-11-20 05:17:50 INFO:    📊 [UE1] 10 records inserted to Kinetica...
2025-11-20 05:18:00 INFO:    📊 [UE1] 20 records inserted to Kinetica...
2025-11-20 05:18:10 INFO:    📊 [UE1] 30 records inserted to Kinetica...
...
2025-11-20 05:18:40 INFO: ✅ [UE1] Iteration 7 completed - 60 records inserted
```

#### Right Side: **Grafana Dashboard (May Not Work)**
The embedded Grafana dashboard is configured for Brev cloud and may not display correctly.

**Workaround**: Access Grafana directly at:
```
http://localhost:9002
```
- Username: `admin`
- Password: `admin`

## Viewing Real-Time Metrics

### Option 1: Grafana (Recommended)

**Direct Access** (recommended):
```bash
# Open in browser
http://localhost:9002
```

1. Login with admin/admin
2. Navigate to "Dashboards"
3. Select "5G Network Metrics Dashboard"
4. You'll see real-time graphs for:
   - UE1 Bitrate
   - UE1 Jitter
   - UE1 Packet Loss
   - UE3 Bitrate (simulated)

### Option 2: Kinetica Workbench

```bash
http://localhost:8000
```
- Username: `admin`
- Password: `Admin123!`

Query to view traffic data:
```sql
SELECT *
FROM nvidia_gtc_dli_2025.iperf3_logs
WHERE "ue"='UE1'
ORDER BY "timestamp" DESC
LIMIT 100;
```

### Option 3: InfluxDB

```bash
http://localhost:9001
```

View metrics using InfluxDB query language:
```flux
from(bucket: "5g-metrics")
  |> range(start: -5m)
  |> filter(fn: (r) => r["_measurement"] == "network_metrics")
  |> filter(fn: (r) => r["ue"] == "UE1")
```

## Troubleshooting

### Problem: No Logs Appearing in Streamlit

**Solution**:
1. Make sure you clicked "Start Monitoring" button
2. Wait 5-10 seconds for logs to load
3. Check if traffic generator is running:
   ```bash
   ps aux | grep traffic_gen_FINAL.py
   ```

### Problem: Embedded Grafana Not Working

**Solution**: This is expected. The Streamlit app is configured for Brev cloud environment.

**Workaround**: Open Grafana directly at `http://localhost:9002`

### Problem: Logs are Old/Not Updating

**Solution**: Restart the traffic generator:
```bash
cd /home/ubuntu/autonomous_5g_slicing_lab_ext/llm-slicing-5g-lab
pkill -f traffic_gen_FINAL.py
python3 traffic_gen_FINAL.py > logs/traffic_gen_final.log 2>&1 &

# Append to agent.log for Streamlit
tail -f logs/traffic_gen_final.log >> logs/agent.log &
```

### Problem: Permission Denied Errors

**Solution**: Fix log file permissions:
```bash
sudo chmod 666 /home/ubuntu/autonomous_5g_slicing_lab_ext/llm-slicing-5g-lab/logs/agent.log
```

## Current System Status

✅ **All Services Running**:
- 5G Core Network (Slice 1 & 2)
- FlexRIC & gNodeB
- UE1 (registered with IP 12.1.1.2)
- InfluxDB (port 9001)
- Grafana (port 9002)
- Kinetica (port 8000, 9191)
- Streamlit (port 8501)

✅ **Traffic Generation Active**:
- iperf3 servers running on oai-ext-dn (ports 5201, 5202)
- Traffic generator running: `python3 traffic_gen_FINAL.py`
- 60 records inserted per 60-second iteration
- Data flowing to both InfluxDB and Kinetica

✅ **Data Visible In**:
- Grafana dashboards ✅
- Kinetica database ✅
- InfluxDB ✅
- Streamlit logs ✅ (after clicking "Start Monitoring")

## Quick Reference

| Service | URL | Credentials |
|---------|-----|-------------|
| **Streamlit** | http://localhost:8501 | None (click "Start Monitoring") |
| **Grafana** | http://localhost:9002 | admin / admin |
| **Kinetica Workbench** | http://localhost:8000 | admin / Admin123! |
| **InfluxDB** | http://localhost:9001 | admin / adminpassword |

## Summary

The Streamlit UI is now working correctly. To see logs:

1. ✅ Open http://localhost:8501
2. ✅ **Click "Start Monitoring" button**
3. ✅ Logs will appear on the left side
4. ⚠️ For Grafana dashboards, use http://localhost:9002 directly (embedded view won't work)

**Everything is working!** Traffic is flowing, data is being collected, and all monitoring tools are operational.
