#!/bin/bash

ROOT_DIR=$(pwd)

#==========================
# Build Xuantie GCC 10.4
#==========================
XUANTIE_GCC_INSTALL_DIR=$ROOT_DIR/xuantie-gnu-install
XUANTIE_GCC_INSTALL_CONFIG="--enable-linux --with-arch=rv64gcv --with-abi=lp64d"

# Clone the Xuantie GNU toolchain repository
git clone --recursive https://github.com/XUANTIE-RV/xuantie-gnu-toolchain.git

# Create a directory for the Xuantie GNU toolchain installation
rm -rf $CLANG_INSTALL_DIR
mkdir $CLANG_INSTALL_DIR

# Navigate to the Xuantie GNU toolchain directory
cd xuantie-gnu-toolchain

# Checkout the 2.8.1 release
git checkout V2.8.1

# Build the Xuantie GNU toolchain
{
	make clean
	./configure --prefix=$XUANTIE_GCC_INSTALL_DIR $XUANTIE_GCC_INSTALL_CONFIG
	make -j50 linux
} | tee $XUANTIE_GCC_INSTALL_DIR/build-gcc.log

# Navigate back to the root directory
cd $ROOT_DIR

#==========================
# Build Xuantie GCC 10.4
#==========================
CLANG_INSTALL_DIR=$ROOT_DIR/riscv-llvm-18-install
CLANG_INSTALL_CONFIG="--enable-linux --enable-llvm --with-arch=rv64gcv --with-abi=lp64d"

# Clone the RISC-V GNU toolchain repository
if [ ! -d "riscv-gnu-toolchain" ]; then
	git clone --recursive https://github.com/riscv-collab/riscv-gnu-toolchain.git
fi

# Create a directory for the RISC-V GNU toolchain installation
rm -rf $CLANG_INSTALL_DIR
mkdir $CLANG_INSTALL_DIR

# Navigate to the RISC-V GNU toolchain directory
cd riscv-gnu-toolchain

# Checkout the 2024.08.28 release
git checkout 2024.08.28

# Export installation path to the PATH
export PATH="$CLANG_INSTALL_DIR/bin:$PATH"

# Build the RISC-V GNU toolchain
{
	make clean
	./configure --prefix=$CLANG_INSTALL_DIR $CLANG_INSTALL_CONFIG
	make -j50 linux
} | tee $CLANG_INSTALL_DIR/build-riscv.log

# Navigate back to the root directory
cd $ROOT_DIR
