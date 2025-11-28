# NAT Wrapper for 5G Network Slicing

Wraps the existing LangGraph 5G network slicing workflow with NeMo Agent Toolkit (NAT).

## Prerequisites

1. **Python 3.11+** installed
2. **NeMo Agent Toolkit** installed
3. **5G Lab running** (via `lab_start.sh`)
4. **Environment variables** configured in root `.env`

## Installation

### Step 1: Install NeMo Agent Toolkit

```bash
pip install nvidia-nat[langchain]~=1.4
```

### Step 2: Install This Wrapper

```bash
cd agentic-llm/nat_wrapper
pip install -e .
```

## Usage

### Option 1: Run via CLI

```bash
cd agentic-llm/nat_wrapper

nat run \
  --config_file src/nat_5g_slicing/configs/config.yml \
  --input "Monitor the network and reconfigure if there are packet loss issues"
```

### Option 2: Deploy as REST API

```bash
cd agentic-llm/nat_wrapper

# Start the NAT server
nat serve \
  --config_file src/nat_5g_slicing/configs/config.yml \
  --host 0.0.0.0 \
  --port 4999
```

Then test with:

```bash
curl -X POST http://localhost:4999/generate \
  -H "Content-Type: application/json" \
  -d '{"input_message": "Check packet loss and reconfigure if needed"}'
```

### Option 3: Docker Deployment

```bash
# Build image
docker build -t nat_5g_slicing -f Dockerfile .

# Run container
docker run -p 4999:4999 -p 6006:6006 \
  --env-file ../../.env \
  --network host \
  nat_5g_slicing
```

## Troubleshooting

**Error: "Module 'nat_5g_slicing' not found"**
- Run: `pip install -e .` from the `nat_wrapper` directory

**Error: "nvidia-nat not found"**
- Run: `pip install nvidia-nat[langchain]~=1.4`

**Error: "Kinetica connection failed"**
- Ensure Kinetica is running and `KINETICA_HOST` is correct in `.env`

**Error: "change_rc_slice_docker.sh not found"**
- Update `RECONFIG_SCRIPT_PATH` in `.env` to the correct path
