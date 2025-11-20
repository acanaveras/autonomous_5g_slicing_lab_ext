#!/bin/bash

# SPDX-FileCopyrightText: Copyright (c) 2023-2024 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: Apache-2.0
#
# Build script for FlexRIC Docker image

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "========================================"
echo "Building FlexRIC Docker Image"
echo "========================================"
echo ""

# Check if extra_files directory exists
if [ ! -d "../extra_files" ]; then
    echo "❌ Error: extra_files directory not found"
    echo "   Expected location: ../extra_files"
    exit 1
fi

# Check if required files exist
REQUIRED_FILES=(
    "../extra_files/xapp_rc_slice_dynamic.c"
    "../extra_files/CMakeLists.txt"
)

for file in "${REQUIRED_FILES[@]}"; do
    if [ ! -f "$file" ]; then
        echo "❌ Error: Required file not found: $file"
        exit 1
    fi
done

echo "✅ All required files present"
echo ""

# Parse command line arguments
NO_CACHE=""
if [ "$1" == "--no-cache" ]; then
    NO_CACHE="--no-cache"
    echo "🔄 Building with --no-cache flag"
fi

# Build the image
echo "🏗️  Building FlexRIC image..."
echo "   This will take approximately 10-15 minutes"
echo ""

docker compose -f docker-compose-flexric.yaml build $NO_CACHE

if [ $? -eq 0 ]; then
    echo ""
    echo "========================================"
    echo "✅ FlexRIC Image Built Successfully!"
    echo "========================================"
    echo ""
    echo "Image name: flexric-5g-slicing:latest"
    echo ""
    echo "Next steps:"
    echo "  1. Start 5G Core Network (if not already running):"
    echo "     cd .."
    echo "     docker-compose -f docker-compose-oai-cn-slice1.yaml up -d"
    echo "     docker-compose -f docker-compose-oai-cn-slice2.yaml up -d"
    echo ""
    echo "  2. Start FlexRIC:"
    echo "     cd docker"
    echo "     docker compose -f docker-compose-flexric.yaml up -d"
    echo ""
    echo "  3. View logs:"
    echo "     docker logs -f flexric"
    echo ""
    echo "  4. Change slice allocation:"
    echo "     ./change_rc_slice_docker.sh 60 40"
    echo ""
else
    echo ""
    echo "========================================"
    echo "❌ Build Failed"
    echo "========================================"
    echo ""
    echo "Please check the error messages above"
    exit 1
fi
