#!/usr/bin/env python3
"""Upload an RV32 Linux Image and DTB through the Ethernet Lite UDP loader."""

from __future__ import annotations

import argparse
import socket
import struct
import sys
import time
from pathlib import Path

from linux_uart_protocol import (
    DDR_BASE,
    DEFAULT_DTB_ADDR,
    DEFAULT_IMAGE_ADDR,
    Header,
    NET_CHUNK_SIZE,
    NET_MAGIC,
    NET_PORT,
    NET_STATUS_OK,
    NET_STREAM_DTB,
    NET_STREAM_IMAGE,
    NET_TYPE_ACK,
    NET_TYPE_BOOT,
    NET_TYPE_DATA,
    NET_TYPE_HEADER,
    NET_VERSION,
    crc32,
    validate_layout,
    validate_riscv_linux_image,
)


PACKET_HEADER = struct.Struct("<8I")
BOOT_ACK_SEEN = False


def format_bytes(size: int) -> str:
    units = ("B", "KiB", "MiB", "GiB")
    value = float(size)
    for unit in units:
        if value < 1024.0 or unit == units[-1]:
            if unit == "B":
                return f"{size} {unit}"
            return f"{value:.1f} {unit}"
        value /= 1024.0
    return f"{size} B"


def parse_int(text: str) -> int:
    return int(text, 0)


def make_packet(
    packet_type: int,
    seq: int,
    stream: int,
    offset: int,
    payload: bytes,
) -> bytes:
    return PACKET_HEADER.pack(
        NET_MAGIC,
        NET_VERSION,
        packet_type,
        seq,
        stream,
        offset,
        len(payload),
        crc32(payload),
    ) + payload


def parse_ack(data: bytes) -> tuple[int, int, int] | None:
    if len(data) < PACKET_HEADER.size:
        return None
    magic, version, packet_type, seq, stream, status, length, payload_crc = (
        PACKET_HEADER.unpack_from(data)
    )
    if (
        magic != NET_MAGIC
        or version != NET_VERSION
        or packet_type != NET_TYPE_ACK
        or length != 0
        or payload_crc != 0
    ):
        return None
    return seq, stream, status


def send_with_ack(
    sock: socket.socket,
    target: tuple[str, int],
    packet: bytes,
    seq: int,
    acked_type: int,
    retries: int,
    label: str,
) -> None:
    global BOOT_ACK_SEEN

    base_timeout = sock.gettimeout() or 1.0
    try:
        for attempt in range(retries + 1):
            sock.sendto(packet, target)
            deadline = time.monotonic() + base_timeout
            while True:
                remaining = deadline - time.monotonic()
                if remaining <= 0:
                    break
                sock.settimeout(remaining)
                try:
                    data, _addr = sock.recvfrom(2048)
                except socket.timeout:
                    break
                ack = parse_ack(data)
                if ack is None:
                    continue
                ack_seq, ack_stream, status = ack
                if ack_stream == NET_TYPE_BOOT and status == NET_STATUS_OK:
                    BOOT_ACK_SEEN = True
                    continue
                if ack_seq != seq or ack_stream != acked_type:
                    continue
                if status != NET_STATUS_OK:
                    raise RuntimeError(f"target rejected {label}, status {status}")
                return
            if attempt < retries:
                continue
    finally:
        sock.settimeout(base_timeout)
    raise RuntimeError(f"timed out waiting for ACK for {label}")


def send_region(
    sock: socket.socket,
    target: tuple[str, int],
    data: bytes,
    stream: int,
    seq: int,
    retries: int,
    label: str,
    progress_every: int,
) -> int:
    chunks = (len(data) + NET_CHUNK_SIZE - 1) // NET_CHUNK_SIZE
    start = time.monotonic()
    print(f"{label}: sending {format_bytes(len(data))} in {chunks} chunks", flush=True)
    for index, offset in enumerate(range(0, len(data), NET_CHUNK_SIZE)):
        payload = data[offset : offset + NET_CHUNK_SIZE]
        packet = make_packet(NET_TYPE_DATA, seq, stream, offset, payload)
        send_with_ack(
            sock,
            target,
            packet,
            seq,
            NET_TYPE_DATA,
            retries,
            f"{label} chunk {index}",
        )
        seq += 1
        if progress_every > 0 and (
            ((index + 1) % progress_every) == 0 or (index + 1) == chunks
        ):
            sent = min(offset + len(payload), len(data))
            elapsed = max(time.monotonic() - start, 0.001)
            percent = sent * 100.0 / len(data)
            rate = int(sent / elapsed)
            print(
                f"{label}: {index + 1}/{chunks} chunks, "
                f"{format_bytes(sent)}/{format_bytes(len(data))} "
                f"({percent:.1f}%, {format_bytes(rate)}/s)",
                flush=True,
            )
    return seq


def wait_boot_ack(sock: socket.socket, timeout: float) -> None:
    global BOOT_ACK_SEEN

    if BOOT_ACK_SEEN:
        return
    deadline = time.monotonic() + timeout
    while True:
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise RuntimeError("timed out waiting for boot handoff ACK")
        sock.settimeout(remaining)
        try:
            data, _addr = sock.recvfrom(2048)
        except socket.timeout:
            continue
        ack = parse_ack(data)
        if ack is None:
            continue
        _seq, ack_stream, status = ack
        if ack_stream == NET_TYPE_BOOT and status == NET_STATUS_OK:
            return


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("target_ip", help="board IP, firmware default is 169.254.5.67")
    parser.add_argument("image", type=Path, help="raw Linux Image")
    parser.add_argument("dtb", type=Path, help="compiled device tree blob")
    parser.add_argument("--port", type=int, default=NET_PORT)
    parser.add_argument("--bind", default="", help="local address to bind, if needed")
    parser.add_argument("--image-load", type=parse_int, default=DEFAULT_IMAGE_ADDR)
    parser.add_argument("--image-entry", type=parse_int)
    parser.add_argument("--dtb-load", type=parse_int, default=DEFAULT_DTB_ADDR)
    parser.add_argument("--timeout", type=float, default=1.0)
    parser.add_argument("--boot-timeout", type=float, default=5.0)
    parser.add_argument("--retries", type=int, default=20)
    parser.add_argument("--progress-every", type=int, default=256)
    args = parser.parse_args()
    if args.timeout <= 0:
        parser.error("--timeout must be positive")
    if args.boot_timeout <= 0:
        parser.error("--boot-timeout must be positive")
    if args.retries < 0:
        parser.error("--retries must be non-negative")
    if args.progress_every < 0:
        parser.error("--progress-every must be non-negative")
    return args


def main() -> int:
    args = parse_args()
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
    header = Header(
        image_load=args.image_load,
        image_entry=args.image_entry or args.image_load,
        image_size=len(image),
        dtb_load=args.dtb_load,
        dtb_size=len(dtb),
    )

    target = (args.target_ip, args.port)
    seq = 1
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
        if args.target_ip == "255.255.255.255" or args.target_ip.endswith(".255"):
            sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
        sock.bind((args.bind, 0))
        sock.settimeout(args.timeout)
        print(
            f"target: {args.target_ip}:{args.port}; waiting for netboot ACKs",
            flush=True,
        )
        send_with_ack(
            sock,
            target,
            make_packet(NET_TYPE_HEADER, seq, 0, 0, header.encode()),
            seq,
            NET_TYPE_HEADER,
            args.retries,
            "header",
        )
        print("header: accepted", flush=True)
        seq += 1
        seq = send_region(
            sock,
            target,
            image,
            NET_STREAM_IMAGE,
            seq,
            args.retries,
            "image",
            args.progress_every,
        )
        seq = send_region(
            sock,
            target,
            dtb,
            NET_STREAM_DTB,
            seq,
            args.retries,
            "DTB",
            args.progress_every,
        )
        print("waiting for boot handoff ACK", flush=True)
        wait_boot_ack(sock, args.boot_timeout)

    print(
        f"uploaded {len(image)} image bytes to 0x{header.image_load:08x}, "
        f"{len(dtb)} DTB bytes to 0x{header.dtb_load:08x} over UDP",
        flush=True,
    )
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, RuntimeError, ValueError) as exc:
        print(f"net upload failed: {exc}", file=sys.stderr)
        raise SystemExit(1)
