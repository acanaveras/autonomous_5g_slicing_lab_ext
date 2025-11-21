#!/bin/bash

# SPDX-FileCopyrightText: Copyright (c) 2023-2024 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: Apache-2.0
#
# Build script for Streamlit UI Docker image

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

IMAGE_NAME="streamlit-5g-ui"
IMAGE_TAG="latest"

echo "========================================="
echo "Building Streamlit UI Docker Image"
echo "========================================="
echo ""

# Check if required files exist
if [[ ! -f "Dockerfile.streamlit" ]]; then
    echo "ERROR: Dockerfile.streamlit not found!"
    exit 1
fi

if [[ ! -f "../../agentic-llm/requirements_grafana.txt" ]]; then
    echo "ERROR: requirements_grafana.txt not found!"
    exit 1
fi

if [[ ! -f "../../agentic-llm/chatbot_DLI.py" ]]; then
    echo "ERROR: chatbot_DLI.py not found!"
    exit 1
fi

echo "Configuration:"
echo "  Image Name: $IMAGE_NAME:$IMAGE_TAG"
echo "  Build Context: ../.."
echo "  Dockerfile: llm-slicing-5g-lab/docker/Dockerfile.streamlit"
echo ""

# Change to build context directory
cd ../..

# Build with optional --no-cache flag
if [[ "$1" == "--no-cache" ]]; then
    echo "Building with --no-cache flag..."
    docker build \
        --no-cache \
        -f llm-slicing-5g-lab/docker/Dockerfile.streamlit \
        -t "$IMAGE_NAME:$IMAGE_TAG" \
        .
else
    echo "Building (using cache if available)..."
    docker build \
        -f llm-slicing-5g-lab/docker/Dockerfile.streamlit \
        -t "$IMAGE_NAME:$IMAGE_TAG" \
        .
fi

echo ""
echo "========================================="
echo "Build Complete!"
echo "========================================="
echo ""
echo "Image: $IMAGE_NAME:$IMAGE_TAG"
echo ""
echo "To run the container:"
echo "  docker compose -f docker-compose-monitoring.yaml up -d streamlit"
echo ""
echo "Or to start the full monitoring stack:"
echo "  docker compose -f docker-compose-monitoring.yaml up -d"
echo ""
