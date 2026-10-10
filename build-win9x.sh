#!/bin/bash
# build-win9x.sh - Build Win9x cross-compiler toolchain (i586 target)
# Run from win9x-toolchain directory on Debian 9 (stretch)
# Produces a cross-compiler that runs on Linux and targets Windows 95/98/ME

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

source versions.txt

# ===== Configuration =====
PREFIX="$SCRIPT_DIR/toolchain"
SYSROOT="$PREFIX/$TARGET"
BUILD_DIR="$SCRIPT_DIR/build"
SOURCES_DIR="$SCRIPT_DIR/sources"

# Parallel jobs
JOBS=$(nproc)

# Target-specific flags for Win95 compatibility
# -march=i586 -mtune=pentium : Pentium (original) compatible
# -DWINVER=0x0400 -D_WIN32_WINNT=0x0400 : Windows 95 API level
# -D_WIN32_WINDOWS=0x0410 : Windows 98 (for Win98/ME support too)
TARGET_CFLAGS="-march=i586 -mtune=pentium -O2 -pipe -DWINVER=0x0400 -D_WIN32_WINNT=0x0400 -D_WIN32_WINDOWS=0x0410"
TARGET_CXXFLAGS="$TARGET_CFLAGS"
TARGET_LDFLAGS="-Wl,--large-address-aware -Wl,--disable-auto-import"

# Host (build machine) flags
HOST_CFLAGS="-O2 -pipe"
HOST_CXXFLAGS="$HOST_CFLAGS"

export PATH="$PREFIX/bin:$PATH"

echo "=== Win9x Cross-Compiler Build ==="
echo "Target: $TARGET"
echo "Prefix: $PREFIX"
echo "Sysroot: $SYSROOT"
echo "Jobs: $JOBS"
echo ""

mkdir -p "$PREFIX" "$SYSROOT" "$BUILD_DIR"

# ===== Step 1: binutils =====
echo "=== [1/7] Building binutils-$BINUTILS_VER ==="
cd "$BUILD_DIR"
rm -rf "binutils-${BINUTILS_VER}"
tar -xf "$SOURCES_DIR/binutils-${BINUTILS_VER}.tar.xz"
mkdir -p "build-binutils"
cd "build-binutils"
"../binutils-${BINUTILS_VER}/configure" \
    --target="$TARGET" \
    --prefix="$PREFIX" \
    --with-sysroot="$SYSROOT" \
    --disable-nls \
    --disable-werror \
    --enable-lto \
    --enable-plugins \
    --enable-gold \
    --enable-ld=default \
    --disable-multilib
make -j"$JOBS"
make install
echo "binutils done"

# ===== Step 2: mingw-w64 headers (w32api) =====
echo "=== [2/7] Installing w32api-$W32API_VER headers ==="
cd "$BUILD_DIR"
rm -rf "mingw-org-wsl-w32api-${W32API_VER}-release"
tar -xf "$SOURCES_DIR/w32api-${W32API_VER}.tar.gz"
cd "mingw-org-wsl-w32api-${W32API_VER}-release"

# Configure and install headers only
./configure \
    --host="$TARGET" \
    --prefix="$SYSROOT" \
    --enable-sdk=all \
    --enable-secure-api \
    --with-default-win32-winnt=0x0400 \
    --with-default-msvcrt=msvcrt
make -j"$JOBS" install-headers
make -j"$JOBS" install-libs
echo "w32api headers done"

# ===== Step 3: mingwrt (MinGW runtime) =====
echo "=== [3/7] Building mingwrt-$MINGWRT_VER ==="
cd "$BUILD_DIR"
rm -rf "mingw-org-wsl-mingwrt-${MINGWRT_VER}-release"
tar -xf "$SOURCES_DIR/mingwrt-${MINGWRT_VER}.tar.gz"
cd "mingw-org-wsl-mingwrt-${MINGWRT_VER}-release/mingwrt"

# Build mingwrt with Win95-compatible settings
./configure \
    --host="$TARGET" \
    --prefix="$SYSROOT" \
    --enable-msvcrt=msvcrt \
    --disable-unicode \
    --disable-dependency-tracking \
    CFLAGS="$TARGET_CFLAGS" \
    LDFLAGS="$TARGET_LDFLAGS"
make -j"$JOBS"
make install
echo "mingwrt done"

# ===== Step 4: GCC Stage 1 (C and C++) =====
echo "=== [4/7] Building GCC $GCC_VER stage1 ==="
cd "$BUILD_DIR"
mkdir -p "build-gcc-stage1"
cd "build-gcc-stage1"
"$SOURCES_DIR/gcc-${GCC_VER}/configure" \
    --target="$TARGET" \
    --prefix="$PREFIX" \
    --with-sysroot="$SYSROOT" \
    --enable-languages=c,c++ \
    --disable-nls \
    --disable-multilib \
    --disable-libstdcxx-threads \
    --disable-libstdcxx-pch \
    --disable-libgomp \
    --disable-libmudflap \
    --disable-libssp \
    --disable-libquadmath \
    --disable-libquadmath-support \
    --disable-shared \
    --enable-static \
    --enable-threads=win32 \
    --enable-sjlj-exceptions \
    --with-dwarf2 \
    --with-gnu-as \
    --with-gnu-ld \
    CFLAGS_FOR_TARGET="$TARGET_CFLAGS" \
    CXXFLAGS_FOR_TARGET="$TARGET_CXXFLAGS" \
    LDFLAGS_FOR_TARGET="$TARGET_LDFLAGS"
make -j"$JOBS" all-gcc
make install-gcc
echo "GCC stage1 done"

# ===== Step 5: mingwrt (final, with GCC available) =====
echo "=== [5/7] Rebuilding mingwrt with GCC ==="
cd "$BUILD_DIR/mingw-org-wsl-mingwrt-${MINGWRT_VER}-release/mingwrt"
make clean || true
./configure \
    --host="$TARGET" \
    --prefix="$SYSROOT" \
    --enable-msvcrt=msvcrt \
    --disable-unicode \
    CFLAGS="$TARGET_CFLAGS" \
    LDFLAGS="$TARGET_LDFLAGS"
make -j"$JOBS"
make install
echo "mingwrt final done"

# ===== Step 6: GCC Stage 2 (full compiler) =====
echo "=== [6/7] Building GCC $GCC_VER stage2 (full) ==="
cd "$BUILD_DIR/build-gcc-stage1"
make -j"$JOBS" all
make install
echo "GCC stage2 done"

# ===== Step 7: pthreads-w32 =====
echo "=== [7/7] Building pthreads-w32-$PTHREADS_VER ==="
cd "$BUILD_DIR"
rm -rf "pthreads-w32-${PTHREADS_VER//./-}-release"
tar -xf "$SOURCES_DIR/pthreads-w32-${PTHREADS_VER}.tar.gz"
cd "pthreads-w32-${PTHREADS_VER//./-}-release"

# Build with MinGW cross-compiler
make -j"$JOBS" \
    CC="$TARGET-gcc" \
    AR="$TARGET-ar" \
    RC="$TARGET-windres" \
    DLLTOOL="$TARGET-dlltool" \
    CROSS="$TARGET-" \
    GC=1 \
    clean GC-static

# Install headers and libraries
mkdir -p "$SYSROOT/include" "$SYSROOT/lib"
cp pthread.h sched.h semaphore.h "$SYSROOT/include/"
cp libpthreadGC2.a "$SYSROOT/lib/libpthread.a"
cp pthreadGC2.dll "$SYSROOT/bin/" 2>/dev/null || true

# Also create pthreadGC2.dll.a import lib if needed
$TARGET-dlltool -d pthreadGC2.def -l "$SYSROOT/lib/libpthread.dll.a" 2>/dev/null || \
    $TARGET-dlltool --export-all-symbols --output-lib "$SYSROOT/lib/libpthread.dll.a" pthreadGC2.dll 2>/dev/null || true

echo "pthreads-w32 done"

# ===== Final: Verify toolchain =====
echo ""
echo "=== Verifying toolchain ==="
"$PREFIX/bin/$TARGET-gcc" --version
"$PREFIX/bin/$TARGET-g++" --version
"$PREFIX/bin/$TARGET-ld" --version
"$PREFIX/bin/$TARGET-as" --version

echo ""
echo "=== Testing Win95-compatible compilation ==="
cat > "$BUILD_DIR/test_win95.c" << 'EOF'
#include <windows.h>
#include <stdio.h>
#include <pthread.h>

void* thread_func(void* arg) {
    printf("Thread running on Win95-compatible target\n");
    return NULL;
}

int main() {
    pthread_t t;
    printf("Hello from Win95 target! WINVER=0x%04X\n", WINVER);
    pthread_create(&t, NULL, thread_func, NULL);
    pthread_join(t, NULL);
    return 0;
}
EOF

"$PREFIX/bin/$TARGET-gcc" \
    -march=i586 -mtune=pentium \
    -DWINVER=0x0400 -D_WIN32_WINNT=0x0400 -D_WIN32_WINDOWS=0x0410 \
    -o "$BUILD_DIR/test_win95.exe" \
    "$BUILD_DIR/test_win95.c" -lpthread

echo "Test binary created: $BUILD_DIR/test_win95.exe"
file "$BUILD_DIR/test_win95.exe"
"$PREFIX/bin/$TARGET-objdump" -p "$BUILD_DIR/test_win95.exe" | grep -i "dll name"

echo ""
echo "=== Build complete! ==="
echo "Toolchain installed at: $PREFIX"
echo "Sysroot at: $SYSROOT"
echo ""
echo "To use this cross-compiler:"
echo "  export PATH=\"$PREFIX/bin:\$PATH\""
echo "  $TARGET-gcc -march=i586 -mtune=pentium -DWINVER=0x0400 -D_WIN32_WINNT=0x0400 ..."