#!/usr/bin/env python3
"""Upload an RV32 Linux Image and DTB through the firmware UART loader."""

from __future__ import annotations

import argparse
import sys
import time
from pathlib import Path

from linux_uart_protocol import (
    ACK_BOOT,
    ACK_CHUNK,
    ACK_ERROR,
    ACK_HEADER,
    ACK_READY,
    DDR_BASE,
    DEFAULT_DTB_ADDR,
    DEFAULT_IMAGE_ADDR,
    Header,
    build_transfer,
    validate_layout,
    validate_riscv_linux_image,
)


MONITOR_READ_TIMEOUT = 0.2
DEFAULT_READY_DELAY_MS = 20.0
DEFAULT_HEADER_BYTE_DELAY_MS = 1.0


def parse_int(text: str) -> int:
    return int(text, 0)


def expect(port, expected: bytes, phase: str) -> None:
    actual = port.read(1)
    if actual == ACK_ERROR:
        code = port.read(1)
        value = code[0] if code else -1
        raise RuntimeError(f"target rejected {phase}, error code {value}")
    if actual != expected:
        raise RuntimeError(f"expected {expected!r} after {phase}, received {actual!r}")


def send_paced(port, data: bytes, byte_delay_seconds: float) -> None:
    if byte_delay_seconds <= 0:
        port.write(data)
        port.flush()
        return

    for value in data:
        port.write(bytes((value,)))
        port.flush()
        time.sleep(byte_delay_seconds)


def send_frames(port, frames: list[bytes], label: str, progress_every: int) -> None:
    for index, frame in enumerate(frames):
        port.write(frame)
        port.flush()
        expect(port, ACK_CHUNK, f"{label} chunk {index}")
        if progress_every > 0 and ((index + 1) % progress_every) == 0:
            print(f"{label}: {index + 1}/{len(frames)} chunks", flush=True)


def monitor_console(
    port,
    output,
    log_path: Path | None,
    monitor_seconds: float | None,
    expect_text: str | None,
) -> bool:
    expected = expect_text.encode("utf-8") if expect_text is not None else None
    deadline = (
        None
        if monitor_seconds is None or monitor_seconds == 0
        else time.monotonic() + monitor_seconds
    )
    history = bytearray()
    keep = max(4096, len(expected or b"") * 2)
    old_timeout = getattr(port, "timeout", None)

    try:
        if hasattr(port, "timeout"):
            port.timeout = MONITOR_READ_TIMEOUT
        log_file = log_path.open("ab") if log_path is not None else None
        try:
            while True:
                chunk = port.read(1)
                if chunk:
                    output.write(chunk)
                    output.flush()
                    if log_file is not None:
                        log_file.write(chunk)
                        log_file.flush()
                    if expected is not None:
                        history.extend(chunk)
                        if len(history) > keep:
                            del history[:-keep]
                        if expected in history:
                            return True
                    continue

                if deadline is not None and time.monotonic() >= deadline:
                    return expected is None
        finally:
            if log_file is not None:
                log_file.close()
    except KeyboardInterrupt:
        print("\nmonitor stopped by user", file=sys.stderr)
        return expected is None or expected in history
    finally:
        if old_timeout is not None and hasattr(port, "timeout"):
            port.timeout = old_timeout


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("port", help="serial port, for example COM11")
    parser.add_argument("image", type=Path, help="raw Linux Image")
    parser.add_argument("dtb", type=Path, help="compiled device tree blob")
    parser.add_argument("--baud", type=int, default=115200)
    parser.add_argument("--image-load", type=parse_int, default=DEFAULT_IMAGE_ADDR)
    parser.add_argument("--image-entry", type=parse_int)
    parser.add_argument("--dtb-load", type=parse_int, default=DEFAULT_DTB_ADDR)
    parser.add_argument("--timeout", type=float, default=30.0)
    parser.add_argument("--ready-delay-ms", type=float, default=DEFAULT_READY_DELAY_MS)
    parser.add_argument(
        "--header-byte-delay-ms",
        type=float,
        default=DEFAULT_HEADER_BYTE_DELAY_MS,
    )
    parser.add_argument("--progress-every", type=int, default=1024)
    parser.add_argument("--monitor", action="store_true")
    parser.add_argument("--monitor-seconds", type=float)
    parser.add_argument("--expect")
    parser.add_argument("--log", type=Path)
    args = parser.parse_args()

    if args.monitor_seconds is not None and args.monitor_seconds < 0:
        parser.error("--monitor-seconds must be non-negative")
    if args.progress_every < 0:
        parser.error("--progress-every must be non-negative")
    if args.ready_delay_ms < 0:
        parser.error("--ready-delay-ms must be non-negative")
    if args.header_byte_delay_ms < 0:
        parser.error("--header-byte-delay-ms must be non-negative")
    return args


def should_monitor(args: argparse.Namespace) -> bool:
    return (
        args.monitor
        or args.monitor_seconds is not None
        or args.expect is not None
        or args.log is not None
    )


def main() -> int:
    args = parse_args()
    try:
        import serial
    except ModuleNotFoundError as exc:
        raise RuntimeError("pyserial is required for board upload") from exc

    image = args.image.read_bytes()
    dtb = args.dtb.read_bytes()
    linux_header = validate_riscv_linux_image(
        image,
        expected_text_offset=args.image_load - DDR_BASE,
    )
    runtime_size = max(len(image), linux_header.image_size)
    validate_layout(
        Header(
            image_load=args.image_load,
            image_entry=args.image_entry or args.image_load,
            image_size=runtime_size,
            dtb_load=args.dtb_load,
            dtb_size=len(dtb),
        )
    )
    header, image_frames, dtb_frames = build_transfer(
        image=image,
        dtb=dtb,
        image_load=args.image_load,
        image_entry=args.image_entry,
        dtb_load=args.dtb_load,
    )

    with serial.Serial(
        args.port,
        baudrate=args.baud,
        bytesize=8,
        parity="N",
        stopbits=1,
        timeout=args.timeout,
        write_timeout=args.timeout,
    ) as port:
        port.reset_input_buffer()
        print("waiting for target ready byte; reset the board if needed", flush=True)
        expect(port, ACK_READY, "target ready")
        time.sleep(args.ready_delay_ms / 1000.0)
        send_paced(port, header.encode(), args.header_byte_delay_ms / 1000.0)
        expect(port, ACK_HEADER, "header")
        send_frames(port, image_frames, "image", args.progress_every)
        send_frames(port, dtb_frames, "DTB", args.progress_every)
        expect(port, ACK_BOOT, "boot handoff")

        print(
            f"uploaded {len(image)} image bytes to 0x{header.image_load:08x}, "
            f"{len(dtb)} DTB bytes to 0x{header.dtb_load:08x}",
            flush=True,
        )
        if should_monitor(args):
            print("monitoring board console; press Ctrl+C to stop", flush=True)
            output = getattr(sys.stdout, "buffer", sys.stdout)
            if not monitor_console(
                port,
                output,
                args.log,
                args.monitor_seconds,
                args.expect,
            ):
                raise RuntimeError(
                    f"board console did not contain expected text: {args.expect!r}"
                )
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, RuntimeError, ValueError) as exc:
        print(f"upload failed: {exc}", file=sys.stderr)
        raise SystemExit(1)
