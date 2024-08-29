#!/bin/bash

ROOT_DIR=$(pwd)
INSTALL_DIR=$ROOT_DIR/riscv-llvm-18-install

# Unpack the Xuantie RVV 0.7.1 toolchain
cd utils
tar -xvf Xuantie-900-gcc-linux-6.6.0-glibc-x86_64-V2.10.1-20240712.tar.gz
cd ..

if [ -n "$1" ]; then
	INSTALL_DIR=$1
fi

INSTALL_CONFIG="--enable-linux --enable-llvm --with-arch=rv64gcv --with-abi=lp64d"

# Clone the RISC-V GNU toolchain repository
if [ ! -d "riscv-gnu-toolchain" ]; then
	git clone --recursive https://github.com/riscv-collab/riscv-gnu-toolchain.git
fi

# Create a directory for the RISC-V GNU toolchain installation
rm -rf $INSTALL_DIR
mkdir $INSTALL_DIR

# Navigate to the RISC-V GNU toolchain directory
cd riscv-gnu-toolchain

if [ -n "$2" ]; then
	git checkout $2
fi

# Export installation path to the PATH
export PATH="$INSTALL_DIR/bin:$PATH"

{
	time (
		# Clean the build directory
		make clean

		# Configure the installation
		./configure --prefix="$INSTALL_DIR" $INSTALL_CONFIG

		# Build
		make -j50 linux
	)
} | tee $INSTALL_DIR/build-riscv.log

# Navigate back to the root directory
cd $ROOT_DIR
