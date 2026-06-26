# Linux Porting Roadmap

The RTL in `computer/` has reached the hardware-preparation milestone for an
initial Linux bring-up.  CPU, CSR path, Sv32 MMU, caches, CLINT, PLIC,
ns16550-style UART, simulation RAM, and DDR3/MIG integration are now tied
together and covered by directed XSim regressions.

The next phase is software bring-up: firmware handoff, device tree, Linux
configuration, image loading, and a first root filesystem strategy.

## 1. Frozen Hardware Map

Use this map for firmware and DTS work:

```text
0x0000_0000 - ...           DDR/simulation RAM, unless optional boot ROM is enabled
0x1000_0000 - 0x1000_ffff   CLINT-style MSIP/mtime/mtimecmp block
0x1001_0000 - 0x1001_00ff   ns16550-style UART, reg-shift=2, reg-io-width=4
0x1002_0000 - 0x1002_000f   GPIO and alternate-function enable
0x1003_0000 - 0x1042_ffff   PLIC-style interrupt controller, 2 sources
```

PLIC source IDs:

| ID | Source |
| --- | --- |
| 1 | External `ext_int` input. |
| 2 | UART interrupt from `iomux`. |

UART pad routing:

| Pad | Function |
| --- | --- |
| 9 | UART TX when `gpio_afen[9]` is set. |
| 10 | UART RX when `gpio_afen[10]` is set. |

`computer_core` bypasses the D-cache for MMIO.  With paging enabled, devices
see translated physical addresses, so Linux can describe them normally in the
device tree.

## 2. Current Hardware Status

| Requirement | Status |
| --- | --- |
| ISA target | Baseline Linux target is still `rv32ima_zicsr_zifencei` soft-float. Hardware `misa` reports `0x4014_1121` for RV32 + A/F/I/M + S/U. Compressed (`C`) is not implemented. |
| RV32M divider | `DIV/DIVU/REM/REMU` use a handwritten multi-cycle restoring divider behind the CPU `DIV_WAIT` state, including RISC-V divide-by-zero and signed-overflow behavior. |
| RV32F FPU | Single-precision hardware path is present for `FLW/FSW`, moves, sign injection, min/max, compare, classify, int/float conversion, `FADD.S`, `FSUB.S`, `FMUL.S`, `FDIV.S`, and `FSQRT.S`, with `fflags/frm/fcsr` CSRs and `mstatus.FS` dirty tracking. Vivado Floating Point IP generation is scripted by `script/create_fpu_ip.tcl`. |
| Sv32 translation | Hardware walker fills TLBs from memory page tables. 4 KiB pages and 4 MiB level-1 superpages are implemented. `satp` writes and `SFENCE.VMA` flush globally. `X/R/W/U/SUM/MXR/A/D` checks are implemented. |
| Accessed/dirty policy | Software-managed. The walker faults when `A=0`, or when a store sees `D=0`; it does not write PTE `A/D` bits back to memory. Linux firmware/kernel work must handle these faults or the RTL can later grow hardware `A/D` writeback. |
| Privileged ISA | M/S-mode CSR base, trap delegation, S-mode external interrupt delivery, `ecall/ebreak`, `mret/sret`, page-fault trap values, identity CSRs, `FENCE.I`, and NOP-style `WFI` are wired and tested. |
| Timer/software interrupts | CLINT provides MSIP, `mtime`, and `mtimecmp`; machine timer/software interrupt paths are tested. |
| External interrupts | PLIC has priority, pending, enable, threshold, and claim/complete registers for 2 sources. M-mode external interrupt and delegated S-mode external interrupt delivery are tested. |
| UART | UART is ns16550-style enough for 8250/earlycon style software: RBR/THR, IER, IIR/FCR accept, LCR/DLAB, MCR, LSR, MSR=0, SCR. |
| DDR3 path | The full computer runs through generated `clk_wiz_0`, generated `mig_7series_0`, the DDR3 model, and the real MIG app interface in both bare mode and Sv32 S-mode simulations. |
| Boot path | Reset vector is parameterized. Optional boot ROM exists. A tiny M-mode firmware handoff into S-mode is tested. |

This status is enough to start Linux bring-up.  The remaining tasks are not
core CPU/MMU/DDR/PLIC blockers; they are firmware, DTS, kernel-image, and
system-integration work.

## 3. Device-Tree Starting Point

Use this as a starting point, then adjust memory size, CPU clock, and interrupt
parent encoding to match the final firmware/kernel expectations:

```dts
/dts-v1/;

/ {
    #address-cells = <1>;
    #size-cells = <1>;
    compatible = "local,computer-rv32";
    model = "Local RV32IMA Computer";

    chosen {
        stdout-path = "serial0:115200n8";
    };

    cpus {
        #address-cells = <1>;
        #size-cells = <0>;
        timebase-frequency = <50000000>;

        cpu0: cpu@0 {
            device_type = "cpu";
            reg = <0>;
            compatible = "riscv";
            riscv,isa = "rv32ima_zicsr_zifencei";
            mmu-type = "riscv,sv32";

            cpu0_intc: interrupt-controller {
                #interrupt-cells = <1>;
                interrupt-controller;
                compatible = "riscv,cpu-intc";
            };
        };
    };

    memory@0 {
        device_type = "memory";
        reg = <0x00000000 0x08000000>;
    };

    soc {
        #address-cells = <1>;
        #size-cells = <1>;
        compatible = "simple-bus";
        ranges;

        clint: timer@10000000 {
            compatible = "riscv,clint0";
            reg = <0x10000000 0x10000>;
            interrupts-extended = <&cpu0_intc 3>, <&cpu0_intc 7>;
        };

        uart0: serial@10010000 {
            compatible = "ns16550a";
            reg = <0x10010000 0x100>;
            reg-shift = <2>;
            reg-io-width = <4>;
            clock-frequency = <50000000>;
            interrupt-parent = <&plic>;
            interrupts = <2>;
        };

        gpio0: gpio@10020000 {
            compatible = "local,gpio";
            reg = <0x10020000 0x10>;
        };

        plic: interrupt-controller@10030000 {
            compatible = "riscv,plic0";
            reg = <0x10030000 0x400000>;
            interrupt-controller;
            #interrupt-cells = <1>;
            riscv,ndev = <2>;
            interrupts-extended = <&cpu0_intc 11>, <&cpu0_intc 9>;
        };
    };
};
```

Notes:

1. The memory size above is a placeholder. Match it to the board/MIG address
   range used for the real run.
2. The platform currently has no block device. Use an initramfs for the first
   Linux boot, or add a storage device before trying a disk-backed rootfs.
3. If firmware does not enable UART pad alternate functions itself, do it before
   expecting serial output.

## 4. Firmware Bring-Up Plan

The next useful milestone is an OpenSBI-like M-mode payload that enters Linux in
S-mode.

Recommended order:

1. Build firmware for `rv32ima_zicsr_zifencei`, with compressed instructions
   disabled.
2. Initialize stack, `mtvec`, `medeleg`, `mideleg`, `mie`, `mstatus`, and UART
   pad mux.
3. Set up or pass a flat device tree pointer according to the Linux RISC-V boot
   protocol.
4. Configure `satp` only if the firmware needs virtual memory; otherwise leave
   Linux to enable Sv32.
5. Delegate S-mode timer, software, and external interrupt causes as needed.
6. Enter the kernel in S-mode with the expected `a0` hart ID and `a1` FDT
   pointer.
7. Start with earlycon/8250 console and initramfs.

## 5. Kernel Configuration Hints

Use a conservative first target:

```text
ARCH=riscv
XLEN=32
ISA=rv32ima_zicsr_zifencei
MMU=Sv32
No compressed instruction requirement
Soft-float for the first Linux boot
Early console through ns16550a/8250
Rootfs through initramfs first
```

Important software assumptions:

| Area | Initial choice |
| --- | --- |
| Console | `earlycon=uart8250,mmio32,0x10010000,115200n8` or equivalent DTS-driven 8250 console. |
| Root filesystem | Initramfs until a block/storage device is added. |
| Floating point | Keep `CONFIG_FPU=n` and use soft-float for the first Linux image. The RTL now covers most scalar RV32F operations, but a hard-float Linux target still needs FMA/rounding-mode hardening, precise exception flag plumbing, and broader FPU context-switch validation. |
| PTE `A/D` | Use a software-managed accessed/dirty fault path, or add RTL writeback before relying on hardware-managed `A/D`. |
| Timer | Use CLINT `mtime/mtimecmp`; verify the `timebase-frequency` value against the real clock. |
| Interrupt controller | Start with the simple PLIC map above; harden multi-context behavior later if mainline drivers need stricter behavior. |

## 6. Verification Matrix

These regressions are the current hardware readiness gate:

| Command | Pass marker | What it proves |
| --- | --- | --- |
| `vivado -mode batch -source script/run_smoke_xsim.tcl` | `SMOKE PASS` | CPU, cache path, load/store, byte strobes against simulation RAM. |
| `vivado -mode batch -source script/run_div_xsim.tcl` | `DIV CPU PASS` | Handwritten RV32M `DIV/DIVU/REM/REMU` behavior, including signed truncation, divide-by-zero, and signed-overflow cases. |
| `vivado -mode batch -source script/run_misaligned_xsim.tcl` | `MISALIGNED CPU PASS` | Misaligned trap behavior. |
| `vivado -mode batch -source script/run_fpu_xsim.tcl` | `FPU CPU PASS` | RV32F register file, `FLW/FSW`, moves, sign injection, min/max, compare, classify, conversions, add/sub/mul/div/sqrt, `misa.F`, and `fcsr` smoke coverage. |
| `vivado -mode batch -source script/run_mmu_walker_xsim.tcl` | `MMU WALKER PASS` | Sv32 page-table walk, TLB fill/refill, superpage, permission faults, `satp`, and `SFENCE.VMA`. |
| `vivado -mode batch -source script/run_top_sim_sv32_xsim.tcl` | `TOP SIM SV32 PASS` | Integrated top-level Sv32 execution against simulation RAM. |
| `vivado -mode batch -source script/run_privileged_xsim.tcl` | `PRIVILEGED CPU PASS` | M/S CSR behavior, delegation, `mret`, `sret`, `FENCE.I`, `WFI`, identity CSRs. |
| `vivado -mode batch -source script/run_clint_xsim.tcl` | `CLINT PASS` | MSIP, `mtime`, `mtimecmp`, write strobes, interrupt outputs. |
| `vivado -mode batch -source script/run_atomic_xsim.tcl` | `ATOMIC CPU PASS` | LR/SC and AMO word operations. |
| `vivado -mode batch -source script/run_interrupt_xsim.tcl` | `INTERRUPT CPU PASS` | Machine timer/software interrupt entry and return. |
| `vivado -mode batch -source script/run_boot_plic_xsim.tcl` | `BOOT/PLIC PASS` | Reset vector, boot ROM hit/miss behavior, PLIC register behavior. |
| `vivado -mode batch -source script/run_uart_plic_xsim.tcl` | `UART PLIC PASS` | ns16550-style UART registers and UART interrupt source through PLIC. |
| `vivado -mode batch -source script/run_computer_plic_irq_xsim.tcl` | `COMPUTER PLIC IRQ PASS` | Integrated machine external interrupt through the full computer. |
| `vivado -mode batch -source script/run_computer_smode_plic_irq_xsim.tcl` | `COMPUTER S-MODE PLIC IRQ PASS` | Delegated S-mode external interrupt through PLIC with `scause=0x80000009`. |
| `vivado -mode batch -source script/run_firmware_boot_xsim.tcl` | `FIRMWARE BOOT PASS` | Minimal M-mode firmware handoff into S-mode payload. |
| `vivado -mode batch -source script/run_mig_example_xsim.tcl` | `TEST PASSED` | Generated MIG/DDR3 IP example design and DDR3 model. |
| `vivado -mode batch -source script/run_computer_ddr_xsim.tcl` | `COMPUTER DDR SMOKE PASS` | Full computer bare-mode instruction fetch and data traffic through real MIG app interface. |
| `vivado -mode batch -source script/run_computer_ddr_sv32_xsim.tcl` | `COMPUTER DDR SV32 PASS` | Full computer S-mode Sv32 execution, DDR-backed page-table walks, 4 MiB superpage load, 4 KiB page store/load, and DDR readback. |
| `vivado -mode batch -source script/run_computer_ddr_linux_boot_xsim.tcl -tclargs --fwok_smoke` | `COMPUTER DDR OPENSBI-LITE UART PASS` | DDR preload through MIG, CPU reset release, and first firmware MMIO output from DDR-resident code. |
| `vivado -mode batch -source script/run_computer_ddr_linux_boot_xsim.tcl -tclargs --linux_smoke` | `COMPUTER DDR LINUX BOOT PASS` | OpenSBI-lite starts from DDR, passes `a0/a1`, enters an S-mode payload at the Linux entry address, and emits the first Linux banner marker. |

## 7. Residual Hardware Hardening

These are useful follow-ups, but they are no longer blockers for starting the
Linux software port:

| Area | Follow-up |
| --- | --- |
| PLIC conformance | Expand toward a fuller multi-context PLIC model if the chosen kernel driver requires stricter behavior. |
| `SFENCE.VMA` | Current implementation flushes globally. Add ASID/address-selective flush later for performance and spec completeness. |
| CSR WARL behavior | Harden reserved/unsupported CSR fields against privileged architecture conformance tests. |
| Trap vectors | Direct mode is enough for bring-up; vectored mode can be added later. |
| Cache model | Document and stress-test the cache maintenance/coherency contract before adding DMA-capable devices. |
| Full Linux FPU enablement | Add FMA or mask the extension contract accordingly, harden rounding-mode behavior, wire precise IP exception flags into `fflags`, and validate lazy/eager FPU context management before enabling `CONFIG_FPU=y` or hard-float userspace. |
| PTE `A/D` writeback | Optional hardware improvement; current software-managed policy is clear and testable. |
| Storage | Add SPI/SD/block storage when moving beyond initramfs. |

## Current Milestone

Hardware preparation for Linux bring-up is complete enough to begin the
software port.  The key verified milestones are:

```text
UART PLIC PASS
COMPUTER S-MODE PLIC IRQ PASS
FIRMWARE BOOT PASS
COMPUTER DDR SMOKE PASS
COMPUTER DDR SV32 PASS
COMPUTER DDR OPENSBI-LITE UART PASS
FPU CPU PASS
```

The next concrete deliverable should be a real RV32IMA soft-float Linux `Image` plus
initramfs/rootfs bundle.  The firmware, DTS, DDR preload format, FWOK smoke,
and S-mode Linux banner smoke are now in place for that handoff.
