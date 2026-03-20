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
echo "High Coverage - Valid UTF-8 Only"
echo "========================================"
echo

# check fuzzer built
if [ ! -f "$BUILD_DIR/pcre2_fuzzer_match" ]; then
    echo -e "${YELLOW}Matching fuzzer not built. Building now...${NC}"
    echo

    if [ ! -f "$SCRIPT_DIR/pcre2/pcre2_fuzz_match.cc" ]; then
        echo -e "${RED}Error: pcre2_fuzz_match.cc not found!${NC}"
        exit 1
    fi

    cd "$BUILD_DIR"

    # Build the matching fuzzer
    echo "Building pcre2_fuzzer_match..."
    /usr/local/opt/llvm/bin/clang++ -fsanitize=fuzzer \
        -nostdinc++ -I/usr/local/opt/llvm/include/c++/v1 \
        -I./interface -L. -L/usr/local/opt/llvm/lib/c++ \
        -Wl,-rpath,/usr/local/opt/llvm/lib/c++ \
        -fuse-ld=/usr/bin/ld \
        -o pcre2_fuzzer_match ../pcre2_fuzz_match.cc -lpcre2-8

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Build successful!${NC}"
        echo
    else
        echo -e "${RED}Build failed!${NC}"
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
            echo "Matching Fuzzer - Focuses on regex matching engine with valid UTF-8"
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
            echo "Difference from run_fuzzer.sh:"
            echo "  - Uses PCRE2_UTF (no NO_UTF_CHECK)"
            echo "  - Higher coverage (explores matching engine)"
            echo "  - Finds different types of bugs"
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
echo -e "${BLUE}Note: This fuzzer uses valid UTF-8 only (high coverage mode)${NC}"
echo -e "${BLUE}For parsing bugs, use ./run_fuzzer.sh instead${NC}"
