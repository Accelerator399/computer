#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BUILD_DIR="${BUILD_DIR:-$ROOT/build/software/fwok-smoke}"
PRELOAD_OUT="${PRELOAD_OUT:-$ROOT/software/image/fwok_smoke_preload.memh}"
FW_ADDR="${FW_ADDR:-0x00000000}"
PYTHON="${PYTHON:-python3}"

mkdir -p "$(dirname "$PRELOAD_OUT")"

make -C "$ROOT/software/firmware/fwok-smoke" \
    BUILD_DIR="$BUILD_DIR" \
    FW_BASE="$FW_ADDR"

"$PYTHON" "$ROOT/software/scripts/bin_to_ddr_preload.py" \
    --image "$BUILD_DIR/fwok_smoke.bin@$FW_ADDR" \
    --output "$PRELOAD_OUT"

echo "FWOK firmware : $BUILD_DIR/fwok_smoke.bin"
echo "Preload       : $PRELOAD_OUT"
