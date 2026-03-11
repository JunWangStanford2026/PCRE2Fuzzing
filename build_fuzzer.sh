cd pcre2/build

export LLVM_BIN="$(brew --prefix llvm)/bin"
export CC="$LLVM_BIN/clang"
export CXX="$LLVM_BIN/clang++"

clang++ ../pcre2_fuzz.cc \
  -fsanitize=address,undefined,fuzzer \
  -I./interface \
  -I../src \
  libpcre2-8.a \
  -o pcre2_fuzzer