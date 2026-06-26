#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BUILD_DIR="${BUILD_DIR:-$ROOT/build/software}"
FW_BUILD_DIR="${FW_BUILD_DIR:-$BUILD_DIR/opensbi-lite}"
DTB_OUT="${DTB_OUT:-$BUILD_DIR/computer-rv32.dtb}"
PRELOAD_OUT="${PRELOAD_OUT:-$ROOT/software/image/linux_preload.memh}"

FW_ADDR="${FW_ADDR:-0x00000000}"
LINUX_ADDR="${LINUX_ADDR:-0x00400000}"
DTB_ADDR="${DTB_ADDR:-0x00800000}"
LINUX_IMAGE="${LINUX_IMAGE:-}"

DTC="${DTC:-dtc}"
PYTHON="${PYTHON:-python3}"

mkdir -p "$BUILD_DIR" "$(dirname "$PRELOAD_OUT")"

make -C "$ROOT/software/firmware/opensbi-lite" \
    BUILD_DIR="$FW_BUILD_DIR" \
    FW_BASE="$FW_ADDR" \
    LINUX_ENTRY="$LINUX_ADDR" \
    DTB_ADDR="$DTB_ADDR"

"$DTC" -I dts -O dtb -o "$DTB_OUT" "$ROOT/software/dts/computer-rv32.dts"

images=(
    --image "$FW_BUILD_DIR/fw_jump.bin@$FW_ADDR"
    --image "$DTB_OUT@$DTB_ADDR"
)

if [[ -n "$LINUX_IMAGE" ]]; then
    images+=(--image "$LINUX_IMAGE@$LINUX_ADDR")
else
    echo "WARN: LINUX_IMAGE is not set; preload will contain firmware and DTB only." >&2
fi

"$PYTHON" "$ROOT/software/scripts/bin_to_ddr_preload.py" \
    "${images[@]}" \
    --output "$PRELOAD_OUT"

echo "Firmware : $FW_BUILD_DIR/fw_jump.bin"
echo "DTB      : $DTB_OUT"
echo "Preload  : $PRELOAD_OUT"
