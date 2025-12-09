#!/bin/bash

# Script to check status of all services
# Usage: ./scripts/check-services.sh

echo "🔍 Checking 5G Network Agent Services Status"
echo "=============================================="
echo ""

# Function to check if a port is in use
check_port() {
    local port=$1
    local name=$2
    local url=$3

    if lsof -Pi :$port -sTCP:LISTEN -t >/dev/null 2>&1 ; then
        PID=$(lsof -ti:$port 2>/dev/null)
        echo "✅ $name is RUNNING (Port: $port, PID: $PID)"
        if [ ! -z "$url" ]; then
            echo "   URL: $url"
        fi
        return 0
    else
        echo "❌ $name is NOT running (Port: $port)"
        return 1
    fi
}

# Check each service
check_port 4999 "NAT Server" "http://localhost:4999"
echo ""

check_port 5001 "NeMo UI" "http://localhost:5001"
echo ""

check_port 6006 "Phoenix" "http://localhost:6006"
echo ""

# Check if NeMo UI directory exists
if [ -d "$(dirname "$0")/../nemo-ui" ]; then
    echo "✅ NeMo UI submodule exists"
else
    echo "❌ NeMo UI submodule not found"
    echo "   Run: ./scripts/setup-nemo-ui.sh"
fi
echo ""

# Test NAT server endpoint
echo "Testing NAT Server endpoint..."
if command -v curl >/dev/null 2>&1; then
    response=$(curl -s -o /dev/null -w "%{http_code}" -X POST http://localhost:4999/generate \
        -H "Content-Type: application/json" \
        -d '{"input_message": "ping"}' 2>/dev/null)

    if [ "$response" = "200" ]; then
        echo "✅ NAT Server /generate endpoint responding"
    else
        echo "⚠️  NAT Server endpoint returned: $response"
    fi
else
    echo "⚠️  curl not available, skipping endpoint test"
fi
echo ""

echo "=============================================="
echo "📋 Log files:"
if [ -f "/tmp/nat-server.log" ]; then
    echo "   NAT Server: /tmp/nat-server.log"
fi
if [ -f "/tmp/nemo-ui.log" ]; then
    echo "   NeMo UI: /tmp/nemo-ui.log"
fi
echo ""
