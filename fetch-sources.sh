#!/bin/bash
# fetch-sources.sh - Download all source tarballs for Win9x cross-compiler
# Uses GCC's ./contrib/download_prerequisites for gmp/mpfr/mpc/isl
# Multiple mirror fallback for reliability

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

source versions.txt

SOURCES_DIR="$SCRIPT_DIR/sources"
mkdir -p "$SOURCES_DIR"

echo "=== Fetching sources to $SOURCES_DIR ==="

download() {
    local output="$1"
    shift
    local urls=("$@")

    if [[ -f "$output" ]]; then
        echo "  [SKIP] $output exists"
        return 0
    fi

    for url in "${urls[@]}"; do
        echo "  [GET] $url"
        # Retry up to 3 times per URL
        local tries=3
        local delay=5
        for i in $(seq 1 $tries); do
            if wget -q --show-progress --timeout=30 -O "$output" "$url"; then
                echo "  [OK] $url"
                return 0
            fi
            echo "  [RETRY $i/$tries] Failed, waiting ${delay}s..."
            sleep $delay
            delay=$((delay * 2))
        done
        echo "  [FAIL] $url after $tries attempts"
    done
    echo "  [ERROR] All mirrors failed for $output"
    return 1
}

# Mirror arrays for each package - extensive fallback chain
BINUTILS_URLS=(
    "https://ftp.gnu.org/gnu/binutils/binutils-${BINUTILS_VER}.tar.xz"
    "https://ftpmirror.gnu.org/binutils/binutils-${BINUTILS_VER}.tar.xz"
    "https://mirror.kernel.org/gnu/binutils/binutils-${BINUTILS_VER}.tar.xz"
    "https://ftp.gnu.org/pub/gnu/binutils/binutils-${BINUTILS_VER}.tar.xz"
    "https://mirrors.edge.kernel.org/gnu/binutils/binutils-${BINUTILS_VER}.tar.xz"
    "https://gnu.mirror.constant.com/binutils/binutils-${BINUTILS_VER}.tar.xz"
    "https://ftp.jaist.ac.jp/pub/GNU/binutils/binutils-${BINUTILS_VER}.tar.xz"
    "https://ftp.tsukuba.wide.ad.jp/software/gnu/binutils/binutils-${BINUTILS_VER}.tar.xz"
)

GCC_URLS=(
    "https://ftp.gnu.org/gnu/gcc/gcc-${GCC_VER}/gcc-${GCC_VER}.tar.xz"
    "https://ftpmirror.gnu.org/gcc/gcc-${GCC_VER}/gcc-${GCC_VER}.tar.xz"
    "https://mirror.kernel.org/gnu/gcc/gcc-${GCC_VER}/gcc-${GCC_VER}.tar.xz"
    "https://ftp.gnu.org/pub/gnu/gcc/gcc-${GCC_VER}/gcc-${GCC_VER}.tar.xz"
    "https://mirrors.edge.kernel.org/gnu/gcc/gcc-${GCC_VER}/gcc-${GCC_VER}.tar.xz"
    "https://gnu.mirror.constant.com/gcc/gcc-${GCC_VER}/gcc-${GCC_VER}.tar.xz"
    "https://ftp.jaist.ac.jp/pub/GNU/gcc/gcc-${GCC_VER}/gcc-${GCC_VER}.tar.xz"
    "https://ftp.tsukuba.wide.ad.jp/software/gnu/gcc/gcc-${GCC_VER}/gcc-${GCC_VER}.tar.xz"
)

# Main components with multiple mirrors
echo "=== Downloading main components ==="
download "$SOURCES_DIR/binutils-${BINUTILS_VER}.tar.xz" "${BINUTILS_URLS[@]}"
download "$SOURCES_DIR/gcc-${GCC_VER}.tar.xz" "${GCC_URLS[@]}"

MINGWRT_URLS=(
    "https://github.com/mingw-w32/mingw-org-wsl/archive/refs/tags/mingwrt-${MINGWRT_VER}-release.tar.gz"
    "https://sourceforge.net/projects/mingw/files/MinGW/Base/mingwrt/mingwrt-${MINGWRT_VER}/mingwrt-${MINGWRT_VER}-mingw32-src.tar.xz/download"
    "https://sourceforge.net/projects/mingw/files/MinGW/Base/mingwrt/mingwrt-${MINGWRT_VER}/mingwrt-${MINGWRT_VER}-mingw32-src.tar.xz"
)
download "$SOURCES_DIR/mingwrt-${MINGWRT_VER}.tar.gz" "${MINGWRT_URLS[@]}"

W32API_URLS=(
    "https://github.com/mingw-w32/mingw-org-wsl/archive/refs/tags/w32api-${W32API_VER}-release.tar.gz"
    "https://sourceforge.net/projects/mingw/files/MinGW/Base/w32api/w32api-${W32API_VER}/w32api-${W32API_VER}-mingw32-src.tar.xz/download"
    "https://sourceforge.net/projects/mingw/files/MinGW/Base/w32api/w32api-${W32API_VER}/w32api-${W32API_VER}-mingw32-src.tar.xz"
)
download "$SOURCES_DIR/w32api-${W32API_VER}.tar.gz" "${W32API_URLS[@]}"

PTHREADS_URLS=(
    "https://sourceware.org/pub/pthreads-win32/pthreads-w32-${PTHREADS_VER//./-}-release.tar.gz"
    "https://sourceware.org/ftp/pthreads-win32/pthreads-w32-${PTHREADS_VER//./-}-release.tar.gz"
    "https://mirrors.edge.kernel.org/sourceware/pthreads-win32/pthreads-w32-${PTHREADS_VER//./-}-release.tar.gz"
)
download "$SOURCES_DIR/pthreads-w32-${PTHREADS_VER}.tar.gz" "${PTHREADS_URLS[@]}"

# Extract GCC and run download_prerequisites
echo "=== Extracting GCC and downloading prerequisites ==="
cd "$SOURCES_DIR"
tar -xf "gcc-${GCC_VER}.tar.xz"
cd "gcc-${GCC_VER}"

# Use GCC's built-in script to download prerequisites with mirrors
# Set mirror environment variables for the script
export GCC_MIRRORS="https://ftpmirror.gnu.org/gnu https://mirror.kernel.org/gnu https://ftp.gnu.org/gnu"
./contrib/download_prerequisites

echo "=== Verifying ==="
ls -lh "$SOURCES_DIR"/*.tar.*
ls -lh "$SOURCES_DIR/gcc-${GCC_VER}"/gmp* "$SOURCES_DIR/gcc-${GCC_VER}"/mpfr* "$SOURCES_DIR/gcc-${GCC_VER}"/mpc* "$SOURCES_DIR/gcc-${GCC_VER}"/isl* 2>/dev/null || true

echo "=== Done ==="
echo "Sources ready in $SOURCES_DIR"