#!/bin/bash
# build-canadian.sh - Canadian Cross: Linux → Win9x → Win9x
# Builds a complete Win9x-hosted toolchain (runs on Win9x, targets Win9x)
# Requires: Debian 9+ or Ubuntu 18.04+ with build dependencies installed

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

source versions-canadian.txt

# ===== Configuration =====
BUILD=x86_64-linux-gnu
HOST=i586-w64-mingw32
TARGET=i586-w64-mingw32

PREFIX="$SCRIPT_DIR/toolchain-canadian"
STAGE1_PREFIX="$PREFIX/stage1"      # Cross-compiler: runs on Linux, targets Win9x
STAGE2_PREFIX="$PREFIX/stage2"      # Native Win9x toolchain: runs on Win9x, targets Win9x
SYSROOT1="$STAGE1_PREFIX/$TARGET"   # Stage 1 sysroot
SYSROOT2="$STAGE2_PREFIX/$TARGET"   # Stage 2 sysroot
BUILD_DIR="$SCRIPT_DIR/build-canadian"
SOURCES_DIR="$SCRIPT_DIR/sources-canadian"

JOBS=$(nproc)

HOST_CFLAGS="-march=i586 -mtune=pentium -O2 -pipe -DWINVER=0x0400 -D_WIN32_WINNT=0x0400 -D_WIN32_WINDOWS=0x0410"
HOST_CXXFLAGS="$HOST_CFLAGS"
HOST_LDFLAGS="-static"
HOST_CONFIGURE_FLAGS="--host=$HOST --build=$BUILD --disable-shared --enable-static"

export PATH="$STAGE1_PREFIX/bin:$PATH"

echo "=== Canadian Cross Build ==="
echo "Build:  $BUILD"
echo "Host:   $HOST"
echo "Target: $TARGET"
echo "Stage 1: $STAGE1_PREFIX (Linux → Win9x)"
echo "Stage 2: $STAGE2_PREFIX (Win9x → Win9x)"
echo "Jobs: $JOBS"
echo ""

mkdir -p "$STAGE1_PREFIX" "$STAGE2_PREFIX" "$SYSROOT1" "$SYSROOT2" "$BUILD_DIR"

# ============================================================
# STAGE 0: Build Stage 1 Cross-Compiler (Linux → Win9x)
# ============================================================
# This is the foundation - a cross-compiler running on Linux
# that produces Win9x binaries. We'll use it to build Stage 2.

