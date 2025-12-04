#!/bin/bash

# Make all scripts executable
# Run this once after pulling the code to your GPU machine

echo "🔧 Setting executable permissions on all scripts..."

SCRIPT_DIR="$(dirname "$0")"

chmod +x "$SCRIPT_DIR/setup-nemo-ui.sh"
chmod +x "$SCRIPT_DIR/start-nemo-ui.sh"
chmod +x "$SCRIPT_DIR/start-nemo-ui-production.sh"
chmod +x "$SCRIPT_DIR/start-all-services.sh"
chmod +x "$SCRIPT_DIR/stop-all-services.sh"
chmod +x "$SCRIPT_DIR/check-services.sh"
chmod +x "$SCRIPT_DIR/make-executable.sh"

echo "✅ All scripts are now executable"
echo ""
echo "Available scripts:"
echo "  ./scripts/setup-nemo-ui.sh              - Initial setup"
echo "  ./scripts/start-nemo-ui.sh              - Start NeMo UI (dev)"
echo "  ./scripts/start-nemo-ui-production.sh   - Start NeMo UI (prod)"
echo "  ./scripts/start-all-services.sh         - Start all services"
echo "  ./scripts/stop-all-services.sh          - Stop all services"
echo "  ./scripts/check-services.sh             - Check service status"
echo ""
