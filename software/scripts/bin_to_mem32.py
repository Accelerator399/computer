#!/usr/bin/env python3
"""Convert a little-endian binary blob to one 32-bit $readmemh word per line."""

from __future__ import annotations

import argparse
from pathlib import Path


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()

    data = bytearray(args.input.read_bytes())
    while len(data) % 4:
        data.append(0)

    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("w", encoding="ascii", newline="\n") as fh:
        for offset in range(0, len(data), 4):
            word = int.from_bytes(data[offset : offset + 4], "little")
            fh.write(f"{word:08x}\n")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
