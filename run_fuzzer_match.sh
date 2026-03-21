#!/bin/bash
# PCRE2 Matching Fuzzer Runner (High Coverage Version)
# This fuzzer focuses on the matching engine with valid UTF-8 patterns

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/pcre2/build"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo "========================================"
echo "PCRE2 Matching Fuzzer Runner"
echo "High Coverage - Full Instrumentation"
echo "========================================"
echo

# Check prerequisites
if [ ! -d "/usr/local/opt/llvm" ]; then
    echo -e "${RED}Error: LLVM not found. Install with: brew install llvm${NC}"
    exit 1
fi

if ! command -v cmake &> /dev/null; then
    echo -e "${RED}Error: cmake not found. Install with: brew install cmake${NC}"
    exit 1
fi

# Check if we need to rebuild with instrumentation
NEEDS_REBUILD=0
NEEDS_FUZZER_REBUILD=0

if [ ! -f "$BUILD_DIR/libpcre2-8.a" ]; then
    NEEDS_REBUILD=1
else
    # Check if library is instrumented (instrumented version is much larger, ~12MB vs ~1MB)
    LIB_SIZE=$(stat -f%z "$BUILD_DIR/libpcre2-8.a" 2>/dev/null || echo "0")
    if [ "$LIB_SIZE" -lt 5000000 ]; then
        echo -e "${YELLOW}Library not instrumented (size: $(($LIB_SIZE / 1024))KB). Rebuilding...${NC}"
        NEEDS_REBUILD=1
    fi
fi

# Check if fuzzer needs rebuild (even if library is fine)
if [ ! -f "$BUILD_DIR/pcre2_fuzzer_match" ]; then
    NEEDS_FUZZER_REBUILD=1
else
    # Check if fuzzer is built with sanitizers (should be several MB, not < 1MB)
    FUZZER_SIZE=$(stat -f%z "$BUILD_DIR/pcre2_fuzzer_match" 2>/dev/null || echo "0")
    if [ "$FUZZER_SIZE" -lt 3000000 ]; then
        echo -e "${YELLOW}Fuzzer not built with sanitizers (size: $(($FUZZER_SIZE / 1024))KB). Rebuilding...${NC}"
        NEEDS_FUZZER_REBUILD=1
    fi
fi

if [ "$NEEDS_REBUILD" -eq 1 ]; then
    echo -e "${YELLOW}Building PCRE2 with full instrumentation...${NC}"
    echo "This may take a few minutes..."
    echo

    cd "$BUILD_DIR"

    # Clean previous build
    echo "Cleaning previous build..."
    rm -rf CMakeFiles CMakeCache.txt cmake_install.cmake Makefile *.a *.pc* pcre2-config src/ interface/ cmake/

    # Configure PCRE2 with instrumentation
    echo "Configuring PCRE2..."
    cmake .. \
      -DCMAKE_C_COMPILER=/usr/local/opt/llvm/bin/clang \
      -DCMAKE_C_FLAGS="-fsanitize=fuzzer-no-link,address,undefined" \
      -DCMAKE_CXX_COMPILER=/usr/local/opt/llvm/bin/clang++ \
      -DCMAKE_CXX_FLAGS="-fsanitize=fuzzer-no-link,address,undefined" \
      -DCMAKE_EXE_LINKER_FLAGS="-fuse-ld=/usr/bin/ld" \
      -DCMAKE_SHARED_LINKER_FLAGS="-fuse-ld=/usr/bin/ld" \
      -DPCRE2_BUILD_TESTS=OFF \
      -DPCRE2_BUILD_PCRE2GREP=OFF \
      -DPCRE2_SUPPORT_JIT=OFF > /dev/null 2>&1

    if [ $? -ne 0 ]; then
        echo -e "${RED}CMake configuration failed!${NC}"
        exit 1
    fi

    # Build library
    echo "Building PCRE2 library..."
    make -j4 > /dev/null 2>&1

    if [ ! -f "libpcre2-8.a" ]; then
        echo -e "${RED}Library build failed!${NC}"
        exit 1
    fi

    LIB_SIZE=$(stat -f%z libpcre2-8.a)
    echo -e "${GREEN}✓ PCRE2 library built with instrumentation ($(($LIB_SIZE / 1024 / 1024))MB)${NC}"
    echo

    # Force fuzzer rebuild since library was rebuilt
    NEEDS_FUZZER_REBUILD=1
fi

if [ "$NEEDS_FUZZER_REBUILD" -eq 1 ]; then
    cd "$BUILD_DIR"

    # Build fuzzer
    echo "Building matching fuzzer binary..."
    /usr/local/opt/llvm/bin/clang++ -fsanitize=fuzzer,address,undefined \
      -nostdinc++ -I/usr/local/opt/llvm/include/c++/v1 \
      -I./interface -L. -L/usr/local/opt/llvm/lib/c++ \
      -Wl,-rpath,/usr/local/opt/llvm/lib/c++ \
      -fuse-ld=/usr/bin/ld \
      -o pcre2_fuzzer_match ../pcre2_fuzz_match.cc -lpcre2-8

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ Matching fuzzer built successfully!${NC}"
        echo
    else
        echo -e "${RED}Fuzzer build failed!${NC}"
        exit 1
    fi
fi

cd "$BUILD_DIR"

# Create directories
mkdir -p corpus_match seeds_match crashes_found_match

# Generate seeds if they don't exist
if [ ! -d "seeds_match" ] || [ -z "$(ls -A seeds_match 2>/dev/null)" ]; then
    echo -e "${YELLOW}Generating seeds for matching fuzzer...${NC}"
    # Create seeds_match directory
    mkdir -p seeds_match
    # Copy seeds from main fuzzer if they exist
    if [ -d "seeds" ] && [ "$(ls -A seeds 2>/dev/null)" ]; then
        cp seeds/* seeds_match/ 2>/dev/null
        echo -e "${GREEN}Copied $(ls seeds_match | wc -l | tr -d ' ') seeds from main fuzzer!${NC}"
    else
        # Generate new seeds in seeds_match
        cd "$SCRIPT_DIR"
        python3 -c "
import os
seeds_dir = 'pcre2/build/seeds_match'
os.makedirs(seeds_dir, exist_ok=True)
verbs = [b'(*ACCEPT)', b'(*FAIL)', b'(*COMMIT)', b'(*SKIP)', b'(*PRUNE)', b'(*THEN)']
for verb in verbs:
    verb_name = verb.decode().strip('(*)').lower()
    for depth in [1,5,10,25,40,50]:
        pattern = b'(' * depth + verb + b')' * depth
        len_bytes = len(pattern).to_bytes(2, 'little')
        with open(os.path.join(seeds_dir, f'{verb_name}_{depth}'), 'wb') as f:
            f.write(len_bytes + pattern + b'test')
for count in [50, 150, 300, 500, 1000]:
    pattern = b'(a)' * count
    len_bytes = len(pattern).to_bytes(2, 'little')
    with open(os.path.join(seeds_dir, f'groups_{count}'), 'wb') as f:
        f.write(len_bytes + pattern + b'a' * min(count, 200))
print('Seeds generated!')
"
        cd "$BUILD_DIR"
        echo -e "${GREEN}Generated $(ls seeds_match | wc -l | tr -d ' ') seeds!${NC}"
    fi
fi

# Parse command line arguments
MODE="standard"
TIME=3600  # Default: 1 hour
JOBS=4

while [[ $# -gt 0 ]]; do
    case $1 in
        --ignore-crashes)
            MODE="ignore-crashes"
            shift
            ;;
        --time)
            TIME="$2"
            shift 2
            ;;
        --jobs)
            JOBS="$2"
            shift 2
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo
            echo "Matching Fuzzer - High coverage with full instrumentation"
            echo
            echo "Options:"
            echo "  --ignore-crashes    Continue fuzzing after crashes (find multiple bugs)"
            echo "  --time SECONDS      Run for specified seconds (default: 3600)"
            echo "  --jobs NUM          Number of parallel workers (default: 4)"
            echo "  --help              Show this help message"
            echo
            echo "Examples:"
            echo "  $0                                  # Standard run (stops on first crash)"
            echo "  $0 --time 7200                      # Run for 2 hours"
            echo "  $0 --ignore-crashes --time 3600     # Find multiple bugs in 1 hour"
            echo
            echo "Difference from run_fuzzer_full.sh:"
            echo "  - Removes PCRE2_UTF flag (no UTF validation)"
            echo "  - Explores non-UTF code paths"
            echo "  - Both use full instrumentation (60K+ edges)"
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            echo "Run '$0 --help' for usage information"
            exit 1
            ;;
    esac
done

echo -e "${GREEN}Configuration:${NC}"
echo "  Fuzzer: Matching (high coverage)"
echo "  Mode: $MODE"
echo "  Time: ${TIME}s"
echo "  Jobs: $JOBS"
echo "  Corpus: $(ls corpus_match 2>/dev/null | wc -l | tr -d ' ') files"
echo "  Seeds: $(ls seeds_match 2>/dev/null | wc -l | tr -d ' ') files"
echo

# Run fuzzer based on mode
if [ "$MODE" = "ignore-crashes" ]; then
    echo -e "${YELLOW}Running in ignore-crashes mode (will find multiple bugs)${NC}"
    echo "Press Ctrl+C to stop"
    echo
    ./pcre2_fuzzer_match corpus_match/ seeds_match/ \
        -fork=$JOBS \
        -ignore_crashes=1 \
        -max_total_time=$TIME \
        -print_final_stats=1
else
    echo -e "${YELLOW}Running in standard mode (stops on first crash)${NC}"
    echo "Press Ctrl+C to stop"
    echo
    ./pcre2_fuzzer_match corpus_match/ seeds_match/ \
        -max_total_time=$TIME \
        -max_len=4096 \
        -timeout=10 \
        -print_final_stats=1
fi

# Check results
echo
echo "========================================"
echo "Fuzzing Complete!"
echo "========================================"

CRASH_COUNT=$(ls crash-* 2>/dev/null | wc -l | tr -d ' ')
if [ "$CRASH_COUNT" -gt 0 ]; then
    echo -e "${GREEN}Found $CRASH_COUNT crash file(s)!${NC}"
    echo
    echo "Crash files:"
    ls -lh crash-* 2>/dev/null
    echo
    echo "To analyze crashes:"
    echo "  python3 $SCRIPT_DIR/decode_crash.py crash-<hash>"
    echo
    echo "To reproduce a crash:"
    echo "  ./pcre2_fuzzer_match crash-<hash>"
    echo
    echo "Backing up crashes..."
    cp crash-* crashes_found_match/ 2>/dev/null || true
    echo -e "${GREEN}Crashes saved to crashes_found_match/${NC}"
else
    echo "No crashes found."
fi

echo
echo "Corpus now has $(ls corpus_match 2>/dev/null | wc -l | tr -d ' ') files"
echo
echo -e "${BLUE}Note: This fuzzer uses full instrumentation (60K+ coverage edges)${NC}"
echo -e "${BLUE}PCRE2_UTF flag removed - explores non-UTF code paths${NC}"
echo -e "${BLUE}For parsing bugs with UTF validation, use ./run_fuzzer_full.sh${NC}"
