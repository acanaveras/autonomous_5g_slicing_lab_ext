#!/bin/bash

# Script to start NeMo UI on port 5001
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
    echo "Please run the setup script first: ./scripts/setup-nemo-ui.sh"
    exit 1
fi

# Check if .env exists
if [ ! -f "$NEMO_UI_DIR/.env" ]; then
    echo "⚠️  Warning: .env file not found in nemo-ui/"
    echo "Creating .env from template..."
    cp nemo-ui.env.template "$NEMO_UI_DIR/.env"
fi

# Navigate to nemo-ui and start
cd "$NEMO_UI_DIR"

# Check if node_modules exists
if [ ! -d "node_modules" ]; then
    echo "📦 Installing dependencies..."
    npm ci
fi

# Start in development mode
echo "🔄 Starting development server..."
PORT=5001 npm run dev
