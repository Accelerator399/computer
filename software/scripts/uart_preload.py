#!/usr/bin/env python3
"""Load a DDR preload file into the FPGA over the board UART."""

from __future__ import annotations

import argparse
import sys
import time
from pathlib import Path


def import_serial():
    try:
        import serial  # type: ignore

        return serial
    except ImportError as exc:
        raise SystemExit(
            "pyserial is required. Install it with: python -m pip install pyserial"
        ) from exc


def read_line(ser, timeout_s: float) -> bytes:
    deadline = time.monotonic() + timeout_s
    data = bytearray()
    while time.monotonic() < deadline:
        b = ser.read(1)
        if not b:
            continue
        data.extend(b)
        if b == b"\n":
            return bytes(data)
    raise TimeoutError(f"timed out waiting for UART line; partial={bytes(data)!r}")


def wait_for_token(ser, token: bytes, timeout_s: float) -> bytes:
    deadline = time.monotonic() + timeout_s
    data = bytearray()
    while time.monotonic() < deadline:
        b = ser.read(1)
        if not b:
            continue
        data.extend(b)
        if token in data:
            return bytes(data)
        if len(data) > 4096:
            del data[:-len(token)]
    raise TimeoutError(f"timed out waiting for {token!r}; partial={bytes(data)!r}")


def iter_preload_lines(path: Path):
    with path.open("r", encoding="ascii") as fh:
        for line_no, raw in enumerate(fh, start=1):
            line = raw.strip()
            if not line or line.startswith("#"):
                continue
            parts = line.split()
            if len(parts) != 2:
                raise ValueError(f"{path}:{line_no}: expected '<addr> <hex128>'")
            addr, data = validate_record(parts[0], parts[1], f"{path}:{line_no}")
            yield line_no, f"{addr.lower()} {data.lower()}\n".encode("ascii")


def validate_record(addr: str, data: str, context: str) -> tuple[str, str]:
    int(addr, 16)
    int(data, 16)
    if len(addr) != 8 or len(data) != 32:
        raise ValueError(f"{context}: expected 8 address hex and 32 data hex digits")
    return addr.lower(), data.lower()


def drain_acks(ser, expected: list[int], timeout_s: float) -> None:
    for line_no in expected:
        reply = read_line(ser, timeout_s).strip()
        if reply != b"OK":
            raise RuntimeError(f"loader rejected line {line_no}: {reply!r}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", default="COM11", help="Serial port. Default: COM11")
    parser.add_argument("--preload", required=True, help="DDR preload .memh file")
    parser.add_argument("--loader-baud", type=int, default=230400, help="Loader baud rate")
    parser.add_argument("--console-baud", type=int, default=115200, help="Console baud rate after GO")
    parser.add_argument("--ready-timeout", type=float, default=30.0)
    parser.add_argument("--ack-timeout", type=float, default=5.0)
    parser.add_argument("--log", default="", help="Optional UART log output file")
    parser.add_argument("--no-go", action="store_true", help="Load DDR but do not release the CPU")
    parser.add_argument("--console-seconds", type=float, default=120.0, help="How long to capture console after GO")
    parser.add_argument("--reset-buffers", action="store_true", help="Clear UART buffers after opening the port")
    parser.add_argument("--max-lines", type=int, default=0, help="Only send this many preload lines; 0 sends all lines")
    parser.add_argument("--line-delay", type=float, default=0.0, help="Delay in seconds after each accepted line")
    parser.add_argument("--ack-window", type=int, default=1, help="Send this many lines before waiting for OK replies")
    parser.add_argument(
        "--extra-line",
        action="append",
        default=[],
        metavar="ADDR:HEX128",
        help="Append one diagnostic preload line after the file lines. Can be repeated.",
    )
    args = parser.parse_args()

    preload = Path(args.preload)
    if not preload.is_file():
        raise SystemExit(f"preload file not found: {preload}")

    serial = import_serial()
    ser = serial.Serial(args.port, args.loader_baud, timeout=0.05)
    try:
        if args.reset_buffers:
            ser.reset_input_buffer()
            ser.reset_output_buffer()
        print(f"Waiting for loader RDY on {args.port} at {args.loader_baud} baud...")
        ready_blob = wait_for_token(ser, b"RDY\n", args.ready_timeout)
        if ready_blob.strip():
            print(ready_blob.decode("ascii", errors="replace").strip())

        if args.ack_window < 1:
            raise ValueError("--ack-window must be at least 1")

        sent = 0
        pending_acks: list[int] = []
        start = time.monotonic()
        payloads = iter_preload_lines(preload)
        for line_no, payload in payloads:
            if args.max_lines and sent >= args.max_lines:
                break
            ser.write(payload)
            pending_acks.append(line_no)
            sent += 1

            if len(pending_acks) >= args.ack_window:
                ser.flush()
                drain_acks(ser, pending_acks, args.ack_timeout)
                pending_acks.clear()

            if sent == 1 or sent % 1024 == 0:
                elapsed = max(time.monotonic() - start, 0.001)
                print(f"loaded {sent} DDR lines ({sent / elapsed:.1f} lines/s)")
            if args.line_delay > 0:
                time.sleep(args.line_delay)

        for extra_index, spec in enumerate(args.extra_line, start=1):
            if ":" not in spec:
                raise ValueError(f"--extra-line {extra_index}: expected ADDR:HEX128")
            addr, data = spec.split(":", 1)
            addr, data = validate_record(addr, data, f"--extra-line {extra_index}")
            ser.write(f"{addr} {data}\n".encode("ascii"))
            pending_acks.append(-extra_index)
            sent += 1

            if len(pending_acks) >= args.ack_window:
                ser.flush()
                drain_acks(ser, pending_acks, args.ack_timeout)
                pending_acks.clear()

            if sent == 1 or sent % 1024 == 0:
                elapsed = max(time.monotonic() - start, 0.001)
                print(f"loaded {sent} DDR lines ({sent / elapsed:.1f} lines/s)")
            if args.line_delay > 0:
                time.sleep(args.line_delay)

        if pending_acks:
            ser.flush()
            drain_acks(ser, pending_acks, args.ack_timeout)
            pending_acks.clear()

        elapsed = max(time.monotonic() - start, 0.001)
        print(f"DDR preload complete: {sent} lines in {elapsed:.1f}s")

        if args.no_go:
            return 0

        ser.write(b"GO\n")
        ser.flush()
        reply = read_line(ser, args.ack_timeout).strip()
        if reply != b"GO":
            raise RuntimeError(f"unexpected GO reply: {reply!r}")

        ser.baudrate = args.console_baud
        ser.timeout = 0.1
        log_fh = None
        if args.log:
            log_path = Path(args.log)
            log_path.parent.mkdir(parents=True, exist_ok=True)
            log_fh = log_path.open("wb")

        print(f"CPU released; capturing console at {args.console_baud} baud...")
        deadline = time.monotonic() + args.console_seconds
        try:
            while time.monotonic() < deadline:
                chunk = ser.read(4096)
                if not chunk:
                    continue
                sys.stdout.buffer.write(chunk)
                sys.stdout.buffer.flush()
                if log_fh is not None:
                    log_fh.write(chunk)
                    log_fh.flush()
        finally:
            if log_fh is not None:
                log_fh.close()
    finally:
        ser.close()

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