build_stage1() {
    echo "============================================================"
    echo "STAGE 1: Building cross-compiler (Linux → Win9x)"
    echo "============================================================"
    
    # ---- 0a: binutils ----
    echo "[1/10] binutils (Stage 1)"
    cd "$BUILD_DIR"
    rm -rf "binutils-${BINUTILS_VER}-stage1"
    tar -xf "$SOURCES_DIR/binutils-${BINUTILS_VER}.tar.gz" -C "$BUILD_DIR"
    mv "binutils-${BINUTILS_VER}" "binutils-${BINUTILS_VER}-stage1"
    mkdir -p "build-binutils-stage1"
    cd "build-binutils-stage1"
    "../binutils-${BINUTILS_VER}-stage1/configure" \
        --target="$TARGET" \
        --prefix="$STAGE1_PREFIX" \
        --with-sysroot="$SYSROOT1" \
        --disable-nls --disable-werror --disable-multilib \
        --enable-lto --enable-plugins --enable-gold
    make -j"$JOBS"
    make install

    # ---- 0b: w32api headers ----
    # Extract mingwrt as a sibling FIRST: w32api generates _mingw.h from
    # ../*mingwrt*/include/_mingw.h.in (mingwrt_srcdir); the later
    # mingwrt build needs ../*w32api*/include/w32api.h.in in turn.
    # Headers only here; the import libs need C stubs (ws2_32.c,
    # shell32.c, *-uuid.c) that hit winnt.h's _X86_-gated CONTEXT and
    # must be i386 COFF, so they're built after GCC stage1 (step 3b).
    echo "[2/10] w32api headers (Stage 1)"
    cd "$BUILD_DIR"
    rm -rf "mingw-w32api-stage1" "mingw-mingwrt-stage1"
    tar -xf "$SOURCES_DIR/mingwrt-${MINGWRT_VER}.tar.xz"
    mv "mingwrt-${MINGWRT_VER}" "mingw-mingwrt-stage1"
    tar -xf "$SOURCES_DIR/w32api-${W32API_VER}.tar.xz"
    mv "w32api-${W32API_VER}" "mingw-w32api-stage1"
    cd "mingw-w32api-stage1"
    ./configure --host="$TARGET" --prefix="$SYSROOT1"
    make -j"$JOBS" install-headers
    # GCC builds this as a 'mingw' target and expects system headers at
    # <sysroot>/mingw/include (SYSTEM_HEADER_DIR=/mingw/include), both
    # for fixincludes during the GCC build and for target compiles.
    mkdir -p "$SYSROOT1/mingw"
    ln -sfn ../include "$SYSROOT1/mingw/include"
    ln -sfn ../lib "$SYSROOT1/mingw/lib"
    ln -sfn ../bin "$SYSROOT1/mingw/bin"
    # GCC 6 ships no usable <stdarg.h> for this target (its gcc/include
    # version is a `#include_next` stub), mingwrt 5.0.2 provides none,
    # and w32api compiles its C stubs with -nostdinc.
    mkdir -p "$SYSROOT1/include"
    cp "$SCRIPT_DIR/mingw-fixed/stdarg.h" "$SYSROOT1/include/stdarg.h"

    # ---- 0c: GCC Stage 1 (C and C++) - IN-TREE DEPENDENCIES ----
    echo "[3/10] GCC Stage 1 (C and C++) - in-tree deps"
    cd "$BUILD_DIR"
    rm -rf "gcc-${GCC_VER}-stage1"
    cp -r "$SOURCES_DIR/gcc-${GCC_VER}" "gcc-${GCC_VER}-stage1"
    # download_prerequisites already ran in fetch script, deps are in-tree
    mkdir -p "build-gcc-stage1"
    cd "build-gcc-stage1"
    "../gcc-${GCC_VER}-stage1/configure" \
        --target="$TARGET" \
        --prefix="$STAGE1_PREFIX" \
        --with-sysroot="$SYSROOT1" \
        --enable-languages=c,c++ \
        --disable-nls --disable-multilib \
        --disable-libstdcxx-threads --disable-libstdcxx-pch \
        --disable-libgomp --disable-libmudflap --disable-libssp \
        --disable-libquadmath --disable-libquadmath-support \
        --disable-shared --enable-static \
        --enable-threads=win32 --enable-sjlj-exceptions --with-dwarf2 \
        --with-gnu-as --with-gnu-ld \
        CFLAGS_FOR_TARGET="$HOST_CFLAGS" \
        CXXFLAGS_FOR_TARGET="$HOST_CXXFLAGS" \
        LDFLAGS_FOR_TARGET="$HOST_LDFLAGS"
    make -j"$JOBS" all-gcc
    make install-gcc

    # ---- 0c2: w32api import libraries (cross GCC) ----
    # Headers were installed in step 2; the import libs' C-stub members
    # (ws2_32.c, shell32.c, *-uuid.c) must be i386 COFF and need _X86_
    # so winnt.h (CONTEXT) compiles. CPPFLAGS adds the sysroot, which
    # holds the self-contained stdarg.h the stubs need (-nostdinc; the
    # cross-GCC's own stdarg.h is only a `#include_next` stub).
    echo "[3b] w32api import libs (cross GCC)"
    cd "$BUILD_DIR/mingw-w32api-stage1"
    make -j"$JOBS" \
        CC="$TARGET-gcc" \
        CPPFLAGS="-D_X86_ -I$SYSROOT1/include" \
        install-w32api-libs

    # ---- 0d: mingwrt ----
    # Tree was already extracted as a sibling in step 2 (w32api needs it).
    echo "[4/10] mingwrt (Stage 1)"
    cd "$BUILD_DIR/mingw-mingwrt-stage1"
    ./configure \
        --host="$TARGET" \
        --prefix="$SYSROOT1" \
        --disable-dependency-tracking \
        CFLAGS="$HOST_CFLAGS" LDFLAGS="$HOST_LDFLAGS"
    make -j"$JOBS"
    make install

    # ---- 0e: GCC Stage 2 (Full) ----
    echo "[5/10] GCC Stage 2 (Full)"
    cd "$BUILD_DIR/build-gcc-stage1"
    make -j"$JOBS" all
    make install

    # ---- 0f: Rebuild mingwrt with GCC (stage-1+2) ----
    echo "[6/10] mingwrt rebuild (stage-1+2)"
    cd "$BUILD_DIR/mingw-mingwrt-stage1"
    make clean || true
    ./configure \
        --host="$TARGET" \
        --prefix="$SYSROOT1" \
        CFLAGS="$HOST_CFLAGS" LDFLAGS="$HOST_LDFLAGS"
    make -j"$JOBS"
    make install

    # ---- Remove in-tree gmp/mpfr/mpc/isl from Stage 1 GCC source tree ----
    # This forces Stage 2 to use external libraries we'll build for HOST
    echo "[6b] Removing in-tree gmp/mpfr/mpc/isl from Stage 1 GCC source"
    rm -rf "$BUILD_DIR/gcc-${GCC_VER}-stage1/gmp" \
           "$BUILD_DIR/gcc-${GCC_VER}-stage1/mpfr" \
           "$BUILD_DIR/gcc-${GCC_VER}-stage1/mpc" \
           "$BUILD_DIR/gcc-${GCC_VER}-stage1/isl"

    # ---- 0g: zlib for target ----
    echo "[7/10] zlib (target)"
    cd "$BUILD_DIR"
    rm -rf "zlib-${ZLIB_VER}-target"
    tar -xf "$SOURCES_DIR/zlib-${ZLIB_VER}.tar.gz"
    mv "zlib-${ZLIB_VER}" "zlib-${ZLIB_VER}-target"
    cd "zlib-${ZLIB_VER}-target"
    CHOST="$TARGET" ./configure --prefix="$SYSROOT1" --static
    make -j"$JOBS"
    make install

    # ---- 0h: pthreads-w32 ----
    echo "[8/10] pthreads-w32 (Stage 1)"
    cd "$BUILD_DIR"
    rm -rf "pthreads-w32-stage1"
    tar -xf "$SOURCES_DIR/pthreads-w32-${PTHREADS_VER}.tar.gz"
    mv "pthreads-w32-${PTHREADS_VER//./-}-release" "pthreads-w32-stage1"
    cd "pthreads-w32-stage1"
    make -j"$JOBS" \
        CC="$TARGET-gcc" AR="$TARGET-ar" RC="$TARGET-windres" DLLTOOL="$TARGET-dlltool" \
        CROSS="$TARGET-" GC=1 clean GC-static
    mkdir -p "$SYSROOT1/include" "$SYSROOT1/lib"
    cp pthread.h sched.h semaphore.h "$SYSROOT1/include/"
    cp libpthreadGC2.a "$SYSROOT1/lib/libpthread.a"

    # ---- 0i: Build HOST dependencies (gmp, mpfr, mpc, isl, libiconv, gettext) ----
    echo "[9/10] Building HOST dependencies (gmp, mpfr, mpc, isl, libiconv, gettext)"
    build_host_deps

    # ---- 0j: Verify Stage 1 ----
    echo "[10/10] Verifying Stage 1"
    "$STAGE1_PREFIX/bin/$TARGET-gcc" --version
    "$STAGE1_PREFIX/bin/$TARGET-g++" --version
    
    echo "=== STAGE 1 COMPLETE ==="
    echo "Cross-compiler at: $STAGE1_PREFIX"
    echo "Sysroot at: $SYSROOT1"
}

build_host_deps() {
    local deps_build_dir="$BUILD_DIR/host-deps"
    mkdir -p "$deps_build_dir"
    local host_prefix="$SYSROOT1"  # Install into Stage 1 sysroot

    # Helper: build a dep for HOST
    build_dep() {
        local name="$1" ver="$2" url_var="${name^^}_URL" configure_extra="$3"
        echo "  Building $name-$ver for HOST..."
        cd "$deps_build_dir"
        rm -rf "${name}-${ver}-host"
        tar -xf "$SOURCES_DIR/${name}-${ver}.tar.*"
        mv "${name}-${ver}" "${name}-${ver}-host"
        mkdir -p "build-${name}-host"
        cd "build-${name}-host"
        "../${name}-${ver}-host/configure" \
            --build="$BUILD" \
            --host="$HOST" \
            --prefix="$host_prefix" \
            --disable-shared --enable-static \
            $configure_extra \
            CC="$TARGET-gcc" CXX="$TARGET-g++" \
            CFLAGS="$HOST_CFLAGS" CXXFLAGS="$HOST_CXXFLAGS" LDFLAGS="$HOST_LDFLAGS"
        make -j"$JOBS"
        make install
    }

    # Order matters: gmp → mpfr → mpc → isl → libiconv → gettext
    build_dep "gmp" "$GMP_VER" "--enable-cxx"
    build_dep "mpfr" "$MPFR_VER" "--with-gmp=$host_prefix"
    build_dep "mpc" "$MPC_VER" "--with-gmp=$host_prefix --with-mpfr=$host_prefix"
    build_dep "isl" "$ISL_VER" "--with-gmp-prefix=$host_prefix"
    build_dep "libiconv" "$LIBICONV_VER" ""
    build_dep "gettext" "$GETTEXT_VER" "--disable-csharp --disable-java --disable-openmp --without-emacs --without-cvs --without-git"
}

# ============================================================
# STAGE 2: Canadian Cross (build=Linux, host=Win9x, target=Win9x)
# ============================================================

build_stage2() {
    echo "============================================================"
    echo "STAGE 2: Canadian Cross (Linux→Win9x→Win9x)"
    echo "============================================================"
    
    # Stage 2 will be built USING Stage 1 compiler
    # The resulting binaries RUN on Win9x

    # ---- 2a: binutils (host) ----
    echo "[1/7] binutils (host=$HOST)"
    cd "$BUILD_DIR"
    rm -rf "binutils-${BINUTILS_VER}-host"
    tar -xf "$SOURCES_DIR/binutils-${BINUTILS_VER}.tar.gz" -C "$BUILD_DIR"
    mv "binutils-${BINUTILS_VER}" "binutils-${BINUTILS_VER}-host"
    mkdir -p "build-binutils-host"
    cd "build-binutils-host"
    "../binutils-${BINUTILS_VER}-host/configure" \
        --build="$BUILD" --host="$HOST" --target="$TARGET" \
        --prefix="$STAGE2_PREFIX" \
        --with-sysroot="$SYSROOT2" \
        --disable-nls --disable-werror --disable-multilib \
        CC="$HOST-gcc" CXX="$HOST-g++" AR="$HOST-ar" RANLIB="$HOST-ranlib" \
        CFLAGS="$HOST_CFLAGS" CXXFLAGS="$HOST_CXXFLAGS" LDFLAGS="$HOST_LDFLAGS"
    make -j"$JOBS"
    make install

    # ---- 2b: w32api (headers + import libs, host) ----
    # Extract mingwrt as a sibling FIRST (w32api needs
    # ../*mingwrt*/include/_mingw.h.in → mingwrt_srcdir).
    echo "[2/7] w32api (host=$HOST)"
    cd "$BUILD_DIR"
    rm -rf "mingw-w32api-host" "mingw-mingwrt-host"
    tar -xf "$SOURCES_DIR/mingwrt-${MINGWRT_VER}.tar.xz"
    mv "mingwrt-${MINGWRT_VER}" "mingw-mingwrt-host"
    tar -xf "$SOURCES_DIR/w32api-${W32API_VER}.tar.xz"
    mv "w32api-${W32API_VER}" "mingw-w32api-host"
    cd "mingw-w32api-host"
    ./configure \
        --build="$BUILD" --host="$HOST" \
        --prefix="$SYSROOT2" \
        CC="$HOST-gcc" CFLAGS="$HOST_CFLAGS"
    # -D_X86_ resolves winnt.h's CONTEXT gate for the C-stub import libs
    # (ws2_32.c etc.), which compile with -nostdinc; -I$SYSROOT2/include
    # provides the self-contained stdarg.h (the cross-GCC's own is only
    # a `#include_next` stub).
    mkdir -p "$SYSROOT2/include"
    cp "$SCRIPT_DIR/mingw-fixed/stdarg.h" "$SYSROOT2/include/stdarg.h"
    make -j"$JOBS" \
        CPPFLAGS="-D_X86_ -I$SYSROOT2/include" \
        install
    # GCC builds this as a 'mingw' target and expects system headers at
    # <sysroot>/mingw/include (SYSTEM_HEADER_DIR=/mingw/include).
    mkdir -p "$SYSROOT2/mingw"
    ln -sfn ../include "$SYSROOT2/mingw/include"
    ln -sfn ../lib "$SYSROOT2/mingw/lib"
    ln -sfn ../bin "$SYSROOT2/mingw/bin"

    # ---- 2c: mingwrt (host) ----
    # Tree was already extracted as a sibling in step 2 (w32api needs it).
    echo "[3/7] mingwrt (host=$HOST)"
    cd "$BUILD_DIR/mingw-mingwrt-host"
    ./configure \
        --build="$BUILD" --host="$HOST" \
        --prefix="$SYSROOT2" \
        CC="$HOST-gcc" CFLAGS="$HOST_CFLAGS" LDFLAGS="$HOST_LDFLAGS"
    make -j"$JOBS"
    make install

    # ---- 2d: GCC Stage 1 (host) ----
    echo "[4/7] GCC Stage 1 (host=$HOST, C only)"
    cd "$BUILD_DIR"
    rm -rf "gcc-${GCC_VER}-host"
    cp -r "$SOURCES_DIR/gcc-${GCC_VER}" "gcc-${GCC_VER}-host"
    # Ensure no in-tree deps (force external libraries)
    rm -rf "gcc-${GCC_VER}-host/gmp" "gcc-${GCC_VER}-host/mpfr" "gcc-${GCC_VER}-host/mpc" "gcc-${GCC_VER}-host/isl"
    mkdir -p "build-gcc-host-stage1"
    cd "build-gcc-host-stage1"
    # Force use of external libraries via environment
    export LIBRARY_PATH="$SYSROOT1/lib:$LIBRARY_PATH"
    export CPATH="$SYSROOT1/include:$CPATH"
    export PKG_CONFIG_PATH="$SYSROOT1/lib/pkgconfig:$PKG_CONFIG_PATH"
    "../gcc-${GCC_VER}-host/configure" \
        --build="$BUILD" --host="$HOST" --target="$TARGET" \
        --prefix="$STAGE2_PREFIX" \
        --with-sysroot="$SYSROOT2" \
        --enable-languages=c,c++ \
        --disable-nls --disable-multilib \
        --disable-libstdcxx-threads --disable-libstdcxx-pch \
        --disable-libgomp --disable-libmudflap --disable-libssp \
        --disable-libquadmath --disable-libquadmath-support \
        --disable-shared --enable-static \
        --enable-threads=win32 --enable-sjlj-exceptions --with-dwarf2 \
        --with-gnu-as --with-gnu-ld \
        --with-gmp="$SYSROOT1" --with-mpfr="$SYSROOT1" --with-mpc="$SYSROOT1" --with-isl="$SYSROOT1" \
        CC="$HOST-gcc" CXX="$HOST-g++" \
        CFLAGS="$HOST_CFLAGS" CXXFLAGS="$HOST_CXXFLAGS" LDFLAGS="$HOST_LDFLAGS" \
        CFLAGS_FOR_TARGET="$HOST_CFLAGS" CXXFLAGS_FOR_TARGET="$HOST_CXXFLAGS" LDFLAGS_FOR_TARGET="$HOST_LDFLAGS"
    make -j"$JOBS" all-gcc
    make install-gcc

    # ---- 2e: Rebuild mingwrt with Stage 2 GCC ----
    echo "[5/7] mingwrt rebuild with Stage 2 GCC"
    cd "$BUILD_DIR/mingw-mingwrt-host"
    make clean || true
    ./configure \
        --build="$BUILD" --host="$HOST" \
        --prefix="$SYSROOT2" \
        CC="$HOST-gcc" CFLAGS="$HOST_CFLAGS" LDFLAGS="$HOST_LDFLAGS"
    make -j"$JOBS"
    make install

    # ---- 2f: GCC Stage 2 (host, full) ----
    echo "[6/7] GCC Stage 2 (host=$HOST, full)"
    cd "$BUILD_DIR/build-gcc-host-stage1"
    # Ensure library paths for full build
    export LIBRARY_PATH="$SYSROOT1/lib:$LIBRARY_PATH"
    export CPATH="$SYSROOT1/include:$CPATH"
    export PKG_CONFIG_PATH="$SYSROOT1/lib/pkgconfig:$PKG_CONFIG_PATH"
    make -j"$JOBS" all
    make install

    # ---- 2g: zlib (host) ----
    echo "[7/7] zlib (host=$HOST)"
    cd "$BUILD_DIR"
    rm -rf "zlib-${ZLIB_VER}-host"
    tar -xf "$SOURCES_DIR/zlib-${ZLIB_VER}.tar.gz"
    mv "zlib-${ZLIB_VER}" "zlib-${ZLIB_VER}-host"
    cd "zlib-${ZLIB_VER}-host"
    CHOST="$HOST" ./configure --prefix="$SYSROOT2" --static \
        CC="$HOST-gcc" CFLAGS="$HOST_CFLAGS" LDFLAGS="$HOST_LDFLAGS"
    make -j"$JOBS"
    make install

    # ---- 2h: pthreads-w32 (host) ----
    echo "[+] pthreads-w32 (host=$HOST)"
    cd "$BUILD_DIR"
    rm -rf "pthreads-w32-host"
    tar -xf "$SOURCES_DIR/pthreads-w32-${PTHREADS_VER}.tar.gz"
    mv "pthreads-w32-${PTHREADS_VER//./-}-release" "pthreads-w32-host"
    cd "pthreads-w32-host"
    make -j"$JOBS" \
        CC="$HOST-gcc" AR="$HOST-ar" RC="$HOST-windres" DLLTOOL="$HOST-dlltool" \
        CROSS="$HOST-" GC=1 clean GC-static
    mkdir -p "$SYSROOT2/include" "$SYSROOT2/lib"
    cp pthread.h sched.h semaphore.h "$SYSROOT2/include/"
    cp libpthreadGC2.a "$SYSROOT2/lib/libpthread.a"

    # ---- 2i: make (host) ----
    echo "[+] make (host=$HOST)"
    cd "$BUILD_DIR"
    rm -rf "make-${MAKE_VER}-host"
    tar -xf "$SOURCES_DIR/make-${MAKE_VER}.tar.gz"
    mv "make-${MAKE_VER}" "make-${MAKE_VER}-host"
    cd "make-${MAKE_VER}-host"
    ./configure \
        --build="$BUILD" --host="$HOST" \
        --prefix="$STAGE2_PREFIX" \
        --disable-nls \
        CC="$HOST-gcc" CFLAGS="$HOST_CFLAGS" LDFLAGS="$HOST_LDFLAGS"
    make -j"$JOBS"
    make install

    echo "=== STAGE 2 COMPLETE ==="
    echo "Win9x-native toolchain at: $STAGE2_PREFIX"
}

# ============================================================
# MAIN
# ============================================================

case "${1:-all}" in
    stage1)
        build_stage1
        ;;
    stage2)
        # Ensure Stage 1 exists
        if [[ ! -f "$STAGE1_PREFIX/bin/$TARGET-gcc" ]]; then
            echo "Stage 1 not found. Run './build-canadian.sh stage1' first."
            exit 1
        fi
        build_stage2
        ;;
    all|"")
        build_stage1
        build_stage2
        ;;
    deps)
        # Build only host dependencies (requires Stage 1)
        if [[ ! -f "$STAGE1_PREFIX/bin/$TARGET-gcc" ]]; then
            echo "Stage 1 not found. Run './build-canadian.sh stage1' first."
            exit 1
        fi
        build_host_deps
        ;;
    *)
        echo "Usage: $0 [stage1|stage2|deps|all]"
        echo "  stage1 - Build cross-compiler (Linux → Win9x)"
        echo "  stage2 - Canadian Cross using Stage 1 (Win9x → Win9x)"
        echo "  deps   - Build HOST dependencies only (gmp, mpfr, mpc, isl, libiconv, gettext)"
        echo "  all    - Build everything (default)"
        exit 1
        ;;
esac

echo ""
echo "=== Build Complete ==="
echo "Stage 1 (Linux-hosted): $STAGE1_PREFIX"
echo "Stage 2 (Win9x-hosted): $STAGE2_PREFIX"
echo ""
echo "To use Stage 2 on Win9x:"
echo "  1. Copy $STAGE2_PREFIX to Win9x machine"
echo "  2. Add to PATH"
echo "  3. $HOST-gcc -march=i586 -mtune=pentium -DWINVER=0x0400 ..."