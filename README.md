# 5G Network Simulator Lab with Agentic Workflow

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

### 4. Access the Services
Once the lab is running, you can access the following services:

| Port | Service              | Description                    |
|------|----------------------|--------------------------------|
| 9002 | Grafana             | Monitoring and visualization   |
| 8501 | Streamlit           | Agent UI and dashboard         |
| 9001 | InfluxDB            | Time-series database           |
| 8080 | Kinetica Admin      | Kinetica admin console         |
| 8000 | Kinetica Workbench  | Kinetica workbench interface   |


### 5. Check Status
```bash
./llm-slicing-5g-lab/docker/lab_status.sh
```

### 6. Stop the Lab
```bash
./llm-slicing-5g-lab/docker/lab_stop.sh
```






