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

# =============================================================================
# Build script for RIC and OAI Network Elements
# 
# This script builds OpenAirInterface5G and FlexRIC for the Autonomous 5G 
# Slicing Lab. It includes a fix for the asn1c compiler issue where recent
# versions of mouse07410/asn1c have a bug that doesn't properly convert
# hyphens to underscores in ASN.1 enum identifiers (e.g., E1AP's 
# "discard-pdpc-SN" becomes invalid C code).
#
# The fix uses velichkov/asn1c (s1ap branch) which has both:
#   - APER (Aligned PER) encoding support required by OAI
#   - Proper hyphen-to-underscore conversion for enum identifiers
# =============================================================================

set -e  # Exit immediately if any command fails

# Save the initial directory
INITIAL_DIR=$(pwd)

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

log_error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] ⚠️  $1${NC}"
}

# =============================================================================
# Step 0: Install necessary compilers and build tools
# =============================================================================
log "Step 0: Installing build dependencies (gcc-12, g++-12, autotools)..."
sudo apt update
sudo apt install -y gcc-12 g++-12 autoconf automake libtool bison flex

# Set gcc-12 and g++-12 as default compilers
sudo update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-12 100
sudo update-alternatives --install /usr/bin/g++ g++ /usr/bin/g++-12 100

log_success "Build dependencies installed"

# Go back to initial directory
cd "$INITIAL_DIR" || { log_error "Failed to return to initial directory"; exit 1; }

# =============================================================================
# Step 1: Clone OpenAirInterface5G
# =============================================================================
log "Step 1: Cloning OpenAirInterface5G..."

if [ -d "openairinterface5g" ]; then
    log_warning "openairinterface5g directory already exists, removing..."
    rm -rf openairinterface5g
fi

git clone https://gitlab.eurecom.fr/oai/openairinterface5g
cd openairinterface5g || { log_error "Failed to enter openairinterface5g directory"; exit 1; }
git checkout slicing-spring-of-code
log_success "OpenAirInterface5G cloned and checked out to slicing-spring-of-code branch"

cd cmake_targets || { log_error "Failed to enter cmake_targets"; exit 1; }

# =============================================================================
# Step 2: Install OAI dependencies (this installs the BUGGY asn1c)
# =============================================================================
log "Step 2: Installing OAI dependencies via build_oai -I..."
log_warning "This will install mouse07410/asn1c which has a known bug - we will fix it next"

./build_oai -I || log_warning "Some dependencies may have failed, but continuing..."

log_success "OAI dependencies installed"

# =============================================================================
# Step 3: CRITICAL FIX - Replace buggy asn1c with velichkov's fork
# =============================================================================
log "Step 3: Replacing buggy asn1c with velichkov/asn1c (s1ap branch)..."
log "This fixes the hyphen-to-underscore bug in E1AP enum identifiers"

# Remove the buggy asn1c installed by build_oai -I
sudo rm -rf /opt/asn1c
sudo rm -rf /tmp/asn1c

# Clone velichkov's fork which has:
# - APER support (required by OAI for 3GPP protocol encoding)
# - Proper hyphen-to-underscore conversion for enum identifiers
# - Fixes for S1AP, X2AP, NGAP, and E1AP protocol compilation
git clone https://github.com/velichkov/asn1c.git /tmp/asn1c
cd /tmp/asn1c
git checkout s1ap

log "Building asn1c from velichkov/asn1c (s1ap branch)..."
autoreconf -iv
./configure --prefix=/opt/asn1c
make -j$(nproc)
sudo make install
sudo ldconfig

# Verify installation
if [ -f "/opt/asn1c/bin/asn1c" ]; then
    log_success "asn1c installed successfully at /opt/asn1c/bin/asn1c"
    # Show version info
    log "asn1c version info:"
    /opt/asn1c/bin/asn1c -h 2>&1 | head -5 || true
else
    log_error "asn1c installation failed!"
    exit 1
fi

# Return to OAI cmake_targets directory
cd "$INITIAL_DIR/openairinterface5g/cmake_targets" || { log_error "Failed to return to cmake_targets"; exit 1; }

# =============================================================================
# Step 4: Build OpenAirInterface5G with the fixed asn1c
# =============================================================================
log "Step 4: Building OpenAirInterface5G (gNB, nrUE, E2 agent)..."
log "This may take 30-60 minutes depending on your system..."

./build_oai -c -C -w SIMU --gNB --nrUE --build-e2 --ninja --cmake-opt -DASN1C_EXEC=/opt/asn1c/bin/asn1c

# Verify OAI build
if [ -f "$INITIAL_DIR/openairinterface5g/cmake_targets/ran_build/build/nr-softmodem" ]; then
    log_success "OpenAirInterface5G built successfully!"
else
    log_error "OpenAirInterface5G build failed - nr-softmodem not found"
    exit 1
fi

# =============================================================================
# Step 5: Return to initial directory and clone FlexRIC
# =============================================================================
cd "$INITIAL_DIR" || { log_error "Failed to return to initial directory"; exit 1; }

log "Step 5: Cloning FlexRIC..."

if [ -d "flexric" ]; then
    log_warning "flexric directory already exists, removing..."
    rm -rf flexric
fi

git clone https://gitlab.eurecom.fr/mosaic5g/flexric
cd flexric || { log_error "Failed to enter flexric directory"; exit 1; }
git checkout slicing-spring-of-code
log_success "FlexRIC cloned and checked out to slicing-spring-of-code branch"

# =============================================================================
# Step 6: Copy custom xApp files
# =============================================================================
log "Step 6: Copying custom xApp files..."

if [ -f "$INITIAL_DIR/xapp_rc_slice_dynamic.c" ]; then
    cp "$INITIAL_DIR/xapp_rc_slice_dynamic.c" examples/xApp/c/ctrl/ || { log_error "Failed to copy xapp_rc_slice_dynamic.c"; exit 1; }
    log_success "Copied xapp_rc_slice_dynamic.c"
else
    log_warning "xapp_rc_slice_dynamic.c not found in $INITIAL_DIR"
fi

if [ -f "$INITIAL_DIR/CMakeLists.txt" ]; then
    cp "$INITIAL_DIR/CMakeLists.txt" examples/xApp/c/ctrl/ || { log_error "Failed to copy CMakeLists.txt"; exit 1; }
    log_success "Copied CMakeLists.txt"
else
    log_warning "CMakeLists.txt not found in $INITIAL_DIR"
fi

# =============================================================================
# Step 7: Build FlexRIC
# =============================================================================
log "Step 7: Building FlexRIC..."

mkdir -p build && cd build
cmake -DXAPP_MULTILANGUAGE=OFF ..
make -j$(nproc)
sudo make install

# Verify FlexRIC build
if [ -f "$INITIAL_DIR/flexric/build/examples/ric/nearRT-RIC" ]; then
    log_success "FlexRIC built successfully!"
else
    log_error "FlexRIC build failed - nearRT-RIC not found"
    exit 1
fi

# =============================================================================
# Done!
# =============================================================================
cd "$INITIAL_DIR"

echo ""
echo "========================================"
log_success "All steps completed successfully!"
echo "========================================"
echo ""
echo "Built components:"
echo "  - OpenAirInterface5G (gNB + nrUE with E2 agent)"
echo "  - FlexRIC (nearRT-RIC)"
echo ""
echo "Key files:"
echo "  - nr-softmodem: $INITIAL_DIR/openairinterface5g/cmake_targets/ran_build/build/nr-softmodem"
echo "  - nearRT-RIC:   $INITIAL_DIR/flexric/build/examples/ric/nearRT-RIC"
echo ""
echo "asn1c fix applied:"
echo "  - Replaced buggy mouse07410/asn1c with velichkov/asn1c (s1ap branch)"
echo "  - This fixes E1AP enum identifier compilation errors"
echo ""
echo "You can now run: cd docker && ./lab_start.sh"
echo ""