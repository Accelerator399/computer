#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BUILD_DIR="${BUILD_DIR:-$ROOT/build/software}"
LINUX_REPO="${LINUX_REPO:-https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git}"
LINUX_REF="${LINUX_REF:-v6.6}"
LINUX_TARBALL_URL="${LINUX_TARBALL_URL:-}"
LINUX_SRC="${LINUX_SRC:-$BUILD_DIR/linux-src}"
LINUX_TARBALL="${LINUX_TARBALL:-$BUILD_DIR/linux-${LINUX_REF}.tar.gz}"
LINUX_DEFCONFIG="${LINUX_DEFCONFIG:-defconfig}"
KBUILD_DIR="${KBUILD_DIR:-$BUILD_DIR/linux-build}"
INIT_BUILD_DIR="${INIT_BUILD_DIR:-$BUILD_DIR/linux-init}"
ROOTFS_DIR="${ROOTFS_DIR:-$BUILD_DIR/rootfs-real-linux}"
ROOTFS_CPIO="${ROOTFS_CPIO:-$BUILD_DIR/rootfs-real-linux.cpio}"
DTB_OUT="${DTB_OUT:-$BUILD_DIR/computer-rv32.dtb}"
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

cpufeature_file="$LINUX_SRC/arch/riscv/kernel/cpufeature.c"
if grep -q '^arch_initcall(check_unaligned_access_boot_cpu);' "$cpufeature_file"; then
    echo "Disabling boot-time RISC-V unaligned-access benchmark for FPGA bring-up"
    sed -i \
        's|^arch_initcall(check_unaligned_access_boot_cpu);$|/* disabled for FPGA bring-up: arch_initcall(check_unaligned_access_boot_cpu); */|' \
        "$cpufeature_file"
fi

main_init_file="$LINUX_SRC/init/main.c"
if ! grep -q 'BRINGUP: before fork_init' "$main_init_file"; then
    echo "Adding Linux start_kernel bring-up markers"
    perl -0pi -e 's|\n\tthread_stack_cache_init\(\);\n\tcred_init\(\);\n\tfork_init\(\);\n\tproc_caches_init\(\);\n\tuts_ns_init\(\);\n\tkey_init\(\);\n\tsecurity_init\(\);\n\tdbg_late_init\(\);\n\tnet_ns_init\(\);\n\tvfs_caches_init\(\);\n\tpagecache_init\(\);\n\tsignals_init\(\);\n\tseq_file_init\(\);\n\tproc_root_init\(\);\n\tnsfs_init\(\);\n\tcpuset_init\(\);\n\tcgroup_init\(\);\n\ttaskstats_init_early\(\);\n\tdelayacct_init\(\);\n\n\tacpi_subsystem_init\(\);\n\tarch_post_acpi_subsys_init\(\);\n\tkcsan_init\(\);\n\n\t/\* Do the rest non-__init.ed, we.re now alive \*/\n\tarch_call_rest_init\(\);\n|\n\tthread_stack_cache_init();\n\tpr_info("BRINGUP: before cred_init\\n");\n\tcred_init();\n\tpr_info("BRINGUP: before fork_init\\n");\n\tfork_init();\n\tpr_info("BRINGUP: after fork_init\\n");\n\tproc_caches_init();\n\tpr_info("BRINGUP: after proc_caches_init\\n");\n\tuts_ns_init();\n\tkey_init();\n\tsecurity_init();\n\tdbg_late_init();\n\tnet_ns_init();\n\tpr_info("BRINGUP: before vfs_caches_init\\n");\n\tvfs_caches_init();\n\tpr_info("BRINGUP: after vfs_caches_init\\n");\n\tpagecache_init();\n\tpr_info("BRINGUP: after pagecache_init\\n");\n\tsignals_init();\n\tpr_info("BRINGUP: after signals_init\\n");\n\tseq_file_init();\n\tproc_root_init();\n\tpr_info("BRINGUP: after proc_root_init\\n");\n\tnsfs_init();\n\tcpuset_init();\n\tcgroup_init();\n\tpr_info("BRINGUP: after cgroup_init\\n");\n\ttaskstats_init_early();\n\tdelayacct_init();\n\tpr_info("BRINGUP: after delayacct_init\\n");\n\n\tacpi_subsystem_init();\n\tarch_post_acpi_subsys_init();\n\tkcsan_init();\n\n\t/* Do the rest non-__init.ed, we.re now alive */\n\tpr_info("BRINGUP: before arch_call_rest_init\\n");\n\tarch_call_rest_init();\n|s' "$main_init_file"
