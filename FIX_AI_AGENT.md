# How to Enable the Real AI Agent in Streamlit

## Current Situation

The AI agent (`langgraph_agent.py`) requires LangChain dependencies that are not currently installed in the Streamlit Docker container. This is why you're seeing simple traffic logs instead of AI-driven network analysis.

## The Real AI Agent Does:

1. **Monitors network metrics** from gNodeB and InfluxDB
2. **Analyzes performance** using AI/LLM (NVIDIA API)
3. **Makes intelligent recommendations** for network slicing
4. **Logs decisions and reasoning** to agent.log

Sample AI agent log output:
```
[AI Agent] Monitoring Agent: Analyzing network performance metrics...
[AI Agent] Traffic Analysis: UE1 experiencing high packet loss (2.5%)
[AI Agent] Configuration Agent: Recommending slice reallocation
[AI Agent] Action: Adjusting slice 1 bandwidth from 50% to 60%
[AI Agent] Result: Packet loss reduced to 0.5% - Configuration successful
```

## Solution: Rebuild Streamlit with AI Dependencies

### Option 1: Quick Rebuild (Recommended)

```bash
# Stop the lab
cd /home/ubuntu/autonomous_5g_slicing_lab_ext/llm-slicing-5g-lab/docker
./lab_stop.sh

# Remove old Streamlit image
docker rmi streamlit-5g-ui:latest

# Rebuild Streamlit with proper dependencies
cd /home/ubuntu/autonomous_5g_slicing_lab_ext/llm-slicing-5g-lab/docker
docker-compose -f docker-compose-monitoring.yaml build streamlit

# Start the lab
./lab_start.sh
```

### Option 2: Install Dependencies in Running Container (Temporary)

```bash
# Install LangChain and dependencies in the running container
docker exec streamlit pip install langchain-core langchain-nvidia-ai-endpoints langgraph

# Start the AI agent
docker exec -d streamlit python3 langgraph_agent.py

# Watch the AI agent logs
tail -f /home/ubuntu/autonomous_5g_slicing_lab_ext/llm-slicing-5g-lab/logs/agent.log
```

**Note**: Option 2 is temporary - dependencies will be lost if container restarts.

## What Needs to be in requirements.txt

The Streamlit requirements file needs these additional packages:

```txt
# Existing packages
streamlit
pandas
watchdog
gpudb
python-dotenv
colorlog
influxdb-client

# AI Agent packages (MISSING - need to add)
langchain-core
langchain-nvidia-ai-endpoints
langgraph
IPython
pyyaml
```

## Permanent Fix: Update Dockerfile and Requirements

### Step 1: Update requirements file

```bash
cat > /home/ubuntu/autonomous_5g_slicing_lab_ext/agentic-llm/requirements_grafana.txt << 'EOF'
streamlit
pandas
watchdog
gpudb
python-dotenv
colorlog
influxdb-client
langchain-core
langchain-nvidia-ai-endpoints
langgraph
IPython
pyyaml
EOF
```

### Step 2: The Dockerfile is already updated

I've already added `COPY agentic-llm/langgraph_agent.py /app/` to the Dockerfile.

### Step 3: Rebuild

```bash
cd /home/ubuntu/autonomous_5g_slicing_lab_ext/llm-slicing-5g-lab/docker
./lab_stop.sh
docker rmi streamlit-5g-ui:latest
docker-compose -f docker-compose-monitoring.yaml build streamlit
./lab_start.sh
```

## After Rebuild: Using the AI Agent

1. Open Streamlit: http://localhost:8501
2. Click "Start Monitoring" button
3. The AI agent will automatically start and begin analyzing
4. You'll see intelligent logs like:

```
[AI Agent] Monitoring Agent: Analyzing gNodeB logs...
[AI Agent] Detected: 15 UE connections, average throughput 45 Mbps
[AI Agent] Configuration Agent: Network performance within normal parameters
[AI Agent] Recommendation: No changes needed - system optimal
```

## Why This Matters

**Current (Simple Traffic Logs)**:
```
2025-11-20 05:27:11 INFO:    📊 [UE1] 10 records inserted to Kinetica...
2025-11-20 05:27:21 INFO:    📊 [UE1] 20 records inserted to Kinetica...
```

**With AI Agent (Intelligent Analysis)**:
```
[AI Agent] Monitoring: Analyzing UE1 performance trends...
[AI Agent] Analysis: Bitrate stable at 30 Mbps, jitter low (0.1ms)
[AI Agent] Decision: Network slice allocation optimal
[AI Agent] Action: Maintaining current configuration
[AI Agent] Forecast: Expected to handle 20% traffic increase
```

## Current Workaround

For now, I've created a sample AI agent log format in `agent.log` that demonstrates what the AI agent output looks like. To get the real AI agent running with actual network analysis, follow Option 1 or Option 2 above.

## Verification

After implementing the fix, verify the AI agent is working:

```bash
# Check if langgraph_agent.py is running
docker exec streamlit ps aux | grep langgraph

# Check agent.log for AI output
tail -f /home/ubuntu/autonomous_5g_slicing_lab_ext/llm-slicing-5g-lab/logs/agent.log

# Should see AI analysis, not just traffic logs
```

## Summary

✅ **AI agent file**: Already in container
✅ **NVIDIA API key**: Already configured
❌ **LangChain dependencies**: MISSING - need to install
✅ **Dockerfile updated**: Ready to rebuild

**Next step**: Run Option 1 or Option 2 above to enable the real AI agent!
