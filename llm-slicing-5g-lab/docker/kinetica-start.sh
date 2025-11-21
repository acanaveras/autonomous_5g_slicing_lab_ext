#!/bin/bash
# Start Kinetica with automatic GPUdb startup

# Fix permissions on persist directory to avoid permission issues
echo "Fixing permissions and creating directories..."
chown -R root:root /opt/gpudb/persist 2>/dev/null || true
chmod -R 777 /opt/gpudb/persist 2>/dev/null || true

# Create necessary directories that Kinetica needs
mkdir -p /opt/gpudb/persist/tmp
mkdir -p /opt/gpudb/persist/logs
mkdir -p /opt/gpudb/persist/data
chmod -R 777 /opt/gpudb/persist

# Start the host manager and supporting services
ldconfig
/opt/gpudb-docker-start.sh &

# Wait for host manager to be ready
echo "Waiting for Host Manager to start..."
for i in {1..60}; do
    if /opt/gpudb/core/bin/gpudb status 2>&1 | grep -q "Host Manager.*Running"; then
        echo "Host Manager is running"
        break
    fi
    sleep 2
done

# Wait a bit more for complete initialization
sleep 15

# Start GPUdb database
echo "Starting GPUdb database..."
/opt/gpudb/core/bin/gpudb start

# Tail logs to keep container running
tail -f /opt/gpudb/core/logs/gpudb.log