fi
if ! grep -q 'BRINGUP: before arch_call_rest_init' "$main_init_file"; then
    echo "ERROR: failed to add Linux start_kernel bring-up markers" >&2
    exit 1
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
# CONFIG_BUG is not set
# CONFIG_KALLSYMS is not set
# CONFIG_DEBUG_INFO is not set
CONFIG_CC_OPTIMIZE_FOR_SIZE=y
EOF

mkdir -p "$KBUILD_DIR"

FORCE_ENABLE_CONFIG=(
    NONPORTABLE
    EXPERT
    EMBEDDED
    CC_OPTIMIZE_FOR_SIZE
    ARCH_RV32I
    32BIT
    MMU
    FLATMEM_MANUAL
    FLATMEM
    RISCV_SBI
    RISCV_SBI_V01
    RISCV_ISA_FALLBACK
    HVC_RISCV_SBI
    SERIAL_EARLYCON_RISCV_SBI
    HZ_100
    PRINTK
    TTY
    SERIAL_EARLYCON
    BINFMT_ELF
    BLK_DEV_INITRD
    INITRAMFS_COMPRESSION_NONE
    PROC_FS
    SYSFS
    TMPFS
    CRYPTO
    CRYPTO_MANAGER_DISABLE_TESTS
    CMDLINE_BOOL
)

