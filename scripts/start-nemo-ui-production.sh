#!/bin/bash

# Script to start NeMo UI in production mode on port 5001
# Usage: ./scripts/start-nemo-ui-production.sh

set -e

NEMO_UI_DIR="$(dirname "$0")/../nemo-ui"

echo "🔨 Building NeMo UI for production..."

# Check if nemo-ui directory exists
if [ ! -d "$NEMO_UI_DIR" ]; then
    echo "❌ Error: nemo-ui directory not found!"
    echo "Please run the setup script first: ./scripts/setup-nemo-ui.sh"
    exit 1
fi

cd "$NEMO_UI_DIR"

# Build
npm run build

echo ""
echo "🚀 Starting NeMo UI in production mode on port 5001..."
echo "📍 Backend: http://localhost:4999"
echo "🌐 UI will be available at: http://localhost:5001"
echo ""

# Start in production mode
PORT=5001 npm start
