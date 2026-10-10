# Multi-stage Dockerfile for Win9x Cross-Compiler
# Stage 1: Build using build-win9x.sh
# Stage 2: Minimal runtime with toolchain + make (via apt)

# ============================================================
# STAGE 1: BUILDER
# ============================================================
FROM debian:stretch AS builder

ENV DEBIAN_FRONTEND=noninteractive

# Build dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    wget curl ca-certificates \
    xz-utils bzip2 gzip tar \
    make gcc g++ binutils \
    flex bison texinfo gawk patch diffutils file \
    libtool autoconf automake \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /workspace

# Copy build script
COPY build-win9x.sh fetch-sources.sh versions.txt ./
RUN chmod +x build-win9x.sh fetch-sources.sh

# Fetch sources then build
RUN ./fetch-sources.sh && ./build-win9x.sh

# ============================================================
# STAGE 2: RUNTIME
# ============================================================
FROM debian:stretch-slim AS runtime

ENV DEBIAN_FRONTEND=noninteractive

# Install runtime deps: wine32 (to run Win9x binaries on Linux) + make (for building on Linux)
RUN apt-get update && apt-get install -y --no-install-recommends \
    wine32 \
    make \
    && rm -rf /var/lib/apt/lists/*

# Copy toolchain from builder
COPY --from=builder /workspace/toolchain /opt/win9x-toolchain

# Set up environment
ENV PATH="/opt/win9x-toolchain/bin:${PATH}"
ENV TARGET=i586-w64-mingw32

WORKDIR /workspace

# Default: show version
CMD ["i586-w64-mingw32-gcc", "--version"]