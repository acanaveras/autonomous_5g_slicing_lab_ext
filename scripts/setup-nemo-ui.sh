#!/bin/bash

# Setup script for NeMo Agent Toolkit UI
# This script adds NeMo UI as a git submodule and configures it
# Usage: ./scripts/setup-nemo-ui.sh

set -e

PROJECT_ROOT="$(dirname "$0")/.."
cd "$PROJECT_ROOT"

echo "🚀 Setting up NeMo Agent Toolkit UI"
echo "===================================="
echo ""

# Step 1: Add as git submodule
echo "📦 Step 1/5: Adding NeMo UI as git submodule..."
if [ -d "nemo-ui" ]; then
    echo "⚠️  nemo-ui directory already exists"
    echo "Do you want to remove it and re-clone? (y/n)"
    read -r response
    if [[ "$response" =~ ^[Yy]$ ]]; then
        echo "Removing existing nemo-ui..."
        rm -rf nemo-ui
        git submodule deinit -f nemo-ui 2>/dev/null || true
        git rm -f nemo-ui 2>/dev/null || true
    else
        echo "Skipping submodule addition..."
    fi
fi

if [ ! -d "nemo-ui" ]; then
    git submodule add https://github.com/NVIDIA/NeMo-Agent-Toolkit-UI.git nemo-ui
    git submodule update --init --recursive
    echo "✅ Submodule added successfully"
else
    echo "✅ Using existing nemo-ui directory"
fi
echo ""

# Step 2: Install dependencies
echo "📦 Step 2/5: Installing Node.js dependencies..."
cd nemo-ui
npm ci
echo "✅ Dependencies installed"
echo ""

# Step 3: Create .env file
echo "⚙️  Step 3/5: Creating .env configuration..."
if [ -f ".env" ]; then
    echo "⚠️  .env already exists, creating backup..."
    cp .env .env.backup
fi

cat > .env << 'EOF'
# NeMo Agent Toolkit UI Configuration
NAT_BACKEND_URL=http://localhost:4999
NEXT_PUBLIC_NAT_WEB_SOCKET_DEFAULT_ON=true
NEXT_PUBLIC_NAT_ENABLE_INTERMEDIATE_STEPS=true
NEXT_PUBLIC_NAT_DEFAULT_MODEL=meta/llama-3.1-70b-instruct
PORT=5001
EOF
echo "✅ .env file created"
echo ""

# Step 4: Verify NAT server is accessible
echo "🔍 Step 4/5: Checking NAT server availability..."
if curl -s -o /dev/null -w "%{http_code}" http://localhost:4999/generate > /dev/null 2>&1; then
    echo "✅ NAT server is accessible on port 4999"
else
    echo "⚠️  Warning: NAT server not responding on port 4999"
    echo "   Make sure to start the NAT server before using the UI:"
    echo "   cd agentic-llm/nat_wrapper"
    echo "   nat serve --config_file src/nat_5g_slicing/configs/config.yml --host 0.0.0.0 --port 4999"
fi
echo ""

# Step 5: Commit changes
echo "📝 Step 5/5: Committing changes to git..."
cd "$PROJECT_ROOT"
git add .gitmodules nemo-ui 2>/dev/null || true
echo "Submodule added. You can commit with:"
echo "  git commit -m 'Add NeMo Agent Toolkit UI as submodule'"
echo ""

echo "===================================="
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
