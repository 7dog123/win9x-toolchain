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

    # Handle case where single URL string is passed instead of array
    if [[ ${#urls[@]} -eq 1 && ! "${urls[0]}" =~ ^https?:// ]]; then
        urls=("${urls[0]}")
    elif [[ ${#urls[@]} -eq 0 ]]; then
        echo "  [ERROR] No URLs provided for $output"
        return 1
    fi

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

# Primary mirror
BINUTILS_URL="https://ftp.gnu.org/gnu/binutils/binutils-${BINUTILS_VER}.tar.gz"

# GCC 6.3.0 - use .tar.gz (more widely available)
GCC_URLS=(
    "https://ftp.gnu.org/gnu/gcc/gcc-${GCC_VER}/gcc-${GCC_VER}.tar.gz"
)

# Main components with multiple mirrors
echo "=== Downloading main components ==="
download "$SOURCES_DIR/binutils-${BINUTILS_VER}.tar.gz" "${BINUTILS_URL}"
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