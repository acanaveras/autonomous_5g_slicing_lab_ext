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

### 4. Expose Required Ports on GPU
If you're running the lab on a remote GPU server, ensure the following ports are exposed to allow access to the services:

```
9002 8501 9001 8080 8000 6006 5001 4999
```

**Port Details:**
- `9002` - Grafana (Monitoring Dashboard)
- `8501` - Streamlit (Agent UI)
- `9001` - InfluxDB (Time-series Database)
- `8080` - Kinetica Admin Console
- `8000` - Kinetica Workbench
- `6006` - Phoenix Telemetry (AI Observability)
- `5001` - NAT UI (NeMo Agent Toolkit Web Interface)
- `4999` - NAT REST API (NeMo Agent Toolkit Server)

### 5. Set Up and Run NeMo Agent Toolkit UI
The NAT UI provides a web interface for interacting with the NeMo Agent Toolkit. It requires Node.js 20.

**Install Node.js 20 using nvm:**
```bash
# Install curl if not already installed
sudo apt install curl -y

# Install nvm (Node Version Manager)
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash

# Load nvm
source ~/.bashrc

# Install and use Node.js 20
nvm install 20
nvm use 20

# Verify installation
node -v
npm -v
```

**Run the NAT UI:**
```bash
cd NeMo-Agent-Toolkit-UI
npm install
cp .env.example .env

# Start the development server on port 5001
PORT=5001 npm run dev:all
```

The NAT UI will be available at http://localhost:5001

### 6. Access the Services
Once the lab is running, you can access the following services:

| Port | Service              | Description                    |
|------|----------------------|--------------------------------|
| 9002 | Grafana             | Monitoring and visualization   |
| 8501 | Streamlit           | Agent UI and dashboard         |
| 9001 | InfluxDB            | Time-series database           |
| 8080 | Kinetica Admin      | Kinetica admin console         |
| 8000 | Kinetica Workbench  | Kinetica workbench interface   |
| 6006 | Phoenix Telemetry   | AI observability and tracing   |
| 5001 | NAT UI              | NeMo Agentic Toolkit web UI    |
| 4999 | NAT REST API        | NeMo Agent Toolkit server      |

**Login Credentials:**

| Service              | URL                          | Username | Password      | Notes                          |
|----------------------|------------------------------|----------|---------------|--------------------------------|
| Grafana             | http://localhost:9002        | admin    | admin         | -                              |
| InfluxDB            | http://localhost:9001        | admin    | adminpassword | -                              |
| Kinetica Admin      | http://localhost:8080        | admin    | admin         | -                              |
| Kinetica Workbench  | http://localhost:8000        | admin    | admin         | -                              |
| Phoenix Telemetry   | http://localhost:6006        | -        | -             | AI observability, distributed tracing, and performance monitoring |
| NAT UI              | http://localhost:5001        | -        | -             | NeMo Agentic Toolkit web interface |
| NAT REST API        | http://localhost:4999/docs   | -        | -             | OpenAPI/Swagger UI for network management tools |
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


### 7. Check Status
```bash
./llm-slicing-5g-lab/docker/lab_status.sh
```

### 8. Stop the Lab
```bash
./llm-slicing-5g-lab/docker/lab_stop.sh
```






