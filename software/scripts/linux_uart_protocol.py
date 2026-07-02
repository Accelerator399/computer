#!/usr/bin/env python3
"""Shared protocol helpers for the board-side Linux UART loader."""

from __future__ import annotations

import dataclasses
import struct
import zlib


MAGIC = 0x3158424C
VERSION = 1
CHUNK_SIZE = 256
NET_MAGIC = 0x314E4343
NET_VERSION = 1
NET_PORT = 62000
NET_CHUNK_SIZE = 1024
NET_TYPE_HEADER = 1
NET_TYPE_DATA = 2
NET_TYPE_ACK = 3
NET_TYPE_BOOT = 4
NET_STREAM_IMAGE = 1
NET_STREAM_DTB = 2
NET_STATUS_OK = 0
DDR_BASE = 0x8000_0000
DDR_SIZE = 0x0800_0000
DEFAULT_IMAGE_ADDR = 0x8040_0000
DEFAULT_DTB_ADDR = 0x87E0_0000
DEFAULT_IMAGE_TEXT_OFFSET = DEFAULT_IMAGE_ADDR - DDR_BASE

RISCV_IMAGE_HEADER_SIZE = 64
RISCV_IMAGE_MAGIC = b"RISCV\0\0\0"
RISCV_IMAGE_MAGIC2 = b"RSC\x05"

ACK_READY = b"R"
ACK_HEADER = b"H"
ACK_CHUNK = b"C"
ACK_BOOT = b"B"
ACK_ERROR = b"E"


def crc32(data: bytes) -> int:
    return zlib.crc32(data) & 0xFFFF_FFFF


@dataclasses.dataclass(frozen=True)
class Header:
    image_load: int
    image_entry: int
    image_size: int
    dtb_load: int
    dtb_size: int
    flags: int = 0

    def prefix(self) -> bytes:
        return struct.pack(
            "<8I",
            MAGIC,
            VERSION,
            self.image_load,
            self.image_entry,
            self.image_size,
            self.dtb_load,
            self.dtb_size,
            self.flags,
        )

    def encode(self) -> bytes:
        prefix = self.prefix()
        return prefix + struct.pack("<I", crc32(prefix))


@dataclasses.dataclass(frozen=True)
class RiscvLinuxImageHeader:
    text_offset: int
    image_size: int
    flags: int
    version: int


def validate_region(address: int, size: int) -> None:
    if size <= 0:
        raise ValueError("region must not be empty")
    end = address + size
    if address < DDR_BASE or end > DDR_BASE + DDR_SIZE or end <= address:
        raise ValueError(f"region 0x{address:08x}..0x{end:08x} is outside DDR")


def validate_layout(header: Header) -> None:
    validate_region(header.image_load, header.image_size)
    validate_region(header.dtb_load, header.dtb_size)
    image_end = header.image_load + header.image_size
    dtb_end = header.dtb_load + header.dtb_size

    if header.image_load & 0x003F_FFFF:
        raise ValueError("RV32 Linux image address must be 4 MiB aligned")
    if header.image_entry & 0x3:
        raise ValueError("image entry must be 4-byte aligned")
    if not header.image_load <= header.image_entry < image_end:
        raise ValueError("image entry is outside the image")
    if header.dtb_load & 0x7:
        raise ValueError("DTB address must be 8-byte aligned")
    if header.dtb_size > 0x0020_0000:
        raise ValueError("DTB must not exceed 2 MiB")
    if (header.dtb_load >> 21) != ((dtb_end - 1) >> 21):
        raise ValueError("DTB must not cross a 2 MiB boundary")
    if max(header.image_load, header.dtb_load) < min(image_end, dtb_end):
        raise ValueError("image and DTB regions overlap")
    if header.flags != 0:
        raise ValueError("unsupported protocol flags")


def validate_riscv_linux_image(
    image: bytes,
    expected_text_offset: int = DEFAULT_IMAGE_TEXT_OFFSET,
) -> RiscvLinuxImageHeader:
    if len(image) < RISCV_IMAGE_HEADER_SIZE:
        raise ValueError("Linux Image is shorter than the RISC-V image header")

    text_offset = struct.unpack_from("<Q", image, 0x08)[0]
    image_size = struct.unpack_from("<Q", image, 0x10)[0]
    flags = struct.unpack_from("<Q", image, 0x18)[0]
    version = struct.unpack_from("<I", image, 0x20)[0]
    magic = image[0x30:0x38]
    magic2 = image[0x38:0x3C]

    if magic != RISCV_IMAGE_MAGIC or magic2 != RISCV_IMAGE_MAGIC2:
        raise ValueError("Linux Image does not have a valid RISC-V raw Image header")
    if text_offset != expected_text_offset:
        raise ValueError(
            f"Linux Image text offset is 0x{text_offset:x}, "
            f"expected 0x{expected_text_offset:x} for this DDR layout"
        )
    if image_size == 0:
        raise ValueError("Linux Image header reports zero image size")
    if image_size > DDR_SIZE - expected_text_offset:
        raise ValueError(
            f"Linux Image runtime size is 0x{image_size:x}, which does not fit in DDR"
        )
    return RiscvLinuxImageHeader(text_offset, image_size, flags, version)


def encode_region(data: bytes) -> list[bytes]:
    if not data:
        raise ValueError("region must not be empty")
    frames = []
    for offset in range(0, len(data), CHUNK_SIZE):
        chunk = data[offset : offset + CHUNK_SIZE]
        frames.append(
            struct.pack("<I", len(chunk))
            + chunk
            + struct.pack("<I", crc32(chunk))
        )
    return frames


def build_transfer(
    image: bytes,
    dtb: bytes,
    image_load: int = DEFAULT_IMAGE_ADDR,
    image_entry: int | None = None,
    dtb_load: int = DEFAULT_DTB_ADDR,
) -> tuple[Header, list[bytes], list[bytes]]:
    if image_entry is None:
        image_entry = image_load
    header = Header(
        image_load=image_load,
        image_entry=image_entry,
        image_size=len(image),
        dtb_load=dtb_load,
        dtb_size=len(dtb),
    )
    validate_layout(header)
    return header, encode_region(image), encode_region(dtb)
