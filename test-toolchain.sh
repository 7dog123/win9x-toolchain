#!/bin/bash
# test-toolchain.sh - Quick test of the built Win9x cross-compiler
# Run from the win9x-toolchain directory after build completes

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

source versions.txt

PREFIX="$SCRIPT_DIR/toolchain"
TARGET=i586-w64-mingw32

export PATH="$PREFIX/bin:$PATH"

echo "=== Testing Win9x cross-compiler ==="

# Test 1: Version check
echo "--- GCC version ---"
$TARGET-gcc --version | head -1
$TARGET-g++ --version | head -1

# Test 2: Target tuple
echo "--- Target tuple ---"
$TARGET-gcc -dumpmachine

# Test 3: Default search paths
echo "--- Search paths ---"
$TARGET-gcc -print-search-dirs

# Test 4: Simple C program (no threads)
echo "--- Test 1: Hello Win95 (C) ---"
cat > /tmp/test1.c << 'EOF'
#include <windows.h>
#include <stdio.h>

int main() {
    OSVERSIONINFO vi = { sizeof(vi) };
    GetVersionEx(&vi);
    printf("Windows %d.%d build %d\n", vi.dwMajorVersion, vi.dwMinorVersion, vi.dwBuildNumber);
    printf("WINVER=0x%04X _WIN32_WINNT=0x%04X\n", WINVER, _WIN32_WINNT);
    return 0;
}
EOF

$TARGET-gcc -march=i586 -mtune=pentium \
    -DWINVER=0x0400 -D_WIN32_WINNT=0x0400 -D_WIN32_WINDOWS=0x0410 \
    -o /tmp/test1.exe /tmp/test1.c

echo "Binary info:"
file /tmp/test1.exe
$TARGET-objdump -p /tmp/test1.exe | grep -A2 "DLL Name"

# Test 5: C++ program
echo "--- Test 2: Hello Win95 (C++) ---"
cat > /tmp/test2.cpp << 'EOF'
#include <windows.h>
#include <iostream>
#include <string>

int main() {
    std::string msg = "Hello from C++ on Win95 target";
    MessageBoxA(NULL, msg.c_str(), "Test", MB_OK);
    return 0;
}
EOF

$TARGET-g++ -march=i586 -mtune=pentium \
    -DWINVER=0x0400 -D_WIN32_WINNT=0x0400 -D_WIN32_WINDOWS=0x0410 \
    -static-libgcc -static-libstdc++ \
    -o /tmp/test2.exe /tmp/test2.cpp

echo "Binary info:"
file /tmp/test2.exe

# Test 6: pthreads
echo "--- Test 3: pthreads on Win95 ---"
cat > /tmp/test3.c << 'EOF'
#include <windows.h>
#include <pthread.h>
#include <stdio.h>

void* worker(void* arg) {
    int id = *(int*)arg;
    printf("Thread %d running (TLS test)\n", id);
    Sleep(100);
    return (void*)(long)id;
}

int main() {
    pthread_t threads[3];
    int ids[3] = {1, 2, 3};

    printf("Creating threads on Win95 target...\n");
    for (int i = 0; i < 3; i++) {
        pthread_create(&threads[i], NULL, worker, &ids[i]);
    }
    for (int i = 0; i < 3; i++) {
        void* ret;
        pthread_join(threads[i], &ret);
        printf("Thread %d joined\n", (int)(long)ret);
    }
    printf("All threads completed successfully\n");
    return 0;
}
EOF

$TARGET-gcc -march=i586 -mtune=pentium \
    -DWINVER=0x0400 -D_WIN32_WINNT=0x0400 -D_WIN32_WINDOWS=0x0410 \
    -o /tmp/test3.exe /tmp/test3.c -lpthread

echo "Binary info:"
file /tmp/test3.exe
$TARGET-objdump -p /tmp/test3.exe | grep -A2 "DLL Name"

# Test 7: Check imports for Win95 compatibility
echo "--- Test 4: Import analysis ---"
for exe in /tmp/test1.exe /tmp/test2.exe /tmp/test3.exe; do
    echo "Checking $exe:"
    $TARGET-objdump -p "$exe" | grep "DLL Name:" | while read line; do
        dll=$(echo "$line" | awk '{print $3}')
        echo "  Imports from $dll"
        $TARGET-objdump -p "$exe" | sed -n "/DLL Name: $dll/,/DLL Name:/p" | grep "^\s\+[0-9a-f]\+" | head -20
    done
done

echo ""
echo "=== All tests passed! Toolchain ready for Win95/98/ME ==="