#!/bin/bash
# Quick start script for PCRE2 fuzzing
# This script automates the entire build process

set -e  # Exit on error

echo "================================"
echo "PCRE2 Fuzzer - Quick Start"
echo "================================"
echo ""

# Check prerequisites
echo "[1/5] Checking prerequisites..."

if ! command -v cmake &> /dev/null; then
    echo "ERROR: cmake not found. Install with: brew install cmake"
    exit 1
fi

if [ ! -d "/usr/local/opt/llvm" ]; then
    echo "ERROR: LLVM not found. Install with: brew install llvm"
    exit 1
fi

if ! command -v xcrun &> /dev/null; then
    echo "ERROR: Xcode Command Line Tools not found. Install with: xcode-select --install"
    exit 1
fi

echo "✓ All prerequisites found"
echo ""

# Navigate to project root
cd "$(dirname "$0")"
PROJECT_ROOT=$(pwd)

echo "[2/5] Building PCRE2 library..."

# Clean and create build directory
rm -rf pcre2/build
mkdir -p pcre2/build
cd pcre2/build

# Configure and build PCRE2
cmake .. \
  -DPCRE2_BUILD_TESTS=OFF \
  -DPCRE2_BUILD_PCRE2GREP=OFF \
  -DPCRE2_SUPPORT_JIT=OFF \
  > /dev/null 2>&1

make -j$(sysctl -n hw.ncpu) > /dev/null 2>&1

if [ ! -f "libpcre2-8.a" ]; then
    echo "ERROR: Failed to build libpcre2-8.a"
    exit 1
fi

echo "✓ PCRE2 library built successfully ($(ls -lh libpcre2-8.a | awk '{print $5}'))"
echo ""

echo "[3/5] Building fuzzer binary..."

# Build the fuzzer
/usr/local/opt/llvm/bin/clang++ ../pcre2_fuzz.cc \
  -fsanitize=address,undefined,fuzzer \
  -isysroot /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk \
  -I./interface \
  -I../src \
  -fuse-ld=/usr/bin/ld \
  libpcre2-8.a \
  -o pcre2_fuzzer

if [ ! -f "pcre2_fuzzer" ]; then
    echo "ERROR: Failed to build pcre2_fuzzer"
    exit 1
fi

echo "✓ Fuzzer built successfully ($(ls -lh pcre2_fuzzer | awk '{print $5}'))"
echo ""

echo "[4/5] Setting up directories..."

# Create corpus directory
mkdir -p corpus
mkdir -p seeds

echo "✓ Created corpus/ and seeds/ directories"
echo ""

echo "[5/5] Running quick test..."

# Run a quick test
./pcre2_fuzzer corpus/ -runs=1000 -max_len=512 2>&1 | tail -5

echo ""
echo "================================"
echo "Build Complete!"
echo "================================"
echo ""
echo "Fuzzer location: pcre2/build/pcre2_fuzzer"
echo "Corpus directory: pcre2/build/corpus/"
echo ""
echo "To start fuzzing:"
echo "  cd pcre2/build"
echo "  ./pcre2_fuzzer corpus/ -max_len=2048 -timeout=5"
echo ""
echo "For more options, see SETUP_AND_RUN.md"
echo ""
