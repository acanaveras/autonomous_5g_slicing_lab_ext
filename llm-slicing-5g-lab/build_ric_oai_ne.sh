#!/bin/bash
# ... (keep your header/license)

set -e
INITIAL_DIR=$(pwd)

# Step 0: Install necessary compilers and build tools
echo ">>> Updating apt and installing build dependencies..."
sudo apt update
sudo apt install -y gcc-12 g++-12 autoconf automake libtool bison flex
sudo update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-12 100
sudo update-alternatives --install /usr/bin/g++ g++ /usr/bin/g++-12 100

cd "$INITIAL_DIR" || { echo "Failed to return to initial directory"; exit 1; }

# Step 1: Clone openairinterface5g
echo ">>> Cloning openairinterface5g..."
git clone https://gitlab.eurecom.fr/oai/openairinterface5g
cd openairinterface5g || { echo "Failed to enter openairinterface5g directory"; exit 1; }
git checkout slicing-spring-of-code
cd cmake_targets || { echo "Failed to enter cmake_targets"; exit 1; }

# Step 2: Install OAI dependencies (this installs the BUGGY asn1c)
echo ">>> Installing OAI dependencies..."
./build_oai -I || echo "WARNING: Some dependencies may have failed, but continuing..."

# Step 3: REPLACE buggy asn1c with fixed version
echo ">>> Replacing buggy asn1c with hyphen-fix version..."
sudo rm -rf /opt/asn1c
sudo rm -rf /tmp/asn1c

# Use OAI's own fork which has the fixes for their ASN.1 files
git clone https://gitlab.eurecom.fr/oai/asn1c.git /tmp/asn1c
cd /tmp/asn1c
git checkout velichkov_s1ap_plus_option_group  # Branch with protocol-specific fixes
autoreconf -iv
./configure --prefix=/opt/asn1c
make -j$(nproc)
sudo make install
sudo ldconfig

cd "$INITIAL_DIR/openairinterface5g/cmake_targets" || exit 1

# Step 4: Build OAI with the FIXED asn1c
echo ">>> Building OAI..."
./build_oai -c -C -w SIMU --gNB --nrUE --build-e2 --ninja --cmake-opt -DASN1C_EXEC=/opt/asn1c/bin/asn1c

# Step 5: Go back and build flexric
cd "$INITIAL_DIR" || { echo "Failed to return to initial directory"; exit 1; }

echo ">>> Cloning and building flexric..."
git clone https://gitlab.eurecom.fr/mosaic5g/flexric
cd flexric || { echo "Failed to enter flexric directory"; exit 1; }
git checkout slicing-spring-of-code    

cp "$INITIAL_DIR/xapp_rc_slice_dynamic.c" examples/xApp/c/ctrl/ || { echo "Failed to copy xapp_rc_slice_dynamic.c"; exit 1; }
cp "$INITIAL_DIR/CMakeLists.txt" examples/xApp/c/ctrl/ || { echo "Failed to copy CMakeLists.txt"; exit 1; }

mkdir -p build && cd build
cmake -DXAPP_MULTILANGUAGE=OFF ..
make -j8
sudo make install

echo ">>> All steps completed successfully!"