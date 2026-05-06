#!/bin/bash -eu
#
# Copyright 2019 Google Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
################################################################################

MBEDTLS_BUILD=$WORK/mbedtls
EXPAT_BUILD=$WORK/expat
S2OPC_BUILD=$WORK/s2opc
SAMPLES=$SRC/S2OPC-fuzzing-data

# Build the dependencies

## Configure mbedtls to disable support of the AES-NI instructions, known to cause error with some sanitizers
tar xzf $SRC/mbedtls.tgz -C $WORK
sed 's,#define MBEDTLS_AESNI_C,//#define MBEDTLS_AESNI_C,' -i $WORK/mbedtls-2.*/include/mbedtls/config.h

mkdir -p $MBEDTLS_BUILD
cd $MBEDTLS_BUILD
# Save and clear sanitizer flags for mbedtls to avoid -Werror issues with unused variables
SAVED_CFLAGS="${CFLAGS:-}"
SAVED_CXXFLAGS="${CXXFLAGS:-}"
export CFLAGS="${CFLAGS:-} -Wno-unused-but-set-variable -Wno-unterminated-string-initialization"
export CXXFLAGS="${CXXFLAGS:-} -Wno-unused-but-set-variable -Wno-unterminated-string-initialization"
cmake -DPYTHON_EXECUTABLE="/usr/bin/python3" \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
      -DCMAKE_C_FLAGS="-Wno-error -Wno-unused-but-set-variable -Wno-unterminated-string-initialization" \
      -DMBEDTLS_FATAL_WARNINGS=OFF \
      -DENABLE_TESTING=OFF \
      -DENABLE_PROGRAMS=OFF \
      $WORK/mbedtls-2.*
make -j$(nproc)
make -j$(nproc) install
export CFLAGS="$SAVED_CFLAGS"
export CXXFLAGS="$SAVED_CXXFLAGS"

## libcheck
tar xzf $SRC/check.tgz -C $WORK
cd $WORK/check-0.*
cmake -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_POSITION_INDEPENDENT_CODE=1 \
      $WORK/check-0.*
make -j$(nproc)
make -j$(nproc) install

## expat
tar xzf $SRC/expat.tgz -C $WORK
mkdir -p $EXPAT_BUILD
cd $EXPAT_BUILD
cmake -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
      -DEXPAT_SHARED_LIBS=OFF \
      $WORK/expat-2.*
make -j$(nproc)
make -j$(nproc) install

# Build S2OPC and the fuzzers
mkdir -p $S2OPC_BUILD
cd $S2OPC_BUILD
cmake -DCMAKE_BUILD_TYPE=RelWithDebInfo \
      -DCMAKE_C_COMPILER="$CC" -DCMAKE_C_FLAGS="$CFLAGS" -DCMAKE_EXE_LINKER_FLAGS="$CXXFLAGS" \
      -DCMAKE_C_LINK_EXECUTABLE="$CXX <FLAGS> <CMAKE_C_LINK_FLAGS> <LINK_FLAGS> <OBJECTS>  -o <TARGET> <LINK_LIBRARIES>" \
      -DWITH_OSS_FUZZ=ON -DENABLE_FUZZING=ON \
      $SRC/S2OPC
cmake --build . --target fuzzers
cp bin/* $OUT

# Build the corpora
cd $SAMPLES
for dir in $(find -maxdepth 1 -type d -not -name ".*"); do
    find $dir -exec zip -j $OUT/$(basename $dir)_fuzzer_seed_corpus.zip {} +
done
