#!/bin/bash

# SPDX-FileCopyrightText: Copyright (c) 2023-2024 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: Apache-2.0
#
# Docker-compatible script to change RC slice bandwidth allocation
# This script executes the xApp inside the FlexRIC container
#
# Usage: ./change_rc_slice_docker.sh <slice1_ratio> <slice2_ratio>
# Example: ./change_rc_slice_docker.sh 60 40

set -e

CONTAINER_NAME="flexric"

# Check if arguments are provided
if [ -z "$1" ] || [ -z "$2" ]; then
    echo "Usage: $0 <slice1_ratio> <slice2_ratio>"
    echo "Example: $0 60 40"
    exit 1
fi

SLICE1_RATIO=$1
SLICE2_RATIO=$2

# Validate that ratios are numbers
if ! [[ "$SLICE1_RATIO" =~ ^[0-9]+$ ]] || ! [[ "$SLICE2_RATIO" =~ ^[0-9]+$ ]]; then
    echo "Error: Ratios must be numeric values"
    exit 1
fi

echo "================================================"
echo "Changing Slice Bandwidth Allocation"
echo "================================================"
echo "Slice 1 Ratio: ${SLICE1_RATIO}%"
echo "Slice 2 Ratio: ${SLICE2_RATIO}%"
echo "================================================"

# Check if container is running
if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    echo "Error: FlexRIC container '${CONTAINER_NAME}' is not running"
    echo "Please start the container first with: docker-compose -f docker/docker-compose-flexric.yaml up -d"
    exit 1
fi

# Execute xApp inside the container
echo "Executing xApp to reconfigure slices..."
docker exec -e SLICE1_RATIO=${SLICE1_RATIO} -e SLICE2_RATIO=${SLICE2_RATIO} \
    ${CONTAINER_NAME} \
    /usr/local/bin/xapp_rc_slice_dynamic

echo "================================================"
echo "Slice reconfiguration completed successfully"
echo "================================================"
