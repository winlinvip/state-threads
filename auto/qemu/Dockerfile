# The images of auto/qemu.sh, all built from this file, so the hash tag covers them.

# The amd64 image, built with --platform linux/amd64 --target amd64 when the Docker host is not amd64: the native
# g++ builds and runs x86_64, which Docker emulates as a whole container instead of qemu-x86_64 running each program.
FROM ubuntu:24.04 AS amd64

RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends make g++ \
    && rm -rf /var/lib/apt/lists/*

# A newer qemu-user than Ubuntu 24.04 has, 10.2 instead of 8.2. Its binaries are statically linked, so the cross
# image below takes only them, and keeps the cross compilers of Ubuntu 24.04.
FROM ubuntu:26.04 AS qemu

RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends qemu-user \
    && rm -rf /var/lib/apt/lists/*

# The default image: cross compilers for every Linux CPU of ST, and qemu-user to run what they build.
# It runs natively on the CPU of the Docker host, arm64 or x86_64, and the native g++ builds that CPU.
FROM ubuntu:24.04 AS cross

RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        make g++ \
        g++-x86-64-linux-gnu g++-aarch64-linux-gnu g++-i686-linux-gnu g++-arm-linux-gnueabihf \
        g++-riscv64-linux-gnu g++-14-loongarch64-linux-gnu \
        g++-mips-linux-gnu g++-mipsel-linux-gnu g++-mips64-linux-gnuabi64 g++-mips64el-linux-gnuabi64 \
    && rm -rf /var/lib/apt/lists/*

# gdb-multiarch, to debug any CPU through the gdb stub of qemu-<cpu> -g <port>. A layer of its own, so the cross
# compilers above stay cached.
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends gdb-multiarch \
    && rm -rf /var/lib/apt/lists/*

# qemu-user for every CPU of auto/qemu.sh, x86_64 and aarch64 too, for the shell and the gdb stub.
COPY --from=qemu /usr/bin/qemu-x86_64 /usr/bin/qemu-aarch64 /usr/bin/qemu-i386 /usr/bin/qemu-arm \
    /usr/bin/qemu-riscv64 /usr/bin/qemu-loongarch64 /usr/bin/qemu-mips /usr/bin/qemu-mipsel \
    /usr/bin/qemu-mips64 /usr/bin/qemu-mips64el /usr/bin/
