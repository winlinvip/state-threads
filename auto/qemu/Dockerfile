# The images of auto/qemu.sh, both built from this file, so the hash tag covers both.

# The amd64 image, built with --platform linux/amd64 --target amd64 when the Docker host is not amd64: the native
# g++ builds and runs x86_64, which Docker emulates as a whole container instead of qemu-x86_64 running each program.
FROM ubuntu:24.04 AS amd64

RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends make g++ \
    && rm -rf /var/lib/apt/lists/*

# The default image: cross compilers for every Linux CPU of ST, and qemu-user to run what they build.
# It runs natively on the CPU of the Docker host, arm64 or x86_64, and the native g++ builds that CPU.
FROM ubuntu:24.04 AS cross

RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        make g++ qemu-user \
        g++-x86-64-linux-gnu g++-aarch64-linux-gnu g++-i686-linux-gnu g++-arm-linux-gnueabihf \
        g++-riscv64-linux-gnu g++-14-loongarch64-linux-gnu \
        g++-mips-linux-gnu g++-mipsel-linux-gnu g++-mips64-linux-gnuabi64 g++-mips64el-linux-gnuabi64 \
    && rm -rf /var/lib/apt/lists/*
