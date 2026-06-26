# Linux Software Bring-Up

This directory contains the software-side pieces needed for the first simulated
Linux boot on the local RV32IMA computer.

Target for the first milestone:

```text
OpenSBI or OpenSBI-like M-mode firmware
    -> S-mode Linux Image
    -> ns16550/8250 early console at 0x10010000
    -> built-in initramfs
    -> /init prints "Hello from RV32 Linux on computer"
```

The first Linux target remains `rv32ima_zicsr_zifencei` with `ilp32`
soft-float user space.  The RTL now has a single-precision FPU path covering
most scalar RV32F operations, with Vivado Floating Point IP wrappers for
add/sub/mul/div/sqrt.  Do not build the first firmware, kernel, or userspace
with compressed `C`, double-precision `D`, or hard-float ABI assumptions yet;
enable Linux `CONFIG_FPU` only after FMA/rounding behavior, precise exception
flags, and FPU context switching have been validated.

## Files

| Path | Purpose |
| --- | --- |
| `dts/computer-rv32.dts` | Initial device tree for the DDR simulation platform. |
| `linux/linux.fragment` | Linux config fragment for early console and initramfs boot. |
| `linux/bootargs.txt` | Initial kernel command line. |
| `buildroot/computer_rv32_defconfig` | Starter Buildroot defconfig for RV32IMA soft-float initramfs. |
| `buildroot/overlay/init` | First userspace init script. |
| `opensbi/README.md` | OpenSBI build notes and fallback firmware contract. |
| `firmware/opensbi-lite` | Small M-mode jump firmware for the first Linux simulation. |
| `firmware/fwok-smoke` | Tiny firmware for fast DDR preload and UART-MMIO smoke tests. |
| `firmware/linux-smoke` | Tiny S-mode payload that prints the Linux banner before a real kernel is available. |
| `scripts/bin_to_ddr_preload.py` | Converts binary images into 128-bit DDR preload lines for XSim. |
| `scripts/build_boot_bundle.sh` | Builds firmware/DTB and packs a DDR preload bundle. |
| `scripts/build_fwok_smoke.sh` | Builds the fast FWOK DDR preload smoke image. |
| `scripts/build_linux_smoke_bundle.sh` | Builds OpenSBI-lite plus the S-mode Linux banner smoke image. |
| `scripts/make_initramfs.py` | Creates a simple uncompressed `newc` initramfs archive. |

## Simulation Smoke Builds

Build the fastest DDR firmware smoke:

```bash
bash software/scripts/build_fwok_smoke.sh
vivado -mode batch -source script/run_computer_ddr_linux_boot_xsim.tcl -tclargs --fwok_smoke
```

Expected pass marker:

```text
COMPUTER DDR OPENSBI-LITE UART PASS
```

Build the firmware plus S-mode Linux banner smoke:

```bash
DTC=/mnt/d/Xilinx/2025.1/Vivado/bin/dtc \
  bash software/scripts/build_linux_smoke_bundle.sh
vivado -mode batch -source script/run_computer_ddr_linux_boot_xsim.tcl -tclargs --linux_smoke
```

Expected pass marker:

```text
COMPUTER DDR LINUX BOOT PASS
```

This is still not a real Linux boot.  It proves that the same DDR preload
layout can start M-mode firmware, pass `a0/a1`, enter an S-mode payload at the
kernel address, and detect the Linux banner through the boot testbench.

## First Real Linux Build Shape

Build or obtain:

```text
computer-rv32.dtb
rootfs.cpio
arch/riscv/boot/Image
fw_payload.bin
```

Then convert the firmware payload for simulation:

```bash
python3 software/scripts/bin_to_ddr_preload.py \
  --image build/platform/generic/firmware/fw_payload.bin@0x00000000 \
  --output software/image/linux_preload.memh
```

The output format is one line per non-empty 16-byte DDR line:

```text
<byte-address-hex> <128-bit-data-hex>
```

The Verilog Linux boot testbench reads this file, writes each line through the
MIG app interface, then releases the CPU from reset.
