#!/bin/bash

# SPDX-FileCopyrightText: Copyright (c) 2023-2024 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: Apache-2.0
#
# Build script for OpenAirInterface gNodeB Docker image

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "========================================"
echo "Building gNodeB Docker Image"
echo "========================================"
echo ""

# Check if configuration file exists
if [ ! -f "gnb-docker.conf" ]; then
    echo "❌ Error: gnb-docker.conf not found"
    echo "   Expected location: $SCRIPT_DIR/gnb-docker.conf"
    exit 1
fi

echo "✅ Configuration file present"
echo ""

# Parse command line arguments
NO_CACHE=""
if [ "$1" == "--no-cache" ]; then
    NO_CACHE="--no-cache"
    echo "🔄 Building with --no-cache flag"
fi

# Build the image
echo "🏗️  Building gNodeB image..."
echo "   This will take approximately 15-20 minutes"
echo "   (Compiling OpenAirInterface from source)"
echo ""

docker compose -f docker-compose-gnb.yaml build $NO_CACHE oai-gnb

if [ $? -eq 0 ]; then
    echo ""
    echo "========================================"
    echo "✅ gNodeB Image Built Successfully!"
    echo "========================================"
    echo ""
    echo "Image name: oai-gnb-5g-slicing:latest"
    echo ""
    echo "Next steps:"
    echo "  1. Ensure FlexRIC is running:"
    echo "     docker compose -f docker-compose-flexric.yaml up -d"
    echo ""
    echo "  2. Ensure 5G Core Network is running:"
    echo "     cd .."
    echo "     docker compose -f docker-compose-oai-cn-slice1.yaml up -d"
    echo "     docker compose -f docker-compose-oai-cn-slice2.yaml up -d"
    echo ""
    echo "  3. Start gNodeB:"
    echo "     cd docker"
    echo "     docker compose -f docker-compose-gnb.yaml up -d oai-gnb"
    echo ""
    echo "  4. View logs:"
    echo "     docker logs -f oai-gnb"
    echo "     # or"
    echo "     tail -f ../logs/gNodeB_docker.log"
    echo ""
    echo "  5. Check E2 connection:"
    echo "     docker logs flexric | grep 'E2 SETUP'"
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