FORCE_DISABLE_CONFIG=(
    64BIT
    ARCH_RV64I
    SPARSEMEM_MANUAL
    SPARSEMEM
    SPARSEMEM_STATIC
    SPARSEMEM_EXTREME
    SPARSEMEM_VMEMMAP
    RISCV_ISA_C
    FPU
    RISCV_ISA_V
    RISCV_ISA_ZBB
    RISCV_ISA_ZICBOM
    RISCV_ISA_ZICBOZ
    RISCV_DMA_NONCOHERENT
    SMP
    HOTPLUG_CPU
    EFI
    ACPI
    PCI
    VIRTUALIZATION
    KVM
    SOC_MICROCHIP_POLARFIRE
    ARCH_RENESAS
    SOC_SIFIVE
    SOC_STARFIVE
    ARCH_SUNXI
    ARCH_THEAD
    SOC_VIRT
    ERRATA_ANDES
    ERRATA_SIFIVE
    ERRATA_THEAD
    MODULES
    NET
    BLOCK
    SCSI
    MD
    AUDIT
    CGROUPS
    NAMESPACES
    CHECKPOINT_RESTORE
    FHANDLE
    BPF_SYSCALL
    PERF_EVENTS
    PROFILING
    KALLSYMS
    DEBUG_INFO
    DEBUG_FS
    DEVTMPFS
    DEVTMPFS_MOUNT
    VT
    UNIX98_PTYS
    LEGACY_PTYS
    BUG
    SERIAL_8250
    SERIAL_8250_CONSOLE
    SERIAL_8250_DEPRECATED_OPTIONS
    SERIAL_8250_PNP
    SERIAL_8250_16550A_VARIANTS
    SERIAL_8250_DMA
    SERIAL_8250_PCILIB
    SERIAL_8250_PCI
    SERIAL_OF_PLATFORM
    SERIAL_SH_SCI
    SERIAL_SIFIVE
    VIRTIO_CONSOLE
    VIRTIO_MENU
    VIRTIO
    HW_RANDOM_VIRTIO
    RPMSG
    RPMSG_CHAR
    RPMSG_CTRL
    RPMSG_VIRTIO
    IOMMU_SUPPORT
    DMADEVICES
    INPUT
    HID_SUPPORT
    USB_SUPPORT
    USB
    I2C
    SPI
    PINCTRL
    GPIOLIB
    GPIO_CDEV
    GPIO_GENERIC
    GPIO_SIFIVE
    DRM
    FB
    SOUND
    MMC
    RTC_CLASS
    HW_RANDOM
    MEDIA_SUPPORT
    NVMEM
    HWMON
    REGULATOR
    POWER_SUPPLY
    THERMAL
    WATCHDOG
    GOLDFISH
    PINCTRL_RENESAS
    PINCTRL_STARFIVE_JH7100
    PINCTRL_STARFIVE_JH7110
    PINCTRL_STARFIVE_JH7110_SYS
    PINCTRL_STARFIVE_JH7110_AON
    PINCTRL_SUNXI
    PINCTRL_SUN20I_D1
    CLK_ANALOGBITS_WRPLL_CLN28HPC
    MCHP_CLK_MPFS
    CLK_RENESAS
    CLK_SIFIVE
    CLK_SIFIVE_PRCI
    CLK_STARFIVE_JH71X0
    CLK_STARFIVE_JH7100
    CLK_STARFIVE_JH7100_AUDIO
    CLK_STARFIVE_JH7110_PLL
    CLK_STARFIVE_JH7110_SYS
    CLK_STARFIVE_JH7110_AON
    CLK_STARFIVE_JH7110_STG
    CLK_STARFIVE_JH7110_ISP
    CLK_STARFIVE_JH7110_VOUT
    ARCH_R9A07G043
    SOC_RENESAS
    PM
    PM_SLEEP
    SUSPEND
    SUSPEND_FREEZER
    POWER_RESET
    POWER_RESET_SYSCON
    POWER_RESET_SYSCON_POWEROFF
    CPU_IDLE
    RISCV_SBI_CPUIDLE
    RISCV_PMU
    EXT4_FS
    MSDOS_FS
    VFAT_FS
    FAT_FS
    NFS_FS
    ROOT_NFS
    9P_FS
    AUTOFS_FS
    HUGETLBFS
    HUGETLB_PAGE
    COMPACTION
    MIGRATION
    OVERLAY_FS
    OVERLAY_FS_REDIRECT_DIR
    OVERLAY_FS_INDEX
    OVERLAY_FS_METACOPY
    OVERLAY_FS_DEBUG
    PROC_PAGE_MONITOR
    PROC_CHILDREN
    TMPFS_POSIX_ACL
    TMPFS_XATTR
    NLS
    LIBCRC32C
    CRYPTO_MANAGER_EXTRA_TESTS
    CRYPTO_USER_API_HASH
    CRYPTO_DEV_VIRTIO
    CRYPTO_GCM
    CRYPTO_GENIV
    CRYPTO_SEQIV
    CRYPTO_ECHAINIV
    CRYPTO_DRBG_MENU
    CRYPTO_JITTERENTROPY
    IKCONFIG
    IKCONFIG_PROC
    DEBUG_MISC
    SLUB_DEBUG
    DEBUG_BUGVERBOSE
    DEBUG_PAGEALLOC
    DEBUG_VM
    DEBUG_VM_IRQSOFF
    DEBUG_VM_PGFLAGS
    DEBUG_VM_PGTABLE
    DEBUG_MEMORY_INIT
    LOCKUP_DETECTOR
    SOFTLOCKUP_DETECTOR
    DETECT_HUNG_TASK
    WQ_WATCHDOG
    SCHED_DEBUG
    DEBUG_TIMEKEEPING
    DEBUG_RT_MUTEXES
    DEBUG_SPINLOCK
    DEBUG_MUTEXES
    DEBUG_RWSEMS
    DEBUG_ATOMIC_SLEEP
    STACKTRACE
    STACKDEPOT
    DEBUG_LIST
    DEBUG_PLIST
    DEBUG_SG
    RCU_EQS_DEBUG
    RUNTIME_TESTING_MENU
    MEMTEST
)

