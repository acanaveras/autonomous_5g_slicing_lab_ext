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

# Step 0: Install necessary compilers and base dependencies
echo ">>> Checking compilers..."
if ! gcc-12 --version &>/dev/null || ! g++-12 --version &>/dev/null; then
    echo ">>> Installing gcc-12, g++-12..."
    sudo apt update
    sudo apt install -y gcc-12 g++-12
    sudo apt install -y cmake ninja-build build-essential
    sudo update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-12 100
    sudo update-alternatives --install /usr/bin/g++ g++ /usr/bin/g++-12 100
else
    echo ">>> Compilers already installed"
fi

# Step 0.1: Install ASN1C manually (more reliable than OAI's build_oai -I)
if [ ! -f "/opt/asn1c/bin/asn1c" ]; then
    echo ">>> Installing ASN1C from source..."
    sudo apt-get update
    sudo apt-get install -y bison flex autoconf automake libtool

    # Clean any previous attempts
    sudo rm -rf /tmp/asn1c

    # Clone and build
    git clone https://github.com/mouse07410/asn1c /tmp/asn1c
    cd /tmp/asn1c
    git checkout vlm_master
    git log -n1

    autoreconf -iv
    ./configure --prefix=/opt/asn1c/
    make -j$(nproc)
    sudo make install
    sudo ldconfig

    cd "$INITIAL_DIR"

    # Verify installation
    if [ -f "/opt/asn1c/bin/asn1c" ]; then
        echo ">>> ASN1C installed successfully at /opt/asn1c/bin/asn1c"
    else
        echo "ERROR: ASN1C installation failed - binary not found"
        exit 1
    fi
else
    echo ">>> ASN1C already installed at /opt/asn1c/bin/asn1c"
fi

# Step 0.2: Install SIMDE headers
if [ ! -d "/usr/include/simde" ]; then
    echo ">>> Installing SIMDE headers..."
    sudo rm -rf /tmp/simde
    git clone https://github.com/simd-everywhere/simde-no-tests.git /tmp/simde
    cd /tmp/simde
    git checkout 389f360a66d4a3bec62b7d71ad8be877487809ba
    git log -n1
    sudo cp -rv /tmp/simde /usr/include/
    cd "$INITIAL_DIR"
    echo ">>> SIMDE headers installed"
else
    echo ">>> SIMDE headers already installed"
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
# Install remaining OAI dependencies (excluding ASN1C and SIMDE which we already installed)
echo ">>> Installing remaining OAI dependencies..."
./build_oai -I || echo "WARNING: Some OAI dependencies may have failed, but ASN1C/SIMDE are installed"

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
