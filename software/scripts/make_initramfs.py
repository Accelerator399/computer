#!/usr/bin/env python3
"""Create a simple uncompressed cpio newc archive from a directory."""

from __future__ import annotations

import argparse
import os
import stat
from pathlib import Path
from typing import BinaryIO, Iterable, Tuple


def pad4(value: int) -> int:
    return (4 - (value & 3)) & 3


def write_pad(out: BinaryIO, size: int) -> None:
    if size:
        out.write(b"\0" * size)


def write_entry(
    out: BinaryIO,
    name: str,
    mode: int,
    data: bytes = b"",
    mtime: int = 0,
    ino: int = 1,
) -> None:
    namesz = len(name.encode("utf-8")) + 1
    filesize = len(data)
    fields = [
        "070701",
        f"{ino:08x}",
        f"{mode:08x}",
        f"{0:08x}",
        f"{0:08x}",
        f"{1:08x}",
        f"{mtime:08x}",
        f"{filesize:08x}",
        f"{0:08x}",
        f"{0:08x}",
        f"{0:08x}",
        f"{0:08x}",
        f"{namesz:08x}",
        f"{0:08x}",
    ]
    header = "".join(fields).encode("ascii")
    out.write(header)
    out.write(name.encode("utf-8") + b"\0")
    write_pad(out, pad4(len(header) + namesz))
    out.write(data)
    write_pad(out, pad4(filesize))


def iter_paths(root: Path) -> Iterable[Tuple[str, Path]]:
    items = []
    for base, dirs, files in os.walk(root):
        dirs.sort()
        files.sort()
        base_path = Path(base)
        rel_base = base_path.relative_to(root)
        if rel_base != Path("."):
            items.append((rel_base.as_posix(), base_path))
        for filename in files:
            path = base_path / filename
            rel = path.relative_to(root).as_posix()
            items.append((rel, path))
    return items


def mode_for(path: Path, rel: str) -> int:
    st_mode = path.lstat().st_mode
    perms = stat.S_IMODE(st_mode)
    if path.is_dir():
        return stat.S_IFDIR | (perms or 0o755)
    if path.is_symlink():
        return stat.S_IFLNK | 0o777
    if rel == "init" or rel.endswith("/init"):
        perms |= 0o755
    return stat.S_IFREG | (perms or 0o644)


def data_for(path: Path) -> bytes:
    if path.is_dir():
        return b""
    if path.is_symlink():
        return os.readlink(path).encode("utf-8")
    return path.read_bytes()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", required=True, help="Directory to archive")
    parser.add_argument("--output", required=True, help="Output cpio path")
    args = parser.parse_args()

    root = Path(args.root)
    if not root.is_dir():
        raise SystemExit(f"root is not a directory: {root}")

    out_path = Path(args.output)
    out_path.parent.mkdir(parents=True, exist_ok=True)

    ino = 1
    with out_path.open("wb") as out:
        for rel, path in iter_paths(root):
            ino += 1
            mtime = int(path.lstat().st_mtime)
            write_entry(out, rel, mode_for(path, rel), data_for(path), mtime, ino)
        write_entry(out, "TRAILER!!!", 0, b"", 0, ino + 1)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
