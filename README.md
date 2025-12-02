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

**Login Credentials:**

| Service              | URL                          | Username | Password      | Notes                          |
|----------------------|------------------------------|----------|---------------|--------------------------------|
| Grafana             | http://localhost:9002        | admin    | admin         | -                              |
| InfluxDB            | http://localhost:9001        | admin    | adminpassword | -                              |
| Kinetica Admin      | http://localhost:8080        | admin    | admin         | -                              |
| Kinetica Workbench  | http://localhost:8000        | admin    | admin         | -                              |
| Streamlit           | http://localhost:8501        | -        | -             | Click "Start Monitoring" button. **Note:** Agent stops after 30 reconfigurations and requires manual restart (configurable in `agentic-llm/config.yaml`)|

**Important Notes:**
- **Automatic Reconfiguration Limit**: The autonomous agent will perform up to **30 network reconfigurations** by default, then pause and wait for user confirmation. This is a safety feature to prevent infinite loops.
- **To Continue Monitoring**: After 30 reconfigurations, you need to restart the agent:
  ```bash
  cd llm-slicing-5g-lab/docker
  pkill -f "langgraph_agent.py"
  cd ../../agentic-llm
  nohup python3 langgraph_agent.py > logs/langgraph_agent.log 2>&1 &
  ```
- **To Change the Limit**: Edit `agentic-llm/config.yaml` and modify the `interrupt_after` value (e.g., set to `1000` for longer operation or `999999` for near-unlimited).


### 5. Check Status
```bash
./llm-slicing-5g-lab/docker/lab_status.sh
```

### 6. Stop the Lab
```bash
./llm-slicing-5g-lab/docker/lab_stop.sh
```






