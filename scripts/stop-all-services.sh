#!/bin/bash

# Script to stop all 5G Network Agent services
# Usage: ./scripts/stop-all-services.sh

echo "🛑 Stopping all 5G Network Agent services..."
echo "=============================================="
echo ""

# Function to stop process by port
stop_by_port() {
    local port=$1
    local name=$2

    echo "Stopping $name (port $port)..."
    PID=$(lsof -ti:$port 2>/dev/null)
    if [ ! -z "$PID" ]; then
        kill $PID 2>/dev/null || kill -9 $PID 2>/dev/null
        echo "✅ Stopped $name (PID: $PID)"
    else
        echo "⚠️  $name not running"
    fi
}

# Stop NeMo UI (port 5001)
stop_by_port 5001 "NeMo UI"
echo ""

# Stop NAT Server (port 4999)
stop_by_port 4999 "NAT Server"
echo ""

# Stop Phoenix
echo "Stopping Phoenix..."
if command -v docker >/dev/null 2>&1; then
    docker stop phoenix 2>/dev/null && echo "✅ Phoenix stopped" || echo "⚠️  Phoenix not running"
else
    echo "⚠️  Docker not available, skipping Phoenix"
fi
echo ""

# Clean up log files (optional)
echo "Cleaning up log files..."
rm -f /tmp/nat-server.log /tmp/nemo-ui.log
echo "✅ Log files cleaned"
echo ""

echo "=============================================="
echo "✅ All services stopped!"
echo ""
