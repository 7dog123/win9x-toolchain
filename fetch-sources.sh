#!/bin/bash
# fetch-sources.sh - Download all source tarballs for Win9x cross-compiler
# Uses GCC's ./contrib/download_prerequisites for gmp/mpfr/mpc/isl

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

source versions.txt

SOURCES_DIR="$SCRIPT_DIR/sources"
mkdir -p "$SOURCES_DIR"

echo "=== Fetching sources to $SOURCES_DIR ==="

download() {
    local url="$1"
    local output="$2"
    if [[ -f "$output" ]]; then
        echo "  [SKIP] $output exists"
        return 0
    fi
    echo "  [GET] $url"
    # Retry up to 5 times with exponential backoff
    local tries=5
    local delay=5
    for i in $(seq 1 $tries); do
        if wget -q --show-progress --timeout=30 -O "$output" "$url"; then
            return 0
        fi
        echo "  [RETRY $i/$tries] Failed, waiting ${delay}s..."
        sleep $delay
        delay=$((delay * 2))
    done
    echo "  [FAIL] Download failed after $tries attempts: $url"
    return 1
}

# Main components
download "$BINUTILS_URL" "$SOURCES_DIR/binutils-${BINUTILS_VER}.tar.xz"
download "$GCC_URL" "$SOURCES_DIR/gcc-${GCC_VER}.tar.xz"
download "$MINGWRT_URL" "$SOURCES_DIR/mingwrt-${MINGWRT_VER}.tar.gz"
download "$W32API_URL" "$SOURCES_DIR/w32api-${W32API_VER}.tar.gz"
download "$PTHREADS_URL" "$SOURCES_DIR/pthreads-w32-${PTHREADS_VER}.tar.gz"

# Extract GCC and run its download_prerequisites script
# This downloads gmp, mpfr, mpc, isl automatically with correct versions
echo "=== Extracting GCC and downloading prerequisites ==="
cd "$SOURCES_DIR"
tar -xf "gcc-${GCC_VER}.tar.xz"
cd "gcc-${GCC_VER}"

# Use GCC's built-in script to download prerequisites
# This fetches the exact versions GCC expects
./contrib/download_prerequisites

echo "=== Verifying ==="
ls -lh "$SOURCES_DIR"/*.tar.*
ls -lh "$SOURCES_DIR/gcc-${GCC_VER}"/gmp* "$SOURCES_DIR/gcc-${GCC_VER}"/mpfr* "$SOURCES_DIR/gcc-${GCC_VER}"/mpc* "$SOURCES_DIR/gcc-${GCC_VER}"/isl* 2>/dev/null || true

echo "=== Done ==="
echo "Sources ready in $SOURCES_DIR"