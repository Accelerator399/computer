#!/usr/bin/env python3
"""Convert binary images into 128-bit DDR preload lines.

Each input image is provided as:

    path/to/file.bin@0x00000000

The output is a simple text format with one line per populated 16-byte DDR line:

    00000000 00112233445566778899aabbccddeeff

The hex payload is written in big-endian display order, matching the way the
existing testbenches print 128-bit DDR lines.  The parser in the new Linux boot
testbench can use this format directly.
"""

from __future__ import annotations

import argparse
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, Iterable, List, Tuple


@dataclass
class Segment:
    path: Path
    base: int


def parse_segment(spec: str) -> Segment:
    if "@" not in spec:
        raise ValueError(f"segment must be path@address, got: {spec}")
    path_str, addr_str = spec.rsplit("@", 1)
    path = Path(path_str)
    if not path.is_file():
        raise FileNotFoundError(path)
    base = int(addr_str, 0)
    if base < 0:
        raise ValueError("base address must be non-negative")
    return Segment(path=path, base=base)


def load_bytes(seg: Segment) -> Iterable[Tuple[int, int]]:
    data = seg.path.read_bytes()
    for offset, byte in enumerate(data):
        yield seg.base + offset, byte


def build_lines(segments: List[Segment]) -> Dict[int, bytearray]:
    lines: Dict[int, bytearray] = {}
    for seg in segments:
        for addr, byte in load_bytes(seg):
            line_base = addr & ~0xF
            line = lines.setdefault(line_base, bytearray([0] * 16))
            line[addr & 0xF] = byte
    return lines


def line_to_hex(line: bytearray) -> str:
    return "".join(f"{b:02x}" for b in reversed(line))


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--image",
        action="append",
        required=True,
        help="Binary image spec in the form path@base_address. Can be repeated.",
    )
    parser.add_argument(
        "--output",
        required=True,
        help="Output preload file path.",
    )
    args = parser.parse_args()

    segments = [parse_segment(spec) for spec in args.image]
    lines = build_lines(segments)

    out_path = Path(args.output)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    with out_path.open("w", encoding="ascii", newline="\n") as fh:
        for base in sorted(lines):
            fh.write(f"{base:08x} {line_to_hex(lines[base])}\n")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
