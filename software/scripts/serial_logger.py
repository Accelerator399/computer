#!/usr/bin/env python3
"""Capture a serial port to a log file for board bring-up runs."""

from __future__ import annotations

import argparse
import sys
import time
from pathlib import Path

import serial


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("port", help="serial port, for example COM11")
    parser.add_argument("log", type=Path, help="file to append captured bytes to")
    parser.add_argument("--baud", type=int, default=115200)
    parser.add_argument("--timeout", type=float, default=0.1)
    parser.add_argument("--fresh", action="store_true", help="truncate log before capture")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    args.log.parent.mkdir(parents=True, exist_ok=True)
    mode = "wb" if args.fresh else "ab"
    with args.log.open(mode) as log:
        log.write(b"\r\n--- LOGGER START ---\r\n")
        log.flush()

    with serial.Serial(args.port, args.baud, timeout=args.timeout) as ser:
        print(f"serial logger: {ser.name} -> {args.log}", flush=True)
        while True:
            data = ser.read(4096)
            if data:
                with args.log.open("ab") as log:
                    log.write(data)
                sys.stdout.buffer.write(data)
                sys.stdout.buffer.flush()
            else:
                time.sleep(0.01)


if __name__ == "__main__":
    raise SystemExit(main())
