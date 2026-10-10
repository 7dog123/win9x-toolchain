#!/bin/bash
# fetch-canadian.sh - Download all sources for Canadian Cross build
# Stage 1 uses GCC's ./contrib/download_prerequisites
# Multiple mirror fallback for reliability

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

source versions-canadian.txt

SOURCES_DIR="$SCRIPT_DIR/sources-canadian"
mkdir -p "$SOURCES_DIR"

echo "=== Fetching Canadian Cross sources to $SOURCES_DIR ==="

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

# Mirror arrays - just primary
BINUTILS_URLS=(
    "https://ftp.gnu.org/gnu/binutils/binutils-${BINUTILS_VER}.tar.gz"
)

GCC_URLS=(
    "https://ftp.gnu.org/gnu/gcc/gcc-${GCC_VER}/gcc-${GCC_VER}.tar.gz"
)

MAKE_URLS=(
    "https://ftp.gnu.org/gnu/make/make-${MAKE_VER}.tar.gz"
)

# Main components
echo "=== Downloading main components ==="
download "$SOURCES_DIR/binutils-${BINUTILS_VER}.tar.gz" "${BINUTILS_URLS[@]}"
download "$SOURCES_DIR/gcc-${GCC_VER}.tar.gz" "${GCC_URLS[@]}"

# mingw-org-wsl tags are wsl-X.Y.Z-release, not mingwrt/w32api specific
# Use sourceforge for the individual package releases
MINGWRT_URL="https://sourceforge.net/projects/mingw/files/MinGW/Base/mingwrt/mingwrt-${MINGWRT_VER}/mingwrt-${MINGWRT_VER}-mingw32-src.tar.xz"
download "$SOURCES_DIR/mingwrt-${MINGWRT_VER}.tar.xz" "$MINGWRT_URL"

W32API_URL="https://sourceforge.net/projects/mingw/files/MinGW/Base/w32api/w32api-${W32API_VER}/w32api-${W32API_VER}-mingw32-src.tar.xz"
download "$SOURCES_DIR/w32api-${W32API_VER}.tar.xz" "$W32API_URL"

PTHREADS_URLS=(
    "https://sourceware.org/pub/pthreads-win32/pthreads-w32-${PTHREADS_VER//./-}-release.tar.gz"
    "https://sourceware.org/ftp/pthreads-win32/pthreads-w32-${PTHREADS_VER//./-}-release.tar.gz"
    "https://mirrors.edge.kernel.org/sourceware/pthreads-win32/pthreads-w32-${PTHREADS_VER//./-}-release.tar.gz"
)
download "$SOURCES_DIR/pthreads-w32-${PTHREADS_VER}.tar.gz" "${PTHREADS_URLS[@]}"

download "$SOURCES_DIR/make-${MAKE_VER}.tar.gz" "${MAKE_URLS[@]}"

# Extract GCC and run download_prerequisites for Stage 1
echo "=== Extracting GCC and downloading prerequisites (for Stage 1) ==="
cd "$SOURCES_DIR"
tar -xf "gcc-${GCC_VER}.tar.gz"
cd "gcc-${GCC_VER}"

# Use GCC's built-in script to download prerequisites for Stage 1
export GCC_MIRRORS="https://ftpmirror.gnu.org/gnu https://mirror.kernel.org/gnu https://ftp.gnu.org/gnu"
./contrib/download_prerequisites

# Copy the downloaded prerequisite tarballs to main sources dir for Stage 2 builds
echo "=== Copying prerequisite sources for Stage 2 ==="
cd "$SOURCES_DIR/gcc-${GCC_VER}"
for dep in gmp mpfr mpc isl; do
    dir=$(ls -d ${dep}-* 2>/dev/null | head -1)
    if [[ -n "$dir" && -d "$dir" ]]; then
        tar -czf "$SOURCES_DIR/${dir}.tar.gz" "$dir"
        echo "  Created ${dir}.tar.gz"
    fi
done

echo "=== Verifying ==="
ls -lh "$SOURCES_DIR"/*.tar.*
ls -lh "$SOURCES_DIR/gcc-${GCC_VER}"/gmp* "$SOURCES_DIR/gcc-${GCC_VER}"/mpfr* "$SOURCES_DIR/gcc-${GCC_VER}"/mpc* "$SOURCES_DIR/gcc-${GCC_VER}"/isl* 2>/dev/null || true

echo "=== Done ==="
echo "Sources ready in $SOURCES_DIR"