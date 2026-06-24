# Computer: CPU + Sv32 MMU + DDR Integration

This repository integrates the CPU from `../cache` with the MMU/cache/DDR
memory system from `../mmu` into one local RTL tree.  The current hardware is
ready to start Linux firmware, device-tree, kernel-image, and userspace
bring-up work:

```text
CPU virtual I/D addresses
    -> Sv32 MMU/satp CSR
    -> hardware page-table walker on TLB miss
    -> I-cache and D-cache
    -> 128-bit memory line interface
    -> simulation RAM or DDR3/MIG bridge
    -> CLINT / PLIC / ns16550-style UART MMIO
```

It is not yet a complete Linux board distribution.  The remaining work is now
mostly firmware and software description work: OpenSBI/OpenSBI-lite handoff,
DTS, kernel configuration/loading, and storage/initramfs.

## What Is Integrated

| Area | File | Notes |
| --- | --- | --- |
| CPU core | `src/cpu/` | Local copy of the CPU, extended for MMU integration, traps, byte strobes, atomics, and parameterized reset. |
| CSR/MMU connection | `src/cpu/csr.v`, `src/mmu/mmu.v` | CPU CSR writes to `satp` are forwarded to the MMU; `satp` writes and `SFENCE.VMA` flush stale TLB entries. |
| Sv32 translation | `src/mmu/mmu.v`, `src/mmu/mmu_tlb.v` | TLB entries are filled from two-level Sv32 page tables through a hardware walker; 4 KiB pages and 4 MiB level-1 superpages are implemented; `SUM/MXR`, `U`, `X/R/W`, and `A/D` checks are honored. |
| Page-fault trap path | `src/cpu/control.v`, `src/cpu/cpu.v` | Instruction/load/store page faults generate RISC-V causes 12/13/15 and set trap value. |
| Privileged trap/return path | `src/cpu/control.v`, `src/cpu/csr.v` | `ecall`, `ebreak`, `mret`, `sret`, trap delegation, S-mode interrupt delivery, `FENCE.I`, `WFI`, and read-only identity CSRs are covered by directed tests. |
| ISA target | `src/cpu/` | Practical software target is `rv32ima_zicsr_zifencei`; `misa` reports `0x4014_1101` (RV32 + A/I/M + S/U). Compressed (`C`) is not implemented. |
| RV32A atomics | `src/cpu/control.v`, `src/cpu/datapath.v` | Implements word LR/SC and AMO read-modify-write operations for early Linux atomic primitives. |
| Byte stores | `src/cpu/datapath.v` | Store byte/half/word produce `mem_wstrb`, needed by caches, MMIO, and Linux-style drivers. |
| CLINT | `src/io/clint.v` | Provides MSIP, `mtime`, and `mtimecmp`; timer/software interrupt outputs feed the CPU CSR interrupt path. |
| PLIC | `src/io/plic.v`, `src/integration/computer_core.v` | Two-source PLIC-style external interrupt controller with priority, pending, enable, threshold, and claim/complete registers. Source ID 1 is external `ext_int`; source ID 2 is UART IRQ. M-mode and delegated S-mode external interrupt paths are tested. |
| UART/GPIO IO mux | `src/io/iomux.v` | UART is ns16550-style MMIO with `reg-shift=2` over a 0x100-byte window; GPIO AFEN routes pad 9 as TX and pad 10 as RX. |
| Reset/boot path | `src/cpu/datapath.v`, `src/integration/boot_rom.v` | CPU reset vector is parameterized; optional boot ROM can serve instruction fetches before DDR firmware handoff. |
| Core integration | `src/integration/computer_core.v` | CPU + MMU + I-cache + D-cache + IO mux, with external 128-bit line memory ports. |
| Simulation top | `src/integration/top_sim.v` | Uses `simple_mem128` for quick functional simulation. |
| DDR/MIG bridge | `src/integration/computer_ddr_bridge.v` | Connects `computer_core` to the MMU project's MIG app-interface adapter. |
| Smoke test | `src/tb/tb_top_sim_smoke.v` | Self-checking test for instruction fetch, D-cache load/store, and byte write enable. |
| MMU walker test | `src/tb/tb_mmu_walker.v` | Self-checking Sv32 page-table walk, TLB fill, superpage, permission fault, `satp` flush, and `SFENCE.VMA` refill test. |
| DDR3 computer tests | `src/tb/tb_computer_ddr_smoke.v`, `src/tb/tb_computer_ddr_sv32.v` | Instantiate `clk_wiz_0`, `mig_7series_0`, DDR3 model, and the full computer DDR bridge for bare-mode and Sv32 DDR-backed simulations. |

## Run The Tests

Vivado 2025.1 is available in the current environment, so the tests use XSim
directly.

Core functional regressions:

```tcl
vivado -mode batch -source script/run_smoke_xsim.tcl
vivado -mode batch -source script/run_misaligned_xsim.tcl
vivado -mode batch -source script/run_mmu_walker_xsim.tcl
vivado -mode batch -source script/run_top_sim_sv32_xsim.tcl
```

Expected pass markers:

```text
SMOKE PASS
MISALIGNED CPU PASS
MMU WALKER PASS
TOP SIM SV32 PASS
```

Privileged ISA, interrupt, atomic, and firmware handoff regressions:

```tcl
vivado -mode batch -source script/run_privileged_xsim.tcl
vivado -mode batch -source script/run_clint_xsim.tcl
vivado -mode batch -source script/run_atomic_xsim.tcl
vivado -mode batch -source script/run_interrupt_xsim.tcl
vivado -mode batch -source script/run_boot_plic_xsim.tcl
vivado -mode batch -source script/run_uart_plic_xsim.tcl
vivado -mode batch -source script/run_computer_plic_irq_xsim.tcl
vivado -mode batch -source script/run_computer_smode_plic_irq_xsim.tcl
vivado -mode batch -source script/run_firmware_boot_xsim.tcl
```

Expected pass markers:

```text
PRIVILEGED CPU PASS
CLINT PASS
ATOMIC CPU PASS
INTERRUPT CPU PASS
BOOT/PLIC PASS
UART PLIC PASS
COMPUTER PLIC IRQ PASS
COMPUTER S-MODE PLIC IRQ PASS
FIRMWARE BOOT PASS
```

DDR3/MIG IP example simulation, using the MIG/clock IP configuration from
`../mmu`:

```tcl
vivado -mode batch -source ../mmu/script/create_project.tcl -tclargs --project_dir D:/code/vivado/computer/build/mmu_ip_check --project_name mmu_ip_check
vivado -mode batch -source script/run_mig_example_xsim.tcl
```

Expected end of log:

```text
PHY_INIT: Memory Initialization completed
TEST PASSED
```

Full computer DDR3 smoke test, using the same generated IP:

```tcl
vivado -mode batch -source script/run_computer_ddr_xsim.tcl
```

Expected end of log:

```text
PASS: MIG init_calib_complete asserted
PASS: DDR program line 0 = 05a00113040021830410202302a00093
PASS: DDR program line 1 = 000000000000006f04100203042000a3
PASS: CPU load after DDR-backed store x3 = 0000002a
PASS: load after DDR-backed byte store x4 = 0000005a
PASS: DDR line 0x40 word = 00005a2a
COMPUTER DDR SMOKE PASS
```

Full computer DDR3 Sv32 test, including page-table walks through the DDR3/MIG
path:

```tcl
vivado -mode batch -source script/run_computer_ddr_sv32_xsim.tcl
```

Expected end of log:

```text
PASS: MIG init_calib_complete asserted
PASS: S-mode load through 4MiB superpage x5 = 12345678
PASS: S-mode store/load through 4KiB page x6 = 12345678
PASS: S-mode payload completed after DDR Sv32 walks x7 = 0000005a
PASS: DDR3 destination line contains S-mode store data = ...12345678
COMPUTER DDR SV32 PASS
```

The DDR3 tests prove that the CPU fetches instructions from DDR3 through
I-cache, performs D-cache write-through/load/byte-store traffic through the real
MIG app interface, and can run S-mode payloads with Sv32 page-table walks
served by the same DDR path.

## Memory Integration Options

`computer_core` is intentionally memory-implementation neutral.  It exposes two
cache line ports and one read-only page-table walker port:

```verilog
icache_mem_req / icache_mem_addr / icache_mem_rdata / icache_mem_ready
dcache_mem_req / dcache_mem_addr / dcache_mem_wdata / dcache_mem_wstrb / dcache_mem_ready
walker_mem_req / walker_mem_addr / walker_mem_rdata / walker_mem_ready
```

Use one of these shells:

| Top | Purpose |
| --- | --- |
| `top_sim` | Runs the core against `simple_mem128` in simulation. |
| `computer_ddr_bridge` | Runs the core against the existing MIG app interface through `mmu_ddr_adapter`. |

For a board-level FPGA top, instantiate `computer_ddr_bridge` in the MIG
`ui_clk` domain, connect its `app_*` ports to the generated MIG instance, and
connect `pad[9]`/`pad[10]` to UART TX/RX as in the original cache project.

## Current Platform Map

The current integrated physical map is:

| Range | Device |
| --- | --- |
| `0x0000_0000` and up | DDR/simulation RAM, unless the optional boot ROM is enabled for a configured window. |
| `0x1000_0000 - 0x1000_ffff` | CLINT-style MSIP/mtime/mtimecmp block. |
| `0x1001_0000 - 0x1001_00ff` | ns16550-style UART, 32-bit spacing (`reg-shift=2`, `reg-io-width=4`). |
| `0x1002_0000 - 0x1002_000f` | GPIO and alternate-function enable. |
| `0x1003_0000 - 0x1042_ffff` | PLIC-style external interrupt controller, 2 sources. |

`computer_core` bypasses D-cache for physical MMIO.  When paging is enabled,
the MMIO devices see the translated physical address, so device mappings can be
described normally in a device tree.

Device-tree hints for the next software step:

```dts
uart0: serial@10010000 {
    compatible = "ns16550a";
    reg = <0x10010000 0x100>;
    reg-shift = <2>;
    reg-io-width = <4>;
    clock-frequency = <50000000>;
    interrupt-parent = <&plic>;
    interrupts = <2>;
};

plic: interrupt-controller@10030000 {
    compatible = "riscv,plic0";
    reg = <0x10030000 0x400000>;
    interrupt-controller;
    #interrupt-cells = <1>;
    riscv,ndev = <2>;
};
```

The UART pins still require GPIO alternate-function enable: set `gpio_afen[9]`
and `gpio_afen[10]` to route TX/RX to pads 9 and 10.

## Current Linux-Porting Status

The hardware blockers for an initial Linux bring-up are now closed enough to
move to firmware, DTS, kernel, and image-loading work.

| Requirement | Current status |
| --- | --- |
| Sv32 MMU | Hardware page-table walker fills TLBs from memory PTEs; 4 KiB pages and 4 MiB superpages are implemented; `satp` writes and `SFENCE.VMA` flush globally; permission checks cover `X/R/W/U/SUM/MXR/A/D`. Hardware does not write back `A/D`; keep a software-managed A/D trap path or add hardware writeback later. |
| Privileged ISA | M/S-mode CSR base, trap delegation, S-mode external interrupt delivery, `ecall/ebreak`, `mret/sret`, page-fault trap values, identity CSRs, `FENCE.I`, and NOP-style `WFI` are wired and tested. Remaining hardening includes WARL details, vectored trap mode, and broader conformance tests. |
| ISA extensions | CPU supports the practical target `rv32ima_zicsr_zifencei`; `misa=0x4014_1101`. Compressed (`C`) is absent, so Linux and firmware must be built without `C`. |
| Timer/interrupts | CLINT-style software/timer interrupts and a two-source PLIC are integrated. Source 1 is external `ext_int`; source 2 is UART IRQ. Both M-mode and delegated S-mode external interrupt paths have regressions. |
| Main memory | DDR3/MIG full-computer simulations pass in bare mode and Sv32 S-mode; page-table walks, instruction fetch, D-cache load/store, and byte stores all traverse the real MIG app interface in simulation. |
| Boot flow | Reset vector is parameterized, optional boot ROM exists, and a tiny M-mode firmware handoff into S-mode is tested. Remaining work is to load a real OpenSBI/OpenSBI-lite payload and kernel image. |
| Devices | ns16550-style UART is present for early console; GPIO exists; block/storage is not present, so initial Linux should use initramfs or add a storage device. |
| Cache management | `FENCE.I` invalidates I-cache. A full Linux cache maintenance/coherency contract should still be documented and stress-tested before larger drivers or DMA-style devices are added. |

See `docs/linux_porting_roadmap.md` for the remaining software bring-up
sequence and residual hardware hardening list.

## Directory Layout

```text
src/
  cpu/                  CPU local copy, extended for MMU/traps/wstrb/atomics
  io/                   ns16550-style UART/GPIO IO mux, CLINT, PLIC
  mmu/                  Sv32 MMU, TLB, 2-way cache, DDR adapter
  integration/          computer_core, boot ROM, simulation RAM top, DDR bridge
  tb/                   smoke and directed hardware testbenches
script/
  run_smoke_xsim.tcl
  run_misaligned_xsim.tcl
  run_mmu_walker_xsim.tcl
  run_top_sim_sv32_xsim.tcl
  run_privileged_xsim.tcl
  run_clint_xsim.tcl
  run_atomic_xsim.tcl
  run_interrupt_xsim.tcl
  run_boot_plic_xsim.tcl
  run_uart_plic_xsim.tcl
  run_computer_plic_irq_xsim.tcl
  run_computer_smode_plic_irq_xsim.tcl
  run_firmware_boot_xsim.tcl
  run_mig_example_xsim.tcl
  run_computer_ddr_xsim.tcl
  run_computer_ddr_sv32_xsim.tcl
docs/
  linux_porting_roadmap.md
```
