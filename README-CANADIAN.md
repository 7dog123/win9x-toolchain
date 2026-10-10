# Canadian Cross Build: Linux → Win9x → Win9x

Produces a **complete Win9x-hosted toolchain** — a compiler that **runs on Windows 95/98/ME** and **targets Windows 95/98/ME**.

## What is Canadian Cross?

| Stage | Build Platform | Host Platform | Target Platform | Produces |
|-------|---------------|---------------|-----------------|----------|
| **Stage 1** | Linux (x86_64) | Linux (x86_64) | Win9x (i586) | Cross-compiler running on Linux |
| **Stage 2** | Linux (x86_64) | **Win9x (i586)** | Win9x (i586) | **Native Win9x toolchain** |

Stage 2 binaries are **Win9x executables** built *using* the Stage 1 cross-compiler.

## Quick Start (Docker)

```bash
# Build the Docker image
docker build -f Dockerfile.canadian -t win9x-canadian .

# Run the full build (takes 2-4 hours)
docker run --rm -v $(pwd):/workspace win9x-canadian

# Output: ./toolchain-canadian/stage2/  ← Copy this to Win9x machine
```

## Manual Build (Debian 9 / Ubuntu 18.04+)

```bash
# Install build dependencies
sudo apt-get install build-essential wget xz-utils bzip2 \
    libgmp-dev libmpfr-dev libmpc-dev libisl-dev zlib1g-dev \
    flex bison texinfo gawk patch diffutils libtool autoconf automake

# Fetch all sources
./fetch-canadian.sh

# Build Stage 1 (cross-compiler Linux → Win9x)
./build-canadian.sh stage1

# Build Stage 2 (Canadian Cross: Win9x → Win9x)
./build-canadian.sh stage2
```

## Output Structure

```
toolchain-canadian/
├── stage1/                    # Linux-hosted cross-compiler
│   ├── bin/
│   │   ├── i586-w64-mingw32-gcc
│   │   └── ...
│   └── i586-w64-mingw32/      # Sysroot for Stage 1
│       ├── include/
│       ├── lib/
│       └── bin/               # pthreadGC2.dll
│
├── stage2/                    # ★ Win9x-hosted toolchain (copy this to Win9x)
│   ├── bin/
│   │   ├── i586-w64-mingw32-gcc.exe
│   │   ├── i586-w64-mingw32-g++.exe
│   │   ├── i586-w64-mingw32-ld.exe
│   │   ├── i586-w64-mingw32-as.exe
│   │   ├── i586-w64-mingw32-windres.exe
│   │   └── i586-w64-mingw32-dlltool.exe
│   └── i586-w64-mingw32/      # Sysroot for Stage 2
│       ├── include/           # w32api headers
│       ├── lib/               # mingwrt, libgcc, libstdc++, pthreads, gmp, mpfr, mpc, isl, libiconv, gettext
│       └── bin/               # pthreadGC2.dll (runtime)
│
└── build-canadian/            # Build artifacts
```

## Deploying to Win9x

```bash
# On Linux (after build):
tar -czf win9x-toolchain.tar.gz -C toolchain-canadian stage2

# Transfer to Win9x machine (floppy, CD, network, VM shared folder)
# On Win9x:
cd C:\
tar -xzf win9x-toolchain.tar.gz
# Or extract ZIP if using 7-Zip on Win9x

# Set up environment (autoexec.bat or command prompt):
SET PATH=C:\stage2\bin;%PATH%
```

## Using on Win9x

```cmd
REM In Win9x command prompt:
C:\stage2\bin\i586-w64-mingw32-gcc -v

REM Compile C program:
i586-w64-mingw32-gcc -march=i586 -mtune=pentium ^
    -DWINVER=0x0400 -D_WIN32_WINNT=0x0400 -D_WIN32_WINDOWS=0x0410 ^
    -o myapp.exe myapp.c

REM Compile C++ program (static runtime):
i586-w64-mingw32-g++ -march=i586 -mtune=pentium ^
    -DWINVER=0x0400 -D_WIN32_WINNT=0x0400 -D_WIN32_WINDOWS=0x0410 ^
    -static-libgcc -static-libstdc++ ^
    -o myapp.exe myapp.cpp

REM With pthreads:
i586-w64-mingw32-gcc -march=i586 -mtune=pentium ^
    -DWINVER=0x0400 -D_WIN32_WINNT=0x0400 ^
    -o myapp.exe myapp.c -lpthread
```

## Required Flags for Win95 Compatibility

| Flag | Purpose |
|------|---------|
| `-march=i586 -mtune=pentium` | Pentium-compatible code (no CMOV, no SSE) |
| `-DWINVER=0x0400` | Windows 95 API |
| `-D_WIN32_WINNT=0x0400` | NT 4.0 / Win95 API subset |
| `-D_WIN32_WINDOWS=0x0410` | Also enable Win98 APIs |
| `-static-libgcc -static-libstdc++` | Avoid runtime DLL dependencies |

## Dependencies Built for Host (Stage 2 Sysroot)

All built **statically** for `i586-w64-mingw32`:

| Library | Version | Purpose |
|---------|---------|---------|
| gmp | 6.2.1 | Arbitrary precision arithmetic |
| mpfr | 4.1.0 | Multiple-precision floating-point |
| mpc | 1.2.1 | Complex numbers |
| isl | 0.24 | Integer set library (loop optimizations) |
| libiconv | 1.16 | Character encoding conversion |
| gettext | 0.21 | Internationalization (libintl) |
| zlib | 1.2.13 | Compression |
| pthreads-w32 | 2.9.1 | POSIX threads (pthreadGC2.dll) |
| mingwrt | 5.0.2 | MinGW runtime (CRT) |
| w32api | 5.0.2 | Windows API headers/import libs |

## Verifying Win95 Compatibility

On Win9x (or via Wine), run:

```bash
./test-canadian.sh C:\stage2
```

Or manually check imports:

```cmd
i586-w64-mingw32-objdump -p myapp.exe | find "DLL Name"
```

**Must NOT see these KERNEL32 imports:**
- `InterlockedCompareExchange`
- `EncodePointer` / `DecodePointer`
- `InitializeCriticalSectionAndSpinCount`
- `SetCriticalSectionSpinCount`
- `GetTickCount64`
- `GetSystemTimePreciseAsFileTime`
- `WaitOnAddress`
- `InitializeCriticalSectionEx`

## Known Limitations

1. **No C++11 `<thread>`/`<mutex>`/`<chrono>`** — Use Win32 APIs or pthreads-w32 directly
2. **No `std::filesystem`** — Not available in GCC 6.3.0
3. **Static linking only** — Dynamic GCC runtime (`libgcc_s_sjlj-1.dll`) not built
4. **32-bit only** — i586 target, no 64-bit support
5. **Win95 hardware minimum** — Requires Pentium (i586) or later

## Build Time Estimates (on modern hardware)

| Phase | Time |
|-------|------|
| Stage 1 (cross-compiler) | 30-60 min |
| Host dependencies (gmp, mpfr, mpc, isl, libiconv, gettext) | 20-40 min |
| Stage 2 (Canadian Cross) | 60-120 min |
| **Total** | **2-4 hours** |

## Troubleshooting

### "InterlockedCompareExchange" import error
- Ensure `-march=i586` (not i686) — i686 enables CMOV
- Verify pthreads-w32 2.9.1 MinGW build is used (not MSVC build)

### "Illegal Instruction" on Pentium
- Remove `-msse`, `-msse2`, `-mfpmath=sse` flags
- Confirm `-march=i586 -mtune=pentium`

### Build fails with "out of memory" (on actual Win9x)
- Not applicable — we build on Linux with Canadian Cross
- If testing natively on Win9x, use swap file and limit `-j1`

### `libiconv` / `gettext` configure errors
- Ensure Stage 1 cross-compiler is in PATH before building deps
- Check `config.log` for missing headers

## License

Toolchain components retain original licenses:
- binutils, gcc, gmp, mpfr, mpc, isl, libiconv, gettext: GPL/LGPL
- mingwrt, w32api: Public domain / ZPL / LGPL
- pthreads-w32: LGPL-2.1 / Apache-2.0
- zlib: zlib license

Build scripts: Public domain.