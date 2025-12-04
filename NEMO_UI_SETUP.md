# NeMo Agent Toolkit UI Integration Guide

This guide explains how to set up and use the NeMo Agent Toolkit UI with the 5G Network Slicing Agent.

## Overview

The NeMo Agent Toolkit UI provides a modern, React-based chat interface for interacting with the NAT backend. It runs on **port 5001** alongside the existing Streamlit UI.

## Architecture

```
┌─────────────────────────────────────────────────────┐
│                    User Browser                      │
└─────────────┬──────────────────────┬────────────────┘
              │                      │
    Port 5001 │                      │ Port 8501
      (NeMo UI)                      │ (Streamlit)
              │                      │
              ▼                      ▼
    ┌─────────────────┐   ┌──────────────────────┐
    │  NeMo UI        │   │  Streamlit UI        │
    │  (Next.js)      │   │  + Grafana Dashboard │
    │  - Chat UI      │   │  - Logs              │
    │  - Streaming    │   │  - Metrics Charts    │
    └────────┬────────┘   └──────────┬───────────┘
             │                       │
             │ Port 4999             │ Port 4999
             ▼                       ▼
    ┌──────────────────────────────────────────┐
    │         NAT Server (Port 4999)           │
    │  - /generate endpoint                    │
    │  - /v1/chat/completions                 │
    └─────────────────┬────────────────────────┘
                      │
                      ▼
    ┌──────────────────────────────────────────┐
    │    Monitoring + Configuration Agents     │
    │  - LangGraph workflow                    │
    │  - Packet loss detection                 │
    │  - Network reconfiguration               │
    └──────────────────────────────────────────┘
```

## Quick Start

### Prerequisites

- Node.js >= 18.0.0
- npm or yarn
- NAT server running on port 4999
- Git

### One-Command Setup

```bash
# Run this on your GPU Ubuntu machine
cd /home/ubuntu/autonomous_5g_slicing_lab_ext
./scripts/setup-nemo-ui.sh
```

This script will:
1. Add NeMo UI as a git submodule
2. Install Node.js dependencies
3. Create `.env` configuration
4. Verify NAT server connectivity

### Start NeMo UI

```bash
# Development mode
./scripts/start-nemo-ui.sh

# Production mode
./scripts/start-nemo-ui-production.sh
```

Access the UI at: **http://localhost:5001**

## Service Management

### Start All Services

```bash
./scripts/start-all-services.sh
```

This starts:
- Phoenix (port 6006)
- NAT Server (port 4999)
- NeMo UI (port 5001)

### Stop All Services

```bash
./scripts/stop-all-services.sh
```

### Check Service Status

```bash
./scripts/check-services.sh
```

## Configuration

The NeMo UI is configured via `nemo-ui/.env`:

```env
# Backend URL
NAT_BACKEND_URL=http://localhost:4999

# Enable WebSocket for streaming
NEXT_PUBLIC_NAT_WEB_SOCKET_DEFAULT_ON=true

# Show agent thinking steps
NEXT_PUBLIC_NAT_ENABLE_INTERMEDIATE_STEPS=true

# Default model
NEXT_PUBLIC_NAT_DEFAULT_MODEL=meta/llama-3.1-70b-instruct

# Custom port
PORT=5001
```

## Manual Setup (Alternative)

If you prefer manual setup:

```bash
# 1. Add submodule
cd /home/ubuntu/autonomous_5g_slicing_lab_ext
git submodule add https://github.com/NVIDIA/NeMo-Agent-Toolkit-UI.git nemo-ui

# 2. Install dependencies
cd nemo-ui
npm ci

# 3. Create .env
cat > .env << 'EOF'
NAT_BACKEND_URL=http://localhost:4999
NEXT_PUBLIC_NAT_WEB_SOCKET_DEFAULT_ON=true
NEXT_PUBLIC_NAT_ENABLE_INTERMEDIATE_STEPS=true
PORT=5001
EOF

# 4. Start
PORT=5001 npm run dev
```

## Troubleshooting

### Port Already in Use

```bash
# Check what's using port 5001
lsof -i :5001

# Kill the process
kill $(lsof -ti:5001)
```

### NAT Server Not Responding

```bash
# Check if NAT server is running
curl -X POST http://localhost:4999/generate \
  -H "Content-Type: application/json" \
  -d '{"input_message": "test"}'

# If not running, start it
cd agentic-llm/nat_wrapper
nat serve --config_file src/nat_5g_slicing/configs/config.yml --host 0.0.0.0 --port 4999
```

### Dependencies Not Installing

```bash
# Clear npm cache
npm cache clean --force

# Remove node_modules
rm -rf nemo-ui/node_modules

# Reinstall
cd nemo-ui
npm ci
```

### Submodule Issues

```bash
# Update submodule
git submodule update --remote --merge

# Re-initialize submodule
git submodule deinit -f nemo-ui
git submodule update --init --recursive
```

## Port Forwarding (For Remote Access)

If your GPU machine is remote, set up SSH port forwarding:

```bash
# On your local machine
ssh -L 5001:localhost:5001 -L 4999:localhost:4999 ubuntu@your-gpu-ip
```

Then access:
- NeMo UI: http://localhost:5001
- NAT Server: http://localhost:4999

## Updating NeMo UI

```bash
# Pull latest changes
cd /home/ubuntu/autonomous_5g_slicing_lab_ext/nemo-ui
git pull origin main

# Update dependencies
npm ci

# Rebuild (if using production)
npm run build
```

## Development vs Production

### Development Mode
- Hot reloading
- Faster startup
- More verbose logging
- Use: `./scripts/start-nemo-ui.sh`

### Production Mode
- Optimized build
- Better performance
- Smaller bundle size
- Use: `./scripts/start-nemo-ui-production.sh`

## Service URLs Reference

| Service | Port | URL |
|---------|------|-----|
| NeMo UI | 5001 | http://localhost:5001 |
| NAT Server | 4999 | http://localhost:4999 |
| Phoenix | 6006 | http://localhost:6006 |
| Streamlit | 8501 | http://localhost:8501 |

## Logs

Service logs are stored in `/tmp/`:

```bash
# NAT Server logs
tail -f /tmp/nat-server.log

# NeMo UI logs
tail -f /tmp/nemo-ui.log

# Watch both
tail -f /tmp/nat-server.log /tmp/nemo-ui.log
```

## Git Integration

The NeMo UI is added as a git submodule. To commit the integration:

```bash
cd /home/ubuntu/autonomous_5g_slicing_lab_ext
git add .gitmodules nemo-ui scripts/ nemo-ui.env.template NEMO_UI_SETUP.md
git commit -m "Add NeMo Agent Toolkit UI integration (port 5001)"
git push
```

## Uninstalling

To remove the NeMo UI:

```bash
# Stop services
./scripts/stop-all-services.sh

# Remove submodule
git submodule deinit -f nemo-ui
git rm -f nemo-ui
rm -rf .git/modules/nemo-ui

# Commit
git commit -m "Remove NeMo UI submodule"
```

## Support

For issues with:
- **NeMo UI**: https://github.com/NVIDIA/NeMo-Agent-Toolkit-UI/issues
- **NAT Backend**: Check NAT wrapper logs
- **Integration**: Review this guide and check-services.sh output
