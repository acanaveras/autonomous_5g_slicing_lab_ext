#!/bin/bash

# SPDX-FileCopyrightText: Copyright (c) 2023-2024 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: Apache-2.0
#
# Build script for OpenAirInterface UE Docker image

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "========================================"
echo "Building UE Docker Image"
echo "========================================"
echo ""

# Check if configuration files exist
if [ ! -f "ue-slice1.conf" ] || [ ! -f "ue-slice2.conf" ]; then
    echo "❌ Error: UE configuration files not found"
    echo "   Expected: ue-slice1.conf, ue-slice2.conf"
    exit 1
fi

echo "✅ Configuration files present"
echo ""

# Parse command line arguments
NO_CACHE=""
if [ "$1" == "--no-cache" ]; then
    NO_CACHE="--no-cache"
    echo "🔄 Building with --no-cache flag"
fi

# Build the image
echo "🏗️  Building UE image..."
echo "   This will take approximately 2-3 minutes"
echo "   (Reusing binaries from gNodeB build)"
echo ""

cd /home/ubuntu/autonomous_5g_slicing_lab_ext/llm-slicing-5g-lab
docker build -f docker/Dockerfile.ue -t oai-ue-5g-slicing:latest . $NO_CACHE

if [ $? -eq 0 ]; then
    echo ""
    echo "========================================"
    echo "✅ UE Image Built Successfully!"
    echo "========================================"
    echo ""
    echo "Image name: oai-ue-5g-slicing:latest"
    echo ""
    echo "Next steps:"
    echo "  1. Ensure 5G Core Network is running:"
    echo "     cd .."
    echo "     docker-compose -f docker-compose-oai-cn-slice1.yaml up -d"
    echo "     docker-compose -f docker-compose-oai-cn-slice2.yaml up -d"
    echo ""
    echo "  2. Ensure FlexRIC and gNodeB are running:"
    echo "     cd docker"
    echo "     docker-compose -f docker-compose-gnb.yaml up -d"
    echo ""
    echo "  3. Start UEs:"
    echo "     docker-compose -f docker-compose-ue.yaml up -d"
    echo ""
    echo "  4. View logs:"
    echo "     docker logs -f oai-ue-slice1"
    echo "     docker logs -f oai-ue-slice2"
    echo ""
    echo "  5. Test connectivity:"
    echo "     docker exec oai-ue-slice1 ping -I oaitun_ue1 -c 4 8.8.8.8"
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
