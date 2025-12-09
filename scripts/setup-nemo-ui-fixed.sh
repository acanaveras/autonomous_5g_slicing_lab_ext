#!/bin/bash

# Fixed setup script for NeMo Agent Toolkit UI
# This version handles broken git submodule configurations
# Usage: ./scripts/setup-nemo-ui-fixed.sh

set -e

PROJECT_ROOT="$(dirname "$0")/.."
cd "$PROJECT_ROOT"

echo "🚀 Setting up NeMo Agent Toolkit UI (Fixed Version)"
echo "===================================================="
echo ""

# Step 1: Clone NeMo UI (direct clone, not submodule)
echo "📦 Step 1/5: Cloning NeMo UI repository..."
if [ -d "nemo-ui" ]; then
    echo "⚠️  nemo-ui directory already exists"
    echo "Do you want to remove it and re-clone? (y/n)"
    read -r response
    if [[ "$response" =~ ^[Yy]$ ]]; then
        echo "Removing existing nemo-ui..."
        rm -rf nemo-ui
    else
        echo "Using existing nemo-ui directory..."
    fi
fi

if [ ! -d "nemo-ui" ]; then
    git clone https://github.com/NVIDIA/NeMo-Agent-Toolkit-UI.git nemo-ui
    echo "✅ NeMo UI cloned successfully"
else
    echo "✅ Using existing nemo-ui directory"
fi
echo ""

# Step 2: Install dependencies
echo "📦 Step 2/5: Installing Node.js dependencies..."
cd nemo-ui

# Check if Node.js is installed
if ! command -v node &> /dev/null; then
    echo "❌ Error: Node.js is not installed!"
    echo "Please install Node.js first:"
    echo "  curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -"
    echo "  sudo apt-get install -y nodejs"
    exit 1
fi

echo "Node.js version: $(node --version)"
echo "npm version: $(npm --version)"
echo ""

npm ci
echo "✅ Dependencies installed"
echo ""

# Step 3: Create .env file
echo "⚙️  Step 3/5: Creating .env configuration..."
if [ -f ".env" ]; then
    echo "⚠️  .env already exists, creating backup..."
    cp .env .env.backup.$(date +%s)
fi

cat > .env << 'EOF'
# Backend Configuration
NAT_BACKEND_URL=http://localhost:4999

# Application Settings
NEXT_PUBLIC_NAT_WEB_SOCKET_DEFAULT_ON=true
NEXT_PUBLIC_NAT_ENABLE_INTERMEDIATE_STEPS=true

# Port Configuration
PORT=5001
EOF
echo "✅ .env file created"
echo ""

# Step 4: Verify NAT server is accessible
echo "🔍 Step 4/5: Checking NAT server availability..."
if curl -s -f -X POST http://localhost:4999/generate \
    -H "Content-Type: application/json" \
    -d '{"input_message": "ping"}' > /dev/null 2>&1; then
    echo "✅ NAT server is accessible on port 4999"
else
    echo "⚠️  Warning: NAT server not responding on port 4999"
    echo "   Make sure to start the NAT server before using the UI:"
    echo "   cd agentic-llm/nat_wrapper"
    echo "   nat serve --config_file src/nat_5g_slicing/configs/config.yml --host 0.0.0.0 --port 4999"
fi
echo ""

# Step 5: Add to .gitignore
echo "📝 Step 5/5: Updating .gitignore..."
cd "$PROJECT_ROOT"
if ! grep -q "^nemo-ui/$" .gitignore 2>/dev/null; then
    echo "nemo-ui/" >> .gitignore
    echo "✅ Added nemo-ui/ to .gitignore"
else
    echo "✅ nemo-ui/ already in .gitignore"
fi
echo ""

echo "===================================================="
echo "✅ Setup complete!"
echo ""
echo "📍 Next steps:"
echo "   1. Start the NAT server (if not already running):"
echo "      cd agentic-llm/nat_wrapper"
echo "      nat serve --config_file src/nat_5g_slicing/configs/config.yml --host 0.0.0.0 --port 4999"
echo ""
echo "   2. Start the NeMo UI:"
echo "      ./scripts/start-nemo-ui.sh"
echo ""
echo "   3. Access the UI at: http://localhost:5001"
echo ""
echo "Note: NeMo UI is cloned directly (not as git submodule) to avoid"
echo "      conflicts with existing broken submodule configurations."
echo ""
