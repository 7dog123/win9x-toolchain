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
tar -xf "$SOURCES_DIR/binutils-${BINUTILS_VER}.tar.gz"
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

# ===== Step 2: w32api headers =====
# Extract mingwrt as a sibling FIRST: w32api's Makefile generates
# _mingw.h from ../mingwrt*/include/_mingw.h.in (mingwrt_srcdir); the
# later mingwrt build needs ../w32api*/include/w32api.h.in in turn.
# Headers alone here: the import libraries need C stubs (ws2_32.c,
# shell32.c, *-uuid.c) that pull in winnt.h, whose CONTEXT definitions
# are gated on _X86_, and no cross-GCC exists yet (CC would fall back to
# host gcc, which neither defines _X86_ nor produces i386 COFF objects).
# The libraries are built in step 4 with the cross-GCC.
echo "=== [2/8] Installing w32api-$W32API_VER headers ==="
cd "$BUILD_DIR"
rm -rf "mingwrt-${MINGWRT_VER}" "w32api-${W32API_VER}"
tar -xf "$SOURCES_DIR/mingwrt-${MINGWRT_VER}.tar.xz"
tar -xf "$SOURCES_DIR/w32api-${W32API_VER}.tar.xz"
cd "w32api-${W32API_VER}"

./configure --host="$TARGET" --prefix="$SYSROOT"
make -j"$JOBS" install-headers
echo "w32api headers done"

# GCC builds this as a 'mingw' target and expects system headers at
# <sysroot>/mingw/include (SYSTEM_HEADER_DIR=/mingw/include), both for
# fixincludes during the GCC build and for target compiles. Expose the
# canonical mingw layout alongside <sysroot>/include and <sysroot>/lib.
mkdir -p "$SYSROOT/mingw"
ln -sfn ../include "$SYSROOT/mingw/include"
ln -sfn ../lib "$SYSROOT/mingw/lib"
ln -sfn ../bin "$SYSROOT/mingw/bin"
echo "sysroot mingw layout done"

# ===== Step 3: GCC Stage 1 (C and C++) =====
echo "=== [3/8] Building GCC $GCC_VER stage1 ==="
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

# ===== Step 4: w32api import libraries (cross-GCC) =====
# Build the import libs with the cross-GCC from step 3 instead of host
# gcc: the C-stub members (ws2_32.c, shell32.c, *-uuid.c) must be i386
# COFF and need _X86_ defined so winnt.h (CONTEXT) compiles. CPPFLAGS
# adds the cross-compiler's private include dir for stdarg.h because the
# w32api Makefile compiles the stubs with -nostdinc.
echo "=== [4/8] Building w32api-$W32API_VER import libraries (cross GCC) ==="
cd "$BUILD_DIR/w32api-${W32API_VER}"
make -j"$JOBS" \
    CC="$TARGET-gcc" \
    CPPFLAGS="-D_X86_ -I$($TARGET-gcc -print-file-name=include)" \
    install-w32api-libs
echo "w32api libs done"

# ===== Step 5: mingwrt (MinGW runtime) =====
# Tree was already extracted as a sibling in step 2 (w32api needs it).
# Needs the cross-GCC from step 3; the sibling w32api tree supplies
# w32api.h.in. The stage-2 DLL build auto-disables while the CRT itself
# is still missing from the sysroot.
echo "=== [5/8] Building mingwrt-$MINGWRT_VER ==="
cd "$BUILD_DIR/mingwrt-${MINGWRT_VER}"

./configure \
    --host="$TARGET" \
    --prefix="$SYSROOT" \
    --disable-dependency-tracking \
    CFLAGS="$TARGET_CFLAGS" \
    LDFLAGS="$TARGET_LDFLAGS"
make -j"$JOBS"
make install
echo "mingwrt done"

# ===== Step 6: GCC Stage 2 (full compiler) =====
echo "=== [6/8] Building GCC $GCC_VER stage2 (full) ==="
cd "$BUILD_DIR/build-gcc-stage1"
make -j"$JOBS" all
make install
echo "GCC stage2 done"

# ===== Step 7: mingwrt (final, full build with DLLs) =====
# Now that the full compiler and CRT are present, re-run configure so
# the stage-2 DLL build (mingwm10.dll etc.) is no longer disabled.
echo "=== [7/8] Rebuilding mingwrt (stage-1+2) ==="
cd "$BUILD_DIR/mingwrt-${MINGWRT_VER}"
make clean || true
./configure \
    --host="$TARGET" \
    --prefix="$SYSROOT" \
    CFLAGS="$TARGET_CFLAGS" \
    LDFLAGS="$TARGET_LDFLAGS"
make -j"$JOBS"
make install
echo "mingwrt final done"

# ===== Step 8: pthreads-w32 =====
echo "=== [8/8] Building pthreads-w32-$PTHREADS_VER ==="
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