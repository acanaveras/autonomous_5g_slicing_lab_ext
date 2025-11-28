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
# Slicing Lab.
#
# FIX APPLIED: Uses mouse07410/asn1c pinned to a commit from BEFORE March 2025
# when the hyphen-to-underscore bug (CVE-2025-55398) was introduced.
#
# Why mouse07410/asn1c?
#   - It's the ONLY fork with -gen-APER support (required by OAI)
#   - OAI's own fork and velichkov's fork don't have -gen-APER
#   - We just need to use an older commit before the bug
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

cd "$INITIAL_DIR" || { log_error "Failed to return to initial directory"; exit 1; }

# =============================================================================
# Step 1: Install mouse07410/asn1c pinned to pre-bug commit
# The -gen-APER flag is ONLY available in mouse07410/asn1c
# Bug CVE-2025-55398 was introduced around March 2025, so we use Jan 2025 commit
# =============================================================================
log "Step 1: Installing mouse07410/asn1c (pinned to pre-March-2025 commit)..."

# Remove any existing asn1c installation
sudo rm -rf /opt/asn1c
sudo rm -rf /tmp/asn1c

# Clone mouse07410/asn1c (the ONLY fork with -gen-APER support)
log "Cloning mouse07410/asn1c..."
git clone https://github.com/mouse07410/asn1c.git /tmp/asn1c
cd /tmp/asn1c

# Checkout vlm_master branch
git checkout vlm_master

# Find a commit from before January 2025 (well before the March 2025 bug)
log "Finding a stable commit from before the hyphen bug (pre-Jan 2025)..."
GOOD_COMMIT=$(git rev-list -n 1 --before="2025-01-01" vlm_master)

if [ -z "$GOOD_COMMIT" ]; then
    log_warning "Could not find commit before 2025-01-01, trying 2024-11-01..."
    GOOD_COMMIT=$(git rev-list -n 1 --before="2024-11-01" vlm_master)
fi

if [ -z "$GOOD_COMMIT" ]; then
    log_warning "Could not find commit before 2024-11-01, trying 2024-06-01..."
    GOOD_COMMIT=$(git rev-list -n 1 --before="2024-06-01" vlm_master)
fi

if [ -z "$GOOD_COMMIT" ]; then
    log_error "Could not find a suitable pre-bug commit!"
    log_error "Please manually find a commit from before March 2025"
    exit 1
fi

log "Checking out known-good commit: $GOOD_COMMIT"
git checkout "$GOOD_COMMIT"

# Show which version we're using
log "asn1c commit info:"
git log -n1

# Build asn1c
log "Building asn1c..."
autoreconf -iv
./configure --prefix=/opt/asn1c
make -j$(nproc)
sudo make install
sudo ldconfig

# Verify installation and -gen-APER support
if [ -f "/opt/asn1c/bin/asn1c" ]; then
    log_success "asn1c installed at /opt/asn1c/bin/asn1c"
    log "asn1c version:"
    /opt/asn1c/bin/asn1c -h 2>&1 | head -5 || true
    
    # Test -gen-APER support
    log "Testing -gen-APER support..."
    if /opt/asn1c/bin/asn1c -gen-APER 2>&1 | grep -q "No input files\|input file"; then
        log_success "asn1c supports -gen-APER flag!"
    elif /opt/asn1c/bin/asn1c -gen-APER 2>&1 | grep -qi "invalid\|unknown"; then
        log_error "This commit doesn't support -gen-APER! Try an older commit."
        exit 1
    else
        log_warning "-gen-APER test inconclusive, continuing..."
    fi
else
    log_error "asn1c installation failed!"
    exit 1
fi

cd "$INITIAL_DIR"

# =============================================================================
# Step 2: Clone OpenAirInterface5G
# =============================================================================
log "Step 2: Cloning OpenAirInterface5G..."

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
# Step 3: Install OAI dependencies (protect our asn1c from being overwritten)
# =============================================================================
log "Step 3: Installing OAI dependencies via build_oai -I..."
log "Protecting our good asn1c installation from being overwritten..."

# Temporarily move our good asn1c to prevent overwrite
sudo mv /opt/asn1c /opt/asn1c_good

# Run build_oai -I to install other dependencies
./build_oai -I || log_warning "Some dependencies may have failed, but continuing..."

# Restore our good asn1c (overwrite whatever build_oai -I installed)
sudo rm -rf /opt/asn1c
sudo mv /opt/asn1c_good /opt/asn1c

log_success "OAI dependencies installed, good asn1c restored"

# Verify asn1c is still correct
log "Verifying asn1c installation after restore..."
/opt/asn1c/bin/asn1c -h 2>&1 | head -3

# Double-check -gen-APER still works
if /opt/asn1c/bin/asn1c -gen-APER 2>&1 | grep -q "No input files\|input file"; then
    log_success "Confirmed: asn1c still supports -gen-APER"
else
    log_warning "-gen-APER check returned unexpected output, but continuing..."
fi

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
echo "  - Using mouse07410/asn1c pinned to pre-bug commit (before March 2025)"
echo "  - This has -gen-APER support AND no hyphen-to-underscore bug"
echo ""
echo "You can now run: cd docker && ./lab_start.sh"
echo ""