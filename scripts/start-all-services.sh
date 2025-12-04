#!/bin/bash

# Unified startup script for all 5G Network Agent services
# Usage: ./scripts/start-all-services.sh

set -e

echo "🚀 Starting all 5G Network Agent services..."
echo "=============================================="
echo ""

# Function to check if a port is in use
check_port() {
    if lsof -Pi :$1 -sTCP:LISTEN -t >/dev/null 2>&1 ; then
        return 1  # Port in use
    else
        return 0  # Port available
    fi
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check required commands
echo "Checking requirements..."
if ! command_exists docker; then
    echo "⚠️  Warning: docker not found (Phoenix won't start)"
fi
if ! command_exists nat; then
    echo "⚠️  Warning: nat command not found (NAT server won't start)"
fi
if ! command_exists node; then
    echo "❌ Error: node not found. Please install Node.js"
    exit 1
fi
echo ""

# Check ports
echo "Checking ports..."
check_port 4999 || echo "⚠️  Port 4999 (NAT Server) is already in use"
check_port 5001 || echo "⚠️  Port 5001 (NeMo UI) is already in use"
check_port 6006 || echo "⚠️  Port 6006 (Phoenix) is already in use"
echo ""

# 1. Start Phoenix (if not running)
echo "📊 Starting Phoenix on port 6006..."
if check_port 6006; then
    if command_exists docker; then
        # Try to start existing container, or create new one
        docker start phoenix 2>/dev/null || \
        docker run -d \
            -p 6006:6006 \
            -p 4317:4317 \
            --name phoenix \
            arizephoenix/phoenix:latest
        echo "✅ Phoenix started"
    else
        echo "⚠️  Docker not available, skipping Phoenix"
    fi
else
    echo "✅ Phoenix already running"
fi
echo ""

# 2. Start NAT Server
echo "🤖 Starting NAT Server on port 4999..."
if check_port 4999; then
    if command_exists nat; then
        cd "$(dirname "$0")/../agentic-llm/nat_wrapper"
        nohup nat serve \
            --config_file src/nat_5g_slicing/configs/config.yml \
            --host 0.0.0.0 \
            --port 4999 \
            > /tmp/nat-server.log 2>&1 &
        NAT_PID=$!
        echo "✅ NAT Server started (PID: $NAT_PID)"
        echo "   Logs: tail -f /tmp/nat-server.log"
        # Wait a bit for server to start
        sleep 3
    else
        echo "❌ NAT command not found. Please install nvidia-nat"
        echo "   cd agentic-llm/nat_wrapper"
        echo "   uv pip install -e ."
    fi
else
    echo "✅ NAT Server already running"
fi
echo ""

# 3. Start NeMo UI
echo "🌐 Starting NeMo UI on port 5001..."
if check_port 5001; then
    if [ -d "$(dirname "$0")/../nemo-ui" ]; then
        cd "$(dirname "$0")/../nemo-ui"

        # Check if .env exists
        if [ ! -f ".env" ]; then
            echo "Creating .env file..."
            cp ../nemo-ui.env.template .env
        fi

        # Check if node_modules exists
        if [ ! -d "node_modules" ]; then
            echo "Installing dependencies..."
            npm ci
        fi

        nohup npm run dev -- -p 5001 > /tmp/nemo-ui.log 2>&1 &
        NEMO_PID=$!
        echo "✅ NeMo UI started (PID: $NEMO_PID)"
        echo "   Logs: tail -f /tmp/nemo-ui.log"
        # Wait for UI to start
        sleep 5
    else
        echo "❌ nemo-ui directory not found"
        echo "   Run setup first: ./scripts/setup-nemo-ui.sh"
    fi
else
    echo "✅ NeMo UI already running"
fi
echo ""

echo "=============================================="
echo "✅ All services started!"
echo ""
echo "📍 Service URLs:"
echo "   - NAT Server:  http://localhost:4999"
echo "   - NeMo UI:     http://localhost:5001"
echo "   - Phoenix:     http://localhost:6006"
echo ""
echo "📋 Check logs:"
echo "   - NAT Server:  tail -f /tmp/nat-server.log"
echo "   - NeMo UI:     tail -f /tmp/nemo-ui.log"
echo ""
echo "🛑 To stop all services: ./scripts/stop-all-services.sh"
echo ""
