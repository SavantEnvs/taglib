#!/usr/bin/env bash
# Builds (1) the sanitized fuzz harness + standalone reproducer, (2) taglib's CppUnit suite and the
# tagreader example with NORMAL flags for mayhem/test.sh. Build dirs live under build/ (gitignored).
set -euo pipefail

[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer}"
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${CC:=clang}" ; : "${CXX:=clang++}" ; : "${LIB_FUZZING_ENGINE:=-fsanitize=fuzzer}"
: "${MAYHEM_JOBS:=$(nproc)}"
: "${COVERAGE_FLAGS=}"
export SANITIZER_FLAGS DEBUG_FLAGS CC CXX LIB_FUZZING_ENGINE MAYHEM_JOBS COVERAGE_FLAGS

cd "$SRC"

# 1) Sanitized + SanCov-instrumented static library (-fuzzer-no-link so the fuzzed code has coverage).
FUZZ_FLAGS="$SANITIZER_FLAGS -fsanitize=fuzzer-no-link $DEBUG_FLAGS"
cmake -S . -B build/fuzz -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_C_COMPILER="$CC" -DCMAKE_CXX_COMPILER="$CXX" \
    -DCMAKE_C_FLAGS="$FUZZ_FLAGS" -DCMAKE_CXX_FLAGS="$FUZZ_FLAGS" \
    -DBUILD_TESTING=OFF -DBUILD_BINDINGS=OFF -DBUILD_EXAMPLES=OFF -DBUILD_SHARED_LIBS=OFF \
    -DENABLE_CCACHE=OFF -DVISIBILITY_HIDDEN=OFF
cmake --build build/fuzz -j"$MAYHEM_JOBS" --target tag

# 2) Harness (upstream's own, unmodified): fuzzer binary + standalone reproducer, LSan off.
$CXX $SANITIZER_FLAGS $DEBUG_FLAGS -c mayhem/lsan_off.cc -o build/fuzz/lsan_off.o
$CC $SANITIZER_FLAGS $DEBUG_FLAGS -x c -c "$STANDALONE_FUZZ_MAIN" -o build/fuzz/standalone_main.o
HARNESS=tests/fuzzing/taglib_fileref_fuzzer.cpp
INC="-I taglib -I taglib/toolkit -I build/fuzz"
$CXX -std=c++17 $SANITIZER_FLAGS $DEBUG_FLAGS $LIB_FUZZING_ENGINE $INC "$HARNESS" \
    build/fuzz/lsan_off.o build/fuzz/taglib/libtag.a -lz -o /mayhem/taglib_fileref_fuzzer
$CXX -std=c++17 $SANITIZER_FLAGS $DEBUG_FLAGS $INC "$HARNESS" \
    build/fuzz/standalone_main.o build/fuzz/lsan_off.o build/fuzz/taglib/libtag.a -lz \
    -o /mayhem/taglib_fileref_fuzzer-standalone

# 3) Functional suite with the project's NORMAL flags.
cmake -S . -B build/test -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_C_COMPILER="$CC" -DCMAKE_CXX_COMPILER="$CXX" \
    -DCMAKE_C_FLAGS="$COVERAGE_FLAGS" -DCMAKE_CXX_FLAGS="$COVERAGE_FLAGS" \
    -DBUILD_TESTING=ON -DBUILD_BINDINGS=ON -DBUILD_EXAMPLES=ON -DBUILD_SHARED_LIBS=OFF \
    -DENABLE_CCACHE=OFF -DVISIBILITY_HIDDEN=OFF
cmake --build build/test -j"$MAYHEM_JOBS"
