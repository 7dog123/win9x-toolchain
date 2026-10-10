#!/bin/bash
# test-canadian.sh - Test the Canadian Cross Win9x-hosted toolchain
# Run on a Win9x machine (or via Wine/QEMU) after copying stage2 there

set -euo pipefail

# This script is meant to run ON the Win9x target machine
# after copying the stage2 toolchain there.

TOOLCHAIN_ROOT="${1:-/mingw}"
TARGET=i586-w64-mingw32

export PATH="$TOOLCHAIN_ROOT/bin:$PATH"

echo "=== Testing Canadian Cross Win9x-hosted Toolchain ==="
echo "Toolchain root: $TOOLCHAIN_ROOT"
echo ""

# Test 1: Basic compiler functionality
echo "--- Test 1: Compiler versions ---"
$TARGET-gcc --version | head -1
$TARGET-g++ --version | head -1
$TARGET-ld --version | head -1
$TARGET-as --version | head -1

# Test 2: Target triplet
echo "--- Test 2: Target triplet ---"
$TARGET-gcc -dumpmachine

# Test 3: Search paths
echo "--- Test 3: Search paths ---"
$TARGET-gcc -print-search-dirs

# Test 4: Simple C program
echo "--- Test 4: Hello Win95 (C) ---"
cat > /tmp/test1.c << 'EOF'
#include <windows.h>
#include <stdio.h>

int main() {
    OSVERSIONINFO vi = { sizeof(vi) };
    GetVersionEx(&vi);
    printf("Running on Windows %d.%d build %d\n", vi.dwMajorVersion, vi.dwMinorVersion, vi.dwBuildNumber);
    printf("WINVER=0x%04X _WIN32_WINNT=0x%04X\n", WINVER, _WIN32_WINNT);
    return 0;
}
EOF

$TARGET-gcc -march=i586 -mtune=pentium \
    -DWINVER=0x0400 -D_WIN32_WINNT=0x0400 -D_WIN32_WINDOWS=0x0410 \
    -o /tmp/test1.exe /tmp/test1.c

echo "Binary:"
file /tmp/test1.exe
$TARGET-objdump -p /tmp/test1.exe | grep -A2 "DLL Name"

# Test 5: C++ program
echo "--- Test 5: C++ program ---"
cat > /tmp/test2.cpp << 'EOF'
#include <windows.h>
#include <iostream>
#include <string>
#include <vector>

int main() {
    std::vector<int> v = {1, 2, 3, 4, 5};
    int sum = 0;
    for (int x : v) sum += x;
    std::cout << "C++ STL works! Sum = " << sum << std::endl;
    return 0;
}
EOF

$TARGET-g++ -march=i586 -mtune=pentium \
    -DWINVER=0x0400 -D_WIN32_WINNT=0x0400 -D_WIN32_WINDOWS=0x0410 \
    -static-libgcc -static-libstdc++ \
    -o /tmp/test2.exe /tmp/test2.cpp

echo "Binary:"
file /tmp/test2.exe

# Test 6: pthreads
echo "--- Test 6: pthreads ---"
cat > /tmp/test3.c << 'EOF'
#include <windows.h>
#include <pthread.h>
#include <stdio.h>

void* worker(void* arg) {
    int id = *(int*)arg;
    printf("Thread %d running\n", id);
    Sleep(50);
    return (void*)(long)(id * 2);
}

int main() {
    pthread_t threads[4];
    int ids[4] = {1, 2, 3, 4};
    void* results[4];

    printf("Creating 4 threads...\n");
    for (int i = 0; i < 4; i++) {
        pthread_create(&threads[i], NULL, worker, &ids[i]);
    }
    for (int i = 0; i < 4; i++) {
        pthread_join(threads[i], &results[i]);
        printf("Thread %d returned %ld\n", ids[i], (long)results[i]);
    }
    printf("All threads done\n");
    return 0;
}
EOF

$TARGET-gcc -march=i586 -mtune=pentium \
    -DWINVER=0x0400 -D_WIN32_WINNT=0x0400 -D_WIN32_WINDOWS=0x0410 \
    -o /tmp/test3.exe /tmp/test3.c -lpthread

echo "Binary:"
file /tmp/test3.exe
$TARGET-objdump -p /tmp/test3.exe | grep -A2 "DLL Name"

# Test 7: Import analysis (critical for Win95 compat)
echo "--- Test 7: Import analysis (Win95 compatibility) ---"
for exe in /tmp/test1.exe /tmp/test2.exe /tmp/test3.exe; do
    echo "Checking $exe:"
    $TARGET-objdump -p "$exe" | sed -n '/DLL Name: KERNEL32.dll/,/DLL Name:/p' | grep "^\s\+[0-9a-f]\+" | head -20
done

# Test 8: Check for forbidden imports
echo "--- Test 8: Forbidden imports check ---"
BAD_IMPORTS="InterlockedCompareExchange EncodePointer DecodePointer InitializeCriticalSectionAndSpinCount SetCriticalSectionSpinCount GetTickCount64 GetSystemTimePreciseAsFileTime WaitOnAddress InitializeCriticalSectionEx"

for exe in /tmp/test1.exe /tmp/test2.exe /tmp/test3.exe; do
    echo "Scanning $exe for bad imports..."
    for bad in $BAD_IMPORTS; do
        if $TARGET-objdump -p "$exe" | grep -q "$bad"; then
            echo "  ❌ FOUND: $bad"
        fi
    done
done

# Test 9: Static linking verification
echo "--- Test 9: Static linking check ---"
for exe in /tmp/test1.exe /tmp/test2.exe /tmp/test3.exe; do
    echo "$exe DLL dependencies:"
    $TARGET-objdump -p "$exe" | grep "DLL Name:" | awk '{print "  " $3}'
done

echo ""
echo "=== All tests completed ==="
echo "If no forbidden imports found, toolchain is Win95-compatible!"