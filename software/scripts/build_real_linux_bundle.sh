#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BUILD_DIR="${BUILD_DIR:-$ROOT/build/software}"
LINUX_REPO="${LINUX_REPO:-https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git}"
LINUX_REF="${LINUX_REF:-v6.6}"
LINUX_TARBALL_URL="${LINUX_TARBALL_URL:-}"
LINUX_SRC="${LINUX_SRC:-$BUILD_DIR/linux-src}"
LINUX_TARBALL="${LINUX_TARBALL:-$BUILD_DIR/linux-${LINUX_REF}.tar.gz}"
LINUX_DEFCONFIG="${LINUX_DEFCONFIG:-rv32_defconfig}"
KBUILD_DIR="${KBUILD_DIR:-$BUILD_DIR/linux-build}"
INIT_BUILD_DIR="${INIT_BUILD_DIR:-$BUILD_DIR/linux-init}"
ROOTFS_DIR="${ROOTFS_DIR:-$BUILD_DIR/rootfs-real-linux}"
ROOTFS_CPIO="${ROOTFS_CPIO:-$BUILD_DIR/rootfs-real-linux.cpio}"
PRELOAD_OUT="${PRELOAD_OUT:-$ROOT/software/image/linux_preload.memh}"
CROSS_COMPILE="${CROSS_COMPILE:-riscv64-linux-gnu-}"
DTC="${DTC:-dtc}"
PYTHON="${PYTHON:-python3}"
DTS_CLK_FREQ="${DTS_CLK_FREQ:-50000000}"
JOBS="${JOBS:-$(nproc)}"

mkdir -p "$BUILD_DIR"

if [[ -n "$LINUX_TARBALL_URL" && ! -f "$LINUX_SRC/Makefile" ]]; then
    echo "Fetching Linux source tarball: $LINUX_TARBALL_URL"
    rm -rf "$LINUX_SRC"
    mkdir -p "$(dirname "$LINUX_TARBALL")"
    if command -v curl >/dev/null 2>&1; then
        curl -L --retry 5 --retry-delay 2 --retry-connrefused \
            -o "$LINUX_TARBALL" "$LINUX_TARBALL_URL"
    elif command -v wget >/dev/null 2>&1; then
        wget -O "$LINUX_TARBALL" "$LINUX_TARBALL_URL"
    else
        echo "ERROR: curl or wget is required to fetch $LINUX_TARBALL_URL" >&2
        exit 1
    fi
    tmp_extract="$BUILD_DIR/linux-src.extract.$$"
    rm -rf "$tmp_extract"
    mkdir -p "$tmp_extract"
    tar -xf "$LINUX_TARBALL" -C "$tmp_extract"
    extracted_dir="$(find "$tmp_extract" -mindepth 1 -maxdepth 1 -type d | head -n 1)"
    if [[ -z "$extracted_dir" ]]; then
        echo "ERROR: cannot find extracted Linux source directory" >&2
        exit 1
    fi
    mv "$extracted_dir" "$LINUX_SRC"
    rm -rf "$tmp_extract"
elif [[ ! -d "$LINUX_SRC/.git" && ! -f "$LINUX_SRC/Makefile" ]]; then
    echo "Fetching Linux source: $LINUX_REPO ($LINUX_REF)"
    rm -rf "$LINUX_SRC"
    git clone --depth 1 --branch "$LINUX_REF" "$LINUX_REPO" "$LINUX_SRC"
else
    echo "Using existing Linux source: $LINUX_SRC"
fi

echo "Building minimal RV32 /init"
make -C "$ROOT/software/firmware/linux-init" \
    BUILD_DIR="$INIT_BUILD_DIR" \
    CROSS_COMPILE="$CROSS_COMPILE"

rm -rf "$ROOTFS_DIR"
mkdir -p "$ROOTFS_DIR"
cp "$INIT_BUILD_DIR/init" "$ROOTFS_DIR/init"
chmod 0755 "$ROOTFS_DIR/init"

"$PYTHON" "$ROOT/software/scripts/make_initramfs.py" \
    --root "$ROOTFS_DIR" \
    --output "$ROOTFS_CPIO"

generated_fragment="$BUILD_DIR/linux.generated.fragment"
cat > "$generated_fragment" <<EOF
CONFIG_INITRAMFS_SOURCE="$ROOTFS_CPIO"
CONFIG_INITRAMFS_COMPRESSION_NONE=y
# CONFIG_INITRAMFS_COMPRESSION_GZIP is not set
# CONFIG_RD_GZIP is not set
# CONFIG_RD_BZIP2 is not set
# CONFIG_RD_LZMA is not set
# CONFIG_RD_XZ is not set
# CONFIG_RD_LZO is not set
# CONFIG_RD_LZ4 is not set
# CONFIG_RD_ZSTD is not set
CONFIG_BLK_DEV_INITRD=y
CONFIG_EMBEDDED=y
CONFIG_EXPERT=y
CONFIG_PRINTK=y
CONFIG_BUG=y
# CONFIG_KALLSYMS is not set
# CONFIG_DEBUG_KERNEL is not set
# CONFIG_DEBUG_INFO is not set
CONFIG_CC_OPTIMIZE_FOR_SIZE=y
EOF

mkdir -p "$KBUILD_DIR"

echo "Configuring Linux kernel"
make -C "$LINUX_SRC" O="$KBUILD_DIR" ARCH=riscv CROSS_COMPILE="$CROSS_COMPILE" "$LINUX_DEFCONFIG"
"$LINUX_SRC/scripts/kconfig/merge_config.sh" \
    -m \
    -O "$KBUILD_DIR" \
    "$KBUILD_DIR/.config" \
    "$ROOT/software/linux/linux.fragment" \
    "$generated_fragment"
make -C "$LINUX_SRC" O="$KBUILD_DIR" ARCH=riscv CROSS_COMPILE="$CROSS_COMPILE" olddefconfig

check_config_state() {
    local symbol="$1"
    local expected="$2"
    local actual
    actual="$("$LINUX_SRC/scripts/config" --file "$KBUILD_DIR/.config" --state "${symbol#CONFIG_}")"
    if [[ "$expected" == "n" && "$actual" == "undef" ]]; then
        actual="n"
    fi
    if [[ "$actual" != "$expected" ]]; then
        echo "ERROR: $symbol expected $expected, got $actual" >&2
        exit 1
    fi
}

check_config_state CONFIG_ARCH_RV32I y
check_config_state CONFIG_32BIT y
check_config_state CONFIG_64BIT n
check_config_state CONFIG_RISCV_ISA_C n
check_config_state CONFIG_FPU n
check_config_state CONFIG_SMP n

echo "Building Linux Image"
make -C "$LINUX_SRC" O="$KBUILD_DIR" ARCH=riscv CROSS_COMPILE="$CROSS_COMPILE" -j"$JOBS" Image

image="$KBUILD_DIR/arch/riscv/boot/Image"
if [[ ! -s "$image" ]]; then
    echo "ERROR: Linux Image not produced: $image" >&2
    exit 1
fi

echo "Packing DDR preload bundle"
LINUX_IMAGE="$image" \
PRELOAD_OUT="$PRELOAD_OUT" \
DTS_CLK_FREQ="$DTS_CLK_FREQ" \
DTC="$DTC" \
PYTHON="$PYTHON" \
bash "$ROOT/software/scripts/build_boot_bundle.sh"

echo "Linux Image : $image"
echo "Rootfs cpio : $ROOTFS_CPIO"
echo "Preload     : $PRELOAD_OUT"
