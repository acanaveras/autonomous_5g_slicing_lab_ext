#!/bin/bash

# Script to start NeMo UI on port 5001 (Development Mode)
# Usage: ./scripts/start-nemo-ui.sh

set -e

NEMO_UI_DIR="$(dirname "$0")/../nemo-ui"

echo "🚀 Starting NeMo Agent Toolkit UI on port 5001..."
echo "📍 Backend: http://localhost:4999"
echo "🌐 UI will be available at: http://localhost:5001"
echo ""

# Check if nemo-ui directory exists
if [ ! -d "$NEMO_UI_DIR" ]; then
    echo "❌ Error: nemo-ui directory not found!"
    echo "Please run the setup script first: ./scripts/setup-nemo-ui-fixed.sh"
    exit 1
fi

# Navigate to nemo-ui
cd "$NEMO_UI_DIR"

# Check if .env exists
if [ ! -f ".env" ]; then
    echo "⚠️  Warning: .env file not found, creating default..."
    cat > .env << 'EOF'
NAT_BACKEND_URL=http://localhost:4999
NEXT_PUBLIC_NAT_WEB_SOCKET_DEFAULT_ON=true
NEXT_PUBLIC_NAT_ENABLE_INTERMEDIATE_STEPS=true
PORT=5001
EOF
fi

# Check if node_modules exists
if [ ! -d "node_modules" ]; then
    echo "📦 Installing dependencies..."
    npm ci
fi

# Start in development mode
echo "🔄 Starting development server..."
echo ""
PORT=5001 npm run dev
