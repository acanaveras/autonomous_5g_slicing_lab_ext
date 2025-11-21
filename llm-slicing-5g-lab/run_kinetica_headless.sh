#!/usr/bin/env bash

# Headless Kinetica Docker Installation Script
# This script runs the Kinetica Docker container without user intervention

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KINETICA_SCRIPT="$SCRIPT_DIR/kinetica"
ADMIN_PASSWORD="admin"  # Kinetica default password
PERSIST_DIR="$SCRIPT_DIR/kinetica-data"  # Data persistence directory

# Export the password so the script can use it
export KINETICA_ADMIN_PASSWORD="$ADMIN_PASSWORD"

echo "=========================================="
echo "Starting Kinetica Docker Installation"
echo "=========================================="
echo "Admin Password: $ADMIN_PASSWORD"
echo "Data Directory: $PERSIST_DIR"
echo ""


# Download Kinetica bootstrap script if not exists
if [[ ! -f "./kinetica" ]]; then
    echo "📥 Downloading Kinetica bootstrap script..."
    curl https://files.kinetica.com/install/kinetica.sh -o kinetica
    chmod u+x kinetica
else
    echo "✅ Kinetica bootstrap script already exists"
fi


# Make the script executable
chmod +x "$KINETICA_SCRIPT"

# Stop and remove any existing container (clean slate)
echo "Cleaning up any existing installation..."
"$KINETICA_SCRIPT" kill 2>/dev/null || true
"$KINETICA_SCRIPT" rm 2>/dev/null || true

# Install Kinetica
echo ""
echo "Installing Kinetica Docker container..."
"$KINETICA_SCRIPT" install --persist "$PERSIST_DIR"

# Start the container
echo ""
echo "Starting Kinetica..."
"$KINETICA_SCRIPT" start --persist "$PERSIST_DIR"

# Check status
echo ""
echo "Checking Kinetica status..."
"$KINETICA_SCRIPT" status

echo ""
echo "=========================================="
echo "Kinetica Installation Complete!"
echo "=========================================="
echo ""
echo "Access Points:"
echo "  Workbench:      http://localhost:8000/workbench"
echo "  Admin Console:  http://localhost:8080/gadmin"
echo "  Reveal UI:      http://localhost:8088"
echo "  Database REST:  http://localhost:9191"
echo "  Postgres Wire:  localhost:5434"
echo ""
echo "Login Credentials:"
echo "  Username: admin"
echo "  Password: $ADMIN_PASSWORD"
echo ""
echo "Data is persisted at: $PERSIST_DIR"
echo ""
echo "To stop Kinetica, run: $KINETICA_SCRIPT stop"
echo "To restart Kinetica, run: $KINETICA_SCRIPT start --persist $PERSIST_DIR"