apply_config_overrides() {
    local config_tool="$LINUX_SRC/scripts/config"
    local base=(bash "$config_tool" --file "$KBUILD_DIR/.config")
    local name

    "${base[@]}" --set-str INITRAMFS_SOURCE "$ROOTFS_CPIO"
    "${base[@]}" --set-val BASE_SMALL 1
    "${base[@]}" --set-val HZ 100
    "${base[@]}" --set-str CMDLINE "earlycon=sbi console=hvc0 rdinit=/init loglevel=8 ignore_loglevel initcall_debug"

    for name in "${FORCE_ENABLE_CONFIG[@]}"; do
        "${base[@]}" --enable "$name"
    done
    for name in "${FORCE_DISABLE_CONFIG[@]}"; do
        "${base[@]}" --disable "$name"
    done
}

echo "Configuring Linux kernel"
make -C "$LINUX_SRC" O="$KBUILD_DIR" ARCH=riscv CROSS_COMPILE="$CROSS_COMPILE" "$LINUX_DEFCONFIG"
"$LINUX_SRC/scripts/kconfig/merge_config.sh" \
    -m \
    -O "$KBUILD_DIR" \
    "$KBUILD_DIR/.config" \
    "$ROOT/software/linux/linux.fragment" \
    "$generated_fragment"
apply_config_overrides
make -C "$LINUX_SRC" O="$KBUILD_DIR" ARCH=riscv CROSS_COMPILE="$CROSS_COMPILE" olddefconfig
apply_config_overrides
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

for symbol in \
    CONFIG_ARCH_RV32I \
    CONFIG_32BIT \
    CONFIG_MMU \
    CONFIG_FLATMEM \
    CONFIG_RISCV_SBI \
    CONFIG_BLK_DEV_INITRD \
    CONFIG_BINFMT_ELF
do
    check_config_state "$symbol" y
done

for symbol in \
    CONFIG_64BIT \
    CONFIG_ARCH_RV64I \
    CONFIG_SPARSEMEM \
    CONFIG_RISCV_ISA_C \
    CONFIG_FPU \
    CONFIG_SMP \
    CONFIG_SOC_STARFIVE \
    CONFIG_ARCH_SUNXI \
    CONFIG_SOC_SIFIVE \
    CONFIG_SOC_VIRT \
    CONFIG_NET \
    CONFIG_BLOCK \
    CONFIG_VIRTIO \
    CONFIG_RPMSG \
    CONFIG_I2C \
    CONFIG_USB_SUPPORT \
    CONFIG_USB \
    CONFIG_MEDIA_SUPPORT \
    CONFIG_DRM \
    CONFIG_FB \
    CONFIG_MMC \
    CONFIG_RTC_CLASS \
    CONFIG_DEVTMPFS \
    CONFIG_OVERLAY_FS
do
    check_config_state "$symbol" n
done

echo "Building Linux Image"
make -C "$LINUX_SRC" O="$KBUILD_DIR" ARCH=riscv CROSS_COMPILE="$CROSS_COMPILE" -j"$JOBS" Image

image="$KBUILD_DIR/arch/riscv/boot/Image"
if [[ ! -s "$image" ]]; then
    echo "ERROR: Linux Image not produced: $image" >&2
    exit 1
fi

generated_dts="$BUILD_DIR/computer-rv32.generated.dts"
sed \
    -e "s/timebase-frequency = <[0-9][0-9]*>/timebase-frequency = <$DTS_CLK_FREQ>/" \
    -e "s/clock-frequency = <[0-9][0-9]*>/clock-frequency = <$DTS_CLK_FREQ>/" \
    "$ROOT/software/dts/computer-rv32.dts" > "$generated_dts"
"$DTC" -I dts -O dtb -o "$DTB_OUT" "$generated_dts"

echo "Linux Image : $image"
echo "DTB         : $DTB_OUT"
echo "Rootfs cpio : $ROOTFS_CPIO"
echo ""
echo "Upload:"
echo "  python software/scripts/linux_uart_upload.py COM11 \"$image\" \"$DTB_OUT\" --monitor"
