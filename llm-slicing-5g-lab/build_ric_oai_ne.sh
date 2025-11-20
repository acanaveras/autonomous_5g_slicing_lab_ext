#!/bin/bash

# SPDX-FileCopyrightText: Copyright (c) 2023-2024 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: Apache-2.0
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.


# Note: Not using set -e to allow better error handling and recovery

# Save the initial directory
INITIAL_DIR=$(pwd)

# Step 0: Install necessary compilers (gcc-12, g++-12)
echo ">>> Checking compilers..."
if ! gcc-12 --version &>/dev/null || ! g++-12 --version &>/dev/null; then
    echo ">>> Installing gcc-12, g++-12..."
    sudo apt update
    sudo apt install -y gcc-12 g++-12
    sudo update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-12 100
    sudo update-alternatives --install /usr/bin/g++ g++ /usr/bin/g++-12 100
else
    echo ">>> Compilers already installed"
fi

# Step 1: Clone and build openairinterface5g
echo ">>> Cloning and building openairinterface5g..."

# Handle existing directory
if [ -d "openairinterface5g" ]; then
    echo ">>> openairinterface5g directory exists, checking contents..."
    if [ -d "openairinterface5g/.git" ]; then
        echo ">>> Updating existing repository..."
        cd openairinterface5g || { echo "Failed to enter openairinterface5g directory"; exit 1; }
        git fetch origin
        git checkout slicing-spring-of-code
        git pull origin slicing-spring-of-code || true
    else
        echo ">>> Removing empty directory and cloning..."
        rm -rf openairinterface5g
        git clone https://gitlab.eurecom.fr/oai/openairinterface5g
        cd openairinterface5g || { echo "Failed to enter openairinterface5g directory"; exit 1; }
        git checkout slicing-spring-of-code
    fi
else
    git clone https://gitlab.eurecom.fr/oai/openairinterface5g
    cd openairinterface5g || { echo "Failed to enter openairinterface5g directory"; exit 1; }
    git checkout slicing-spring-of-code
fi
cd cmake_targets || { echo "Failed to enter cmake_targets"; exit 1; }

# Build openairinterface5g
# Check if key dependencies are already installed
if [ ! -f "/opt/asn1c/bin/asn1c" ]; then
    echo ">>> Installing OAI dependencies (this may take a few minutes)..."
    # Run dependency installation - ignore exit code as the script has an aggressive exit trap
    ./build_oai -I || true

    # Verify critical dependencies are installed
    echo ">>> Verifying critical dependencies..."
    if [ ! -f "/opt/asn1c/bin/asn1c" ]; then
        echo "ERROR: ASN1C not installed. Check logs in openairinterface5g/cmake_targets/log/"
        exit 1
    fi
    if [ ! -d "/usr/include/simde" ]; then
        echo "WARNING: SIMDE headers not found, but continuing..."
    fi
    echo ">>> Dependencies verified successfully"
else
    echo ">>> OAI dependencies already installed, skipping..."
fi

echo ">>> Building OAI gNB and nrUE (this will take 30-45 minutes)..."
./build_oai -c -C -w SIMU --gNB --nrUE --build-e2 --ninja || { echo "Failed to build OAI"; exit 1; }

# Step 2: Go back to the initial directory
cd "$INITIAL_DIR" || { echo "Failed to return to initial directory"; exit 1; }

# Step 3: Clone and build flexric
echo ">>> Cloning and building flexric..."

# Handle existing directory
if [ -d "flexric" ]; then
    echo ">>> flexric directory exists, checking contents..."
    if [ -d "flexric/.git" ]; then
        echo ">>> Updating existing repository..."
        cd flexric || { echo "Failed to enter flexric directory"; exit 1; }
        git fetch origin
        git checkout slicing-spring-of-code
        git pull origin slicing-spring-of-code || true
    else
        echo ">>> Removing empty directory and cloning..."
        rm -rf flexric
        git clone https://gitlab.eurecom.fr/mosaic5g/flexric
        cd flexric || { echo "Failed to enter flexric directory"; exit 1; }
        git checkout slicing-spring-of-code
    fi
else
    git clone https://gitlab.eurecom.fr/mosaic5g/flexric
    cd flexric || { echo "Failed to enter flexric directory"; exit 1; }
    git checkout slicing-spring-of-code
fi

# Step 4: Copy necessary files
echo ">>> Copying xApp control files..."
cp "$INITIAL_DIR/xapp_rc_slice_dynamic.c" examples/xApp/c/ctrl/ || { echo "Failed to copy xapp_rc_slice_dynamic.c"; exit 1; }
cp "$INITIAL_DIR/CMakeLists.txt" examples/xApp/c/ctrl/ || { echo "Failed to copy CMakeLists.txt"; exit 1; }

# Step 5: Build flexric
echo ">>> Building FlexRIC (this will take 5-10 minutes)..."
mkdir -p build && cd build || { echo "Failed to create/enter build directory"; exit 1; }
cmake -DXAPP_MULTILANGUAGE=OFF .. || { echo "FlexRIC cmake configuration failed"; exit 1; }
make -j8 || { echo "FlexRIC compilation failed"; exit 1; }
sudo make install || { echo "FlexRIC installation failed"; exit 1; }

echo ">>> All steps completed successfully!"
