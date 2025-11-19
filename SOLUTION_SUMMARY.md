# 5G Lab Traffic Generation - Complete Solution

## ✅ All Issues FIXED and System Running!

### Problems Identified & Resolved:

1. **Missing Python Dependency** ✅
   - Issue: Streamlit missing `typeguard` module
   - Fix: Added to `agentic-llm/requirements_grafana.txt:7`
   - File: `/home/ubuntu/autonomous_5g_slicing_lab_ext/agentic-llm/requirements_grafana.txt`

2. **Lab Startup Script Bug** ✅
   - Issue: Log file path broke when script changed directories
   - Fix: Changed to absolute path `LOG_DIR="$SCRIPT_DIR/../logs"`
   - File: `/home/ubuntu/autonomous_5g_slicing_lab_ext/llm-slicing-5g-lab/docker/lab_start.sh:14`

3. **Kinetica REST API Not Starting** ✅
   - Issue: Database rank0 process wasn't starting automatically
   - Fix: Used proper Kinetica bootstrap script with `GPUDB_START_ALL=1`
   - Now running on port **9191** ✅

4. **SQL Reserved Keyword Issue** ✅
   - Issue: Column name "stream" is SQL reserved keyword
   - Fix: Quote all column names in INSERT statements
   - Impact: Data wasn't being inserted to Kinetica

5. **InfluxDB Connection** ✅
   - Issue: Script using wrong hostname `influxdb:8086`
   - Fix: Changed to `localhost:9001`
   - Now writing metrics for Grafana ✅

---

## 🚀 How to Run the Complete System

### 1. Start the 5G Network
```bash
cd /home/ubuntu/autonomous_5g_slicing_lab_ext/llm-slicing-5g-lab/docker
./lab_start.sh
```

### 2. Start Kinetica Database (if not running)
```bash
cd /home/ubuntu/autonomous_5g_slicing_lab_ext/llm-slicing-5g-lab
./run_kinetica_headless.sh
```

### 3. Start Continuous Traffic Generation
```bash
cd /home/ubuntu/autonomous_5g_slicing_lab_ext/llm-slicing-5g-lab
nohup python3 traffic_gen_v2.py > logs/traffic_gen.log 2>&1 &

# Monitor traffic generation
tail -f logs/traffic_gen.log
tail -f logs/UE1_iperfc.log
```

### 4. Start Streamlit (if needed)
```bash
cd /home/ubuntu/autonomous_5g_slicing_lab_ext/llm-slicing-5g-lab/docker
docker-compose -f docker-compose-monitoring.yaml up -d streamlit
```

---

## 📊 Access Points

| Service | URL | Credentials |
|---------|-----|-------------|
| **Streamlit UI** | http://localhost:8501 | N/A |
| **Grafana** | http://localhost:9002 | admin / admin |
| **InfluxDB** | http://localhost:9001 | N/A |
| **Kinetica Workbench** | http://localhost:8000/workbench | admin / Admin123! |
| **Kinetica Admin** | http://localhost:8080/gadmin | admin / Admin123! |

---

## 📈 Current System Status

**All Components Running:**
- ✅ 5G Core Network (AMF, SMF, UPF, NRF, etc.)
- ✅ FlexRIC (E2 connection active)
- ✅ gNodeB (Connected to core)
- ✅ UE (Slice 1) - IP: 12.1.1.2
- ✅ External DN - iperf3 servers on ports 5201 & 5202
- ✅ Kinetica Database - REST API on port 9191
- ✅ InfluxDB - Port 9001
- ✅ Grafana - Port 9002  
- ✅ Streamlit - Port 8501
- ✅ **Traffic Generator - RUNNING CONTINUOUSLY**

**Data Flow:**
```
UE → iperf3 test → Python Script → Kinetica (iperf3_logs table)
                                 ↓
                          InfluxDB → Grafana Dashboard
                                 ↓
                           Streamlit UI (real-time logs)
```

---

## 🔍 Verify Everything is Working

### Check Traffic Generation
```bash
# View live logs
tail -f /home/ubuntu/autonomous_5g_slicing_lab_ext/llm-slicing-5g-lab/logs/traffic_gen.log
tail -f /home/ubuntu/autonomous_5g_slicing_lab_ext/llm-slicing-5g-lab/logs/UE1_iperfc.log

# Check if process is running
ps aux | grep traffic_gen_v2
```

### Check Kinetica Data
```python
from gpudb import GPUdb

kdbc_options = GPUdb.Options()
kdbc_options.username = "admin"
kdbc_options.password = "Admin123!"
kdbc_options.disable_auto_discovery = True
kdbc = GPUdb(host="localhost:9191", options=kdbc_options)

# Count recent records
sql = "SELECT COUNT(*) FROM nvidia_gtc_dli_2025.iperf3_logs WHERE timestamp >= current_datetime() - INTERVAL 5 MINUTES"
result = kdbc.to_df(sql)
print(result)
```

### Check Docker Containers
```bash
docker ps --format "table {{.Names}}\t{{.Status}}" | grep -E "oai-|kinetica|streamlit|grafana"
```

---

## 📁 Key Files Created/Modified

1. `/home/ubuntu/autonomous_5g_slicing_lab_ext/llm-slicing-5g-lab/traffic_gen_v2.py` - **Continuous traffic generator (WORKING)**
2. `/home/ubuntu/autonomous_5g_slicing_lab_ext/agentic-llm/requirements_grafana.txt` - Added typeguard
3. `/home/ubuntu/autonomous_5g_slicing_lab_ext/llm-slicing-5g-lab/docker/lab_start.sh` - Fixed log path

---

## 🛠️ Troubleshooting

### If traffic stops flowing:
```bash
# Restart traffic generator
pkill -f traffic_gen_v2.py
cd /home/ubuntu/autonomous_5g_slicing_lab_ext/llm-slicing-5g-lab
nohup python3 traffic_gen_v2.py > logs/traffic_gen.log 2>&1 &
```

### If iperf3 servers aren't responding:
```bash
# Restart servers
docker exec oai-ext-dn pkill iperf3
docker exec -d oai-ext-dn iperf3 -s -p 5201
docker exec -d oai-ext-dn iperf3 -s -p 5202
```

### If Kinetica is down:
```bash
cd /home/ubuntu/autonomous_5g_slicing_lab_ext/llm-slicing-5g-lab
./run_kinetica_headless.sh
```

---

## 📊 Expected Results

- **Traffic logs updating every second** in UE1_iperfc.log
- **~60 new records per minute** in Kinetica
- **Real-time charts** in Streamlit showing bitrate & packet loss
- **Grafana dashboard** displaying iperf3 metrics
- **Continuous traffic generation** running in background

**System is NOW FULLY OPERATIONAL! 🎉**
