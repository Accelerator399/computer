#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BUILD_DIR="${BUILD_DIR:-$ROOT/build/software}"
FW_BUILD_DIR="${FW_BUILD_DIR:-$BUILD_DIR/opensbi-lite}"
SMOKE_BUILD_DIR="${SMOKE_BUILD_DIR:-$BUILD_DIR/linux-smoke}"
DTB_OUT="${DTB_OUT:-$BUILD_DIR/computer-rv32.dtb}"
PRELOAD_OUT="${PRELOAD_OUT:-$ROOT/software/image/linux_smoke_preload.memh}"

FW_ADDR="${FW_ADDR:-0x00000000}"
LINUX_ADDR="${LINUX_ADDR:-0x00400000}"
DTB_ADDR="${DTB_ADDR:-0x00800000}"

DTC="${DTC:-dtc}"
PYTHON="${PYTHON:-python3}"

mkdir -p "$BUILD_DIR" "$(dirname "$PRELOAD_OUT")"

make -C "$ROOT/software/firmware/opensbi-lite" \
    BUILD_DIR="$FW_BUILD_DIR" \
    FW_BASE="$FW_ADDR" \
    LINUX_ENTRY="$LINUX_ADDR" \
    DTB_ADDR="$DTB_ADDR"

make -C "$ROOT/software/firmware/linux-smoke" \
    BUILD_DIR="$SMOKE_BUILD_DIR" \
    PAYLOAD_BASE="$LINUX_ADDR" \
    DTB_ADDR="$DTB_ADDR"

"$DTC" -I dts -O dtb -o "$DTB_OUT" "$ROOT/software/dts/computer-rv32.dts"

"$PYTHON" "$ROOT/software/scripts/bin_to_ddr_preload.py" \
    --image "$FW_BUILD_DIR/fw_jump.bin@$FW_ADDR" \
    --image "$SMOKE_BUILD_DIR/linux_smoke.bin@$LINUX_ADDR" \
    --image "$DTB_OUT@$DTB_ADDR" \
    --output "$PRELOAD_OUT"

echo "Firmware      : $FW_BUILD_DIR/fw_jump.bin"
echo "S-mode smoke  : $SMOKE_BUILD_DIR/linux_smoke.bin"
echo "DTB           : $DTB_OUT"
echo "Preload       : $PRELOAD_OUT"
