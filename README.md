# Win9x Cross-Compiler Toolchain

Builds a Linux-hosted cross-compiler targeting **Windows 95 / 98 / ME** (i586/Pentium class).

## Versions Used

| Component | Version | Source | Win95 Support |
|-----------|---------|--------|---------------|
| binutils  | 2.28    | GNU    | Last MinGW.org release |
| gcc       | 6.3.0   | GNU    | Last MinGW.org release |
| mingwrt   | 5.0.2   | mingw-w32 | Bug #2357 fix for Win95/NT3.51 |
| w32api    | 5.0.2   | mingw-w32 | Requires `-DWINVER=0x0400` |
| pthreads  | 2.9.1   | sourceware | MinGW build `pthreadGC2.dll` works on Win95 |

See `versions.txt` for full details and URLs.

## Quick Start (Docker)

```bash
# Build the Docker image
docker build -t win9x-toolchain .

# Run the build (outputs to ./toolchain)
docker run --rm -v $(pwd):/workspace win9x-toolchain
```

## Manual Build (Debian 9 / Ubuntu 18.04+)

```bash
# Install dependencies
sudo apt-get install build-essential wget xz-utils bzip2 \
    libgmp-dev libmpfr-dev libmpc-dev libisl-dev zlib1g-dev \
    flex bison texinfo gawk patch diffutils

# Fetch sources
./fetch-sources.sh

# Build toolchain (takes 30-60 minutes)
./build-win9x.sh

# Test
./test-toolchain.sh
```

## Output Structure

After build completes:

```
toolchain/
├── bin/                    # Cross-compiler binaries
│   ├── i586-w64-mingw32-gcc
│   ├── i586-w64-mingw32-g++
│   ├── i586-w64-mingw32-ld
│   ├── i586-w64-mingw32-as
│   └── ...
├── i586-w64-mingw32/       # Sysroot (target libraries/headers)
│   ├── include/            # w32api headers
│   ├── lib/                # mingwrt, libgcc, libstdc++, pthreads
│   └── bin/                # pthreadGC2.dll (runtime)
└── lib/gcc/i586-w64-mingw32/6.3.0/
```

## Using the Cross-Compiler

```bash
export PATH="/path/to/toolchain/bin:$PATH"

# C program for Win95
i586-w64-mingw32-gcc -march=i586 -mtune=pentium \
    -DWINVER=0x0400 -D_WIN32_WINNT=0x0400 -D_WIN32_WINDOWS=0x0410 \
    -o myapp.exe myapp.c

# C++ program (static runtime for deployment)
i586-w64-mingw32-g++ -march=i586 -mtune=pentium \
    -DWINVER=0x0400 -D_WIN32_WINNT=0x0400 -D_WIN32_WINDOWS=0x0410 \
    -static-libgcc -static-libstdc++ \
    -o myapp.exe myapp.cpp

# With pthreads
i586-w64-mingw32-gcc -march=i586 -mtune=pentium \
    -DWINVER=0x0400 -D_WIN32_WINNT=0x0400 \
    -o myapp.exe myapp.c -lpthread
```

### Required Compiler Flags for Win95 Compatibility

| Flag | Purpose |
|------|---------|
| `-march=i586 -mtune=pentium` | Generate Pentium-compatible code (no CMOV/SSE) |
| `-DWINVER=0x0400` | Target Windows 95 API |
| `-D_WIN32_WINNT=0x0400` | Target NT 4.0 / Win95 API subset |
| `-D_WIN32_WINDOWS=0x0410` | Also enable Win98 APIs |
| `-static-libgcc -static-libstdc++` | Avoid GCC runtime DLL dependencies |

### Win95 Runtime Requirements

Deployed executables need on the target Win95 machine:
- **MSVCRT.DLL** ≥ 6.00.8797 (from VC6 redist or Win2K update)
- **COMCTL32.DLL** ≥ 5.80 (common controls)
- **WINSOCK2** update (for socket apps)

## Known Limitations

1. **No winpthreads** — Uses native Win32 threads (`--enable-threads=win32`). `std::thread`/`std::mutex` from C++11 **not available**.
2. **No C++11 `<thread>`, `<mutex>`, `<chrono>`** — Use Win32 APIs (`CreateThread`, `WaitForSingleObject`, `CRITICAL_SECTION`) or pthreads-w32 API directly.
3. **libstdc++** — Built without threading support; some `<atomic>` operations may be slow.
4. **w32api 5.0.2** defaults to Win2K — Always pass `-DWINVER=0x0400` explicitly.
5. **64-bit not supported** — Toolchain is 32-bit only (i586 target).

## Verifying Win95 Compatibility

Check that generated EXE doesn't import unavailable APIs:

```bash
i586-w64-mingw32-objdump -p myapp.exe | grep -A20 "DLL Name: KERNEL32.dll"
```

**Must NOT see:** `InterlockedCompareExchange`, `EncodePointer`, `DecodePointer`, `InitializeCriticalSectionAndSpinCount`, `SetCriticalSectionSpinCount`, `GetTickCount64`, `GetSystemTimePreciseAsFileTime`, `WaitOnAddress`, `InitializeCriticalSectionEx`

**Should see only:** Classic Win95 kernel32 APIs (`CreateThread`, `CreateEvent`, `CreateSemaphore`, `InitializeCriticalSection`, `EnterCriticalSection`, `WaitForSingleObject`, `Sleep`, `TlsAlloc`, `VirtualAlloc`, etc.)

## Troubleshooting

### "InterlockedCompareExchange" import error on Win95
- Ensure `-march=i586` (not i686) — i686 enables CMOV which requires Pentium Pro+
- Ensure pthreads-w32 2.9.1 MinGW build is used (not MSVC build)

### "Illegal Instruction" on Pentium
- Remove any `-msse`, `-msse2`, `-mfpmath=sse` flags
- Use `-march=i586 -mtune=pentium`

### wxWidgets / GUI apps fail
- Link with `-mwindows` flag
- Ensure COMCTL32.DLL 5.80+ is installed on target
- Use `-DWINVER=0x0400` before including windows.h

### C++ static linking bloats binary
- Use `-Os -ffunction-sections -fdata-sections -Wl,--gc-sections`
- Strip with `i586-w64-mingw32-strip --strip-all myapp.exe`

## License

Toolchain components retain their original licenses:
- binutils: GPL-3.0+
- gcc: GPL-3.0+ with GCC Runtime Library Exception
- mingwrt/w32api: Public domain / ZPL / LGPL
- pthreads-w32: LGPL-2.1 / Apache-2.0

This build script is public domain.