#!/bin/bash
# PCRE2 Fuzzer Runner
# This script sets up and runs the PCRE2 fuzzer with recommended settings

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/pcre2/build"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "========================================"
echo "PCRE2 Fuzzer Runner"
echo "========================================"
echo

# Check if fuzzer is built
if [ ! -f "$BUILD_DIR/pcre2_fuzzer" ]; then
    echo -e "${RED}Error: Fuzzer not built!${NC}"
    echo "Please build the fuzzer first:"
    echo "  cd pcre2/build"
    echo "  /usr/local/opt/llvm/bin/clang++ -fsanitize=fuzzer -nostdinc++ \\"
    echo "    -I/usr/local/opt/llvm/include/c++/v1 -I./interface \\"
    echo "    -L. -L/usr/local/opt/llvm/lib/c++ \\"
    echo "    -Wl,-rpath,/usr/local/opt/llvm/lib/c++ \\"
    echo "    -fuse-ld=/usr/bin/ld -o pcre2_fuzzer ../pcre2_fuzz.cc -lpcre2-8"
    exit 1
fi

cd "$BUILD_DIR"

# Create directories
mkdir -p corpus seeds crashes_found

# Generate seeds if they don't exist
if [ ! -d "seeds" ] || [ -z "$(ls -A seeds 2>/dev/null)" ]; then
    echo -e "${YELLOW}Generating seeds...${NC}"
    python3 "$SCRIPT_DIR/generate_seeds.py"
    echo -e "${GREEN}Seeds generated!${NC}"
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
            echo "  $0 --ignore-crashes --jobs 8        # Use 8 parallel workers"
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
echo "  Mode: $MODE"
echo "  Time: ${TIME}s"
echo "  Jobs: $JOBS"
echo "  Corpus: $(ls corpus 2>/dev/null | wc -l | tr -d ' ') files"
echo "  Seeds: $(ls seeds 2>/dev/null | wc -l | tr -d ' ') files"
echo

# Run fuzzer based on mode
if [ "$MODE" = "ignore-crashes" ]; then
    echo -e "${YELLOW}Running in ignore-crashes mode (will find multiple bugs)${NC}"
    echo "Press Ctrl+C to stop"
    echo
    ./pcre2_fuzzer corpus/ seeds/ \
        -fork=$JOBS \
        -ignore_crashes=1 \
        -max_total_time=$TIME \
        -print_final_stats=1
else
    echo -e "${YELLOW}Running in standard mode (stops on first crash)${NC}"
    echo "Press Ctrl+C to stop"
    echo
    ./pcre2_fuzzer corpus/ seeds/ \
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
    echo "  ./pcre2_fuzzer crash-<hash>"
    echo
    echo "Backing up crashes..."
    cp crash-* crashes_found/ 2>/dev/null || true
    echo -e "${GREEN}Crashes saved to crashes_found/${NC}"
else
    echo "No crashes found."
fi

echo
echo "Corpus now has $(ls corpus 2>/dev/null | wc -l | tr -d ' ') files"
