# SPDX-FileCopyrightText: Copyright (c) 2025, NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: Apache-2.0

# Build arguments
ARG NAT_VERSION=latest

# Base stage: Install NeMo Agent Toolkit
FROM python:3.11-slim as base

# Install system dependencies
RUN apt-get update && apt-get install -y \
    git \
    curl \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /workspace

# Copy the entire project
COPY . /workspace/

# Install NeMo Agent Toolkit (assuming it's in the repo or will be pip installed)
RUN pip install --no-cache-dir nvidia-nat[langchain]~=1.4

# Install this workflow package
WORKDIR /workspace/agentic-llm/nat_wrapper
RUN pip install --no-cache-dir -e .

# Final stage: Runtime
FROM python:3.11-slim

# Install runtime dependencies only
RUN apt-get update && apt-get install -y \
    curl \
    bash \
    && rm -rf /var/lib/apt/lists/*

# Copy installed packages from base
COPY --from=base /usr/local/lib/python3.11/site-packages /usr/local/lib/python3.11/site-packages
COPY --from=base /usr/local/bin /usr/local/bin

# Copy workspace
COPY --from=base /workspace /workspace

# Set working directory
WORKDIR /workspace/agentic-llm/nat_wrapper

# Expose ports
# 4999: FastAPI server
# 6006: Phoenix telemetry
EXPOSE 4999 6006

# Environment variables (will be overridden by docker run --env-file)
ENV NVIDIA_API_KEY=""
ENV KINETICA_HOST="localhost:9191"
ENV KINETICA_USERNAME="admin"
ENV KINETICA_PASSWORD="admin"
ENV KINETICA_SCHEMA="nvidia_gtc_dli_2025"
ENV IPERF3_RANDOM_TABLE_NAME="nvidia_gtc_dli_2025.iperf3_logs"
ENV RECONFIG_SCRIPT_PATH="../llm-slicing-5g-lab/docker/change_rc_slice_docker.sh"

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=40s --retries=3 \
  CMD curl -f http://localhost:4999/health || exit 1

# Start NAT server
CMD ["nat", "serve", "--config_file", "src/nat_5g_slicing/configs/config.yml", "--host", "0.0.0.0", "--port", "4999"]
