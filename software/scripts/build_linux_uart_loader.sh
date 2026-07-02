#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BUILD_DIR="${BUILD_DIR:-$ROOT/build/software/linux-uart-loader}"
CROSS_COMPILE="${CROSS_COMPILE:-riscv64-unknown-elf-}"
PYTHON="${PYTHON:-python3}"

make -C "$ROOT/software/firmware/linux-uart-loader" \
    BUILD_DIR="$BUILD_DIR" \
    CROSS_COMPILE="$CROSS_COMPILE" \
    PYTHON="$PYTHON"

echo "Boot ROM hex: $BUILD_DIR/boot_rom.hex"
echo "Boot RAM hex: $BUILD_DIR/boot_ram.hex"
