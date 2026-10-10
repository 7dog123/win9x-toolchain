#!/bin/bash
# fetch-canadian.sh - Download all sources for Canadian Cross build
# Stage 1 uses GCC's ./contrib/download_prerequisites

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

source versions-canadian.txt

SOURCES_DIR="$SCRIPT_DIR/sources-canadian"
mkdir -p "$SOURCES_DIR"

echo "=== Fetching Canadian Cross sources to $SOURCES_DIR ==="

download() {
    local url="$1"
    local output="$2"
    if [[ -f "$output" ]]; then
        echo "  [SKIP] $output exists"
        return 0
    fi
    echo "  [GET] $url"
    wget -q --show-progress -O "$output" "$url"
}

# Main components
download "https://ftp.gnu.org/gnu/binutils/binutils-${BINUTILS_VER}.tar.xz" \
    "$SOURCES_DIR/binutils-${BINUTILS_VER}.tar.xz"
download "https://ftp.gnu.org/gnu/gcc/gcc-${GCC_VER}/gcc-${GCC_VER}.tar.xz" \
    "$SOURCES_DIR/gcc-${GCC_VER}.tar.xz"

# MinGW.org components
download "https://github.com/mingw-w32/mingw-org-wsl/archive/refs/tags/mingwrt-${MINGWRT_VER}-release.tar.gz" \
    "$SOURCES_DIR/mingwrt-${MINGWRT_VER}.tar.gz"
download "https://github.com/mingw-w32/mingw-org-wsl/archive/refs/tags/w32api-${W32API_VER}-release.tar.gz" \
    "$SOURCES_DIR/w32api-${W32API_VER}.tar.gz"

# pthreads-w32
download "https://sourceware.org/pub/pthreads-win32/pthreads-w32-${PTHREADS_VER//./-}-release.tar.gz" \
    "$SOURCES_DIR/pthreads-w32-${PTHREADS_VER}.tar.gz"

# make
download "$MAKE_URL" "$SOURCES_DIR/make-${MAKE_VER}.tar.gz"

# Extract GCC and run download_prerequisites for Stage 1
echo "=== Extracting GCC and downloading prerequisites (for Stage 1) ==="
cd "$SOURCES_DIR"
tar -xf "gcc-${GCC_VER}.tar.xz"
cd "gcc-${GCC_VER}"

# Use GCC's built-in script to download prerequisites for Stage 1
./contrib/download_prerequisites

# Copy the downloaded prerequisite tarballs to main sources dir for Stage 2 builds
echo "=== Copying prerequisite sources for Stage 2 ==="
cd "$SOURCES_DIR/gcc-${GCC_VER}"
for dep in gmp mpfr mpc isl; do
    # Find the extracted directory
    dir=$(ls -d ${dep}-* 2>/dev/null | head -1)
    if [[ -n "$dir" && -d "$dir" ]]; then
        # Create tarball from extracted source
        tar -czf "$SOURCES_DIR/${dir}.tar.gz" "$dir"
        echo "  Created ${dir}.tar.gz"
    fi
done

echo "=== Verifying ==="
ls -lh "$SOURCES_DIR"/*.tar.*
ls -lh "$SOURCES_DIR/gcc-${GCC_VER}"/gmp* "$SOURCES_DIR/gcc-${GCC_VER}"/mpfr* "$SOURCES_DIR/gcc-${GCC_VER}"/mpc* "$SOURCES_DIR/gcc-${GCC_VER}"/isl* 2>/dev/null || true

echo "=== Done ==="
echo "Sources ready in $SOURCES_DIR"