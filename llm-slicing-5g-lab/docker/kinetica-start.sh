#!/bin/bash
# Start Kinetica with automatic GPUdb startup

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
