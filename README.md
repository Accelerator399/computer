# Computer 硬件项目说明

本仓库是一套基于 Verilog/Vivado 的 RV32 计算机硬件工程。项目重点是把自研 CPU、Sv32 MMU、Cache、CLINT、PLIC、UART/GPIO、DDR3/MIG 桥接和 FPGA 顶层整合成一个可仿真、可上板、可继续扩展的 SoC。

Linux 相关内容在本项目中主要是硬件能力的验证场景之一，用来检验特权级、MMU、中断、DDR 和串口启动链路；README 的主体仍然围绕硬件结构、模块边界、地址映射和验证方法展开。

## 硬件总览

```text
computer_top_fpga
  -> clk_wiz_0 / mig_7series_0 / DDR3 pins
  -> 可选 UART DDR loader 或 boot ROM/RAM 固件
  -> mig_app_cdc_bridge
  -> computer_ddr_bridge
       -> computer_core
            -> cpu
            -> Sv32 mmu + TLB + page-table walker
            -> I-cache / D-cache
            -> CLINT / PLIC / UART / GPIO / optional Ethernet Lite MMIO
       -> mmu_ddr_adapter
       -> MIG app interface
```

CPU 侧的指令、数据和页表访问都以 128-bit cache line 形式进入存储系统：

```text
CPU virtual I/D address
  -> Sv32 translation
  -> physical address
  -> I-cache / D-cache / walker memory port
  -> simple_mem128 in simulation, or DDR3 through MIG
```

## 主要硬件模块

| 层级 | 文件 | 作用 |
| --- | --- | --- |
| FPGA 顶层 | `src/fpga/computer_top_fpga.v` | 板级顶层，连接外部时钟、复位、UART、DDR3、可选 Ethernet Lite，引入 `clk_wiz_0` 和 `mig_7series_0`。 |
| SoC DDR 桥 | `src/integration/computer_ddr_bridge.v` | 将 `computer_core` 的 128-bit line memory ports 接到 MIG app 接口。 |
| SoC 核心 | `src/integration/computer_core.v` | 集成 CPU、MMU、I-cache、D-cache、CLINT、PLIC、UART/GPIO、可选 Ethernet Lite MMIO。 |
| CPU | `src/cpu/cpu.v` | 顶层 CPU，连接 control、datapath、CSR、乘除法、FPU、异常和中断路径。 |
| 控制器 | `src/cpu/control.v` | 多周期状态机，负责取指、执行、访存、CSR、trap、AMO、DIV/FPU wait 等控制。 |
| 数据通路 | `src/cpu/datapath.v` | PC、寄存器堆、立即数、ALU、访存地址/写掩码、CSR 写数据、trap value 等数据路径。 |
| CSR | `src/cpu/csr.v` | M/S 模式 CSR、trap delegation、`mstatus`、`mepc/sepc`、`mtvec/stvec`、`satp` 外部转发、中断 pending/enable。 |
| MMU | `src/mmu/mmu.v` | Sv32 地址翻译、`satp`、TLB miss 控制、两级页表遍历、权限检查和 page fault 输出。 |
| TLB | `src/mmu/mmu_tlb.v` | I/D translation lookup、TLB refill、4 KiB page 与 4 MiB superpage 映射。 |
| Cache | `src/mmu/cache.v` | 2-way set-associative cache，16 sets，16-byte line，write-through，支持 byte write strobe。 |
| DDR adapter | `src/mmu/mmu_ddr_adapter.v` | 将 I-cache、D-cache、walker 三路 128-bit line 请求仲裁到 MIG app 接口。 |
| CLINT | `src/io/clint.v` | MSIP、`mtime`、`mtimecmp`，产生 machine software/timer interrupt。 |
| PLIC | `src/io/plic.v` | 简化 PLIC，支持 priority、pending、enable、threshold、claim/complete。 |
| UART/GPIO IOMUX | `src/io/iomux.v` | ns16550-style UART 寄存器、GPIO dir/out/in/afen、pad 复用。 |
| UART | `src/io/uart/` | 波特率发生器、TX、RX、frame error、ready/busy 信号。 |
| Boot ROM/RAM | `src/integration/boot_rom.v`, `src/integration/boot_ram.v` | 可选片上启动存储，用于固件启动和 FPGA bring-up。 |
| 仿真 RAM | `src/integration/simple_mem128.v` | XSim 快速仿真的 128-bit line memory。 |
| FPGA UART DDR loader | `src/fpga/uart_ddr_loader.v` | 板级串口 DDR 预加载器，通过 UART 写入 MIG app line。 |
| CDC bridge | `src/fpga/mig_app_cdc_bridge.v` | CPU clock domain 与 MIG `ui_clk` domain 之间的 app 请求/响应桥。 |
| AXI-Lite bridge | `src/fpga/axi_lite_mmio_bridge.v` | 将 SoC MMIO 请求桥接到 AXI-Lite 外设，目前用于可选 AXI Ethernet Lite。 |

## CPU 与 ISA 支持

CPU 是一个多周期 RV32 核心，`control.v` 负责状态机控制，`datapath.v` 负责寄存器、ALU、访存和 trap 数据路径。CPU 对外使用简洁的取指和访存接口，由 `computer_core` 在外层接入 MMU/cache。

当前硬件覆盖的主要 ISA/特权能力：

| 类别 | 状态 |
| --- | --- |
| RV32I | 基础整数指令、分支跳转、load/store、byte/half/word 写掩码。 |
| Zicsr | CSR read/write/set/clear，含 M/S 模式常用 CSR。 |
| Zifencei | `FENCE.I` 接入 I-cache flush。 |
| RV32M | `MUL/MULH/MULHSU/MULHU` 与 `DIV/DIVU/REM/REMU`。除法为多周期 restoring divider。 |
| RV32A | Word LR/SC 与 AMO read-modify-write，用于原子操作。 |
| RV32F | 单精度浮点寄存器、load/store、move/sign/min/max/compare/classify、int/float convert、add/sub/mul/div/sqrt。 |
| 特权级 | M/S/U 模式基础路径、trap delegation、`mret/sret`、interrupt delivery、page fault cause/value。 |
| 未实现 | 压缩指令 `C` 未实现；双精度 `D` 未实现。 |

硬件 `misa` 当前报告 RV32 + A/F/I/M + S/U，值为 `0x4014_1121`。如果只需要整数或资源更紧张的 FPGA 构建，可以通过工程脚本关闭 FPU。

## MMU、TLB 与 Cache

### Sv32 MMU

`src/mmu/mmu.v` 实现 RISC-V Sv32 地址翻译：

- `satp[31]` 作为 Sv32 enable，M-mode 默认 bypass。
- I/D 两路 translation lookup，共享硬件 page-table walker。
- TLB miss 时执行两级页表遍历。
- 支持 4 KiB page 和 4 MiB level-1 superpage。
- `satp` 写入或 `SFENCE.VMA` 会触发 TLB flush。
- 检查 `V/R/W/X/U/A/D`，以及 `mstatus.SUM`、`mstatus.MXR`。
- page fault 分别返回 instruction/load/store page fault 路径。

当前 walker 不会自动写回 PTE 的 `A/D` bit；当 `A=0` 或 store 遇到 `D=0` 时会触发 page fault。这是一个明确的硬件策略，后续可以选择保持软件管理，也可以扩展硬件写回。

### Cache

`src/mmu/cache.v` 是 I-cache/D-cache 复用的 cache 模块：

| 参数 | 当前值 |
| --- | --- |
| 组数 | 16 sets |
| 路数 | 2 ways |
| 行大小 | 16 bytes / 128 bits |
| 地址拆分 | `{tag[31:8], index[7:4], offset[3:0]}` |
| 替换策略 | 每组 1-bit LRU |
| 写策略 | Write-through |
| 写粒度 | 4-bit CPU byte strobe，转换为 16-bit line strobe |

I-cache 可由 `FENCE.I` flush；D-cache 对 MMIO 地址旁路，避免外设访问被缓存。

## 存储系统

`computer_core` 不绑定具体内存实现，只暴露三组 128-bit line 端口：

```verilog
icache_mem_req / icache_mem_addr / icache_mem_rdata / icache_mem_ready
dcache_mem_req / dcache_mem_addr / dcache_mem_wdata / dcache_mem_wstrb / dcache_mem_ready
walker_mem_req / walker_mem_addr / walker_mem_rdata / walker_mem_ready
```

不同场景使用不同外壳：

| 外壳 | 文件 | 用途 |
| --- | --- | --- |
| 仿真 RAM | `src/integration/top_sim.v`, `src/integration/simple_mem128.v` | 快速 XSim 功能仿真。 |
| DDR/MIG | `src/integration/computer_ddr_bridge.v` | 将核心接到 MIG app interface。 |
| FPGA 顶层 | `src/fpga/computer_top_fpga.v` | 板级 DDR3、时钟、复位、UART/loader 和可选 Ethernet Lite。 |

FPGA 顶层中 DDR 物理基址为 `0x8000_0000`，MIG app 地址宽度默认为 27 bit，对应当前脚本和 DTS 中使用的 128 MiB DDR 窗口。

## 外设与 MMIO

### CLINT

`src/io/clint.v` 实现一个简化 CLINT：

| offset | 寄存器 |
| --- | --- |
| `0x0000` | `msip` |
| `0x4000` | `mtimecmp[31:0]` |
| `0x4004` | `mtimecmp[63:32]` |
| `0xbff8` | `mtime[31:0]` |
| `0xbffc` | `mtime[63:32]` |

`mtime` 每个时钟周期自增；`mtime >= mtimecmp` 输出 timer interrupt；`msip[0]` 输出 software interrupt。

### PLIC

`src/io/plic.v` 当前配置为 2 个 source：

| Source ID | 来源 |
| --- | --- |
| 1 | 外部 `ext_int` 输入 |
| 2 | UART IRQ |

PLIC 支持 priority、pending、enable、threshold、claim/complete。当前模型面向单核/单 context bring-up，足够覆盖外部中断路径；如果后续增加更多外设或多 context，需要继续扩展。

### UART/GPIO

`src/io/iomux.v` 提供 ns16550-style UART register window 和简单 GPIO：

| 区域 | 内容 |
| --- | --- |
| UART `0x1001_0000 - 0x1001_00ff` | RBR/THR、IER、IIR/FCR accept、LCR/DLAB、MCR、LSR、MSR=0、SCR。 |
| GPIO `0x1002_0000 - 0x1002_000f` | `gpio_dir`、`gpio_out`、`pad` input、`gpio_afen`。 |

UART 采用 32-bit spacing，因此软件侧可按 `reg-shift=2`、`reg-io-width=4` 描述。GPIO alternate-function 复用如下：

| Pad | 功能 |
| --- | --- |
| 9 | `gpio_afen[9]=1` 时作为 UART TX。 |
| 10 | `gpio_afen[10]=1` 时作为 UART RX。 |

### 可选 Ethernet Lite

`computer_top_fpga.v` 可以通过 `COMPUTER_ENABLE_ETHERNET_LITE` 或工程脚本 `--enable_ethernet_lite` 接入 Xilinx AXI Ethernet Lite IP。SoC 内部通过 `axi_lite_mmio_bridge.v` 将 MMIO 请求转为 AXI-Lite。当前主要用于上板镜像快速加载实验，不是核心硬件必选项。

## 地址映射

| 地址范围 | 设备 |
| --- | --- |
| `0x0000_0000` 起 | 仿真 RAM 或可选 boot ROM 窗口。 |
| `0x0000_8000` 起 | 可选 boot RAM 默认窗口。 |
| `0x8000_0000 - 0x87ff_ffff` | FPGA DDR3 物理窗口，默认 128 MiB。 |
| `0x1000_0000 - 0x1000_ffff` | CLINT。 |
| `0x1001_0000 - 0x1001_00ff` | UART。 |
| `0x1002_0000 - 0x1002_000f` | GPIO/IOMUX。 |
| `0x1003_0000 - 0x1042_ffff` | PLIC，当前 2 个 source。 |
| `0x1044_0000 - 0x1044_1fff` | 可选 AXI Ethernet Lite。 |

注意：部分 XSim DDR preload 测试为了简化，会直接使用 MIG app line 地址从 `0x0000_0000` 写入测试程序；FPGA 上板运行时的 CPU 物理 DDR 窗口是 `0x8000_0000` 起。

## FPGA 顶层

板级顶层 `src/fpga/computer_top_fpga.v` 包含：

- `clk_wiz_0`：输入 100 MHz，输出 CPU clock 和 MIG 所需 200 MHz。
- `mig_7series_0`：DDR3 控制器。
- `mig_app_cdc_bridge`：跨 CPU clock 和 MIG `ui_clk`。
- `uart_ddr_loader`：默认可在 CPU release 前通过 UART 写入 DDR line。
- `computer_ddr_bridge`：核心 SoC + DDR adapter。
- 可选 `axi_ethernetlite_0`：由脚本参数启用。

主要构建参数由 `script/create_computer_fpga_project.tcl` 注入：

| 参数/define | 说明 |
| --- | --- |
| `COMPUTER_CLK_FREQ` | CPU 时钟和外设时钟参数，默认 `100000000`。 |
| `COMPUTER_ENABLE_FPU` | 是否启用 FPU，默认启用。 |
| `COMPUTER_LOADER_BAUD_RATE` | FPGA UART DDR loader 波特率，默认 `230400`。 |
| `COMPUTER_USE_UART_DDR_LOADER` | 是否使用板级 UART DDR loader。 |
| `COMPUTER_BOOT_ROM_ENABLE` | 是否启用 boot ROM。 |
| `COMPUTER_BOOT_RAM_ENABLE` | 是否启用 boot RAM。 |
| `COMPUTER_ENABLE_ETHERNET_LITE` | 是否实例化 AXI Ethernet Lite。 |

## 仿真验证

Vivado/XSim 脚本位于 `script/`。常用硬件回归如下。

### CPU 与基础 SoC

```tcl
vivado -mode batch -source script/run_smoke_xsim.tcl
vivado -mode batch -source script/run_div_xsim.tcl
vivado -mode batch -source script/run_misaligned_xsim.tcl
vivado -mode batch -source script/run_fpu_xsim.tcl
vivado -mode batch -source script/run_privileged_xsim.tcl
vivado -mode batch -source script/run_atomic_xsim.tcl
vivado -mode batch -source script/run_interrupt_xsim.tcl
```

对应 pass marker：

```text
SMOKE PASS
DIV CPU PASS
MISALIGNED CPU PASS
FPU CPU PASS
PRIVILEGED CPU PASS
ATOMIC CPU PASS
INTERRUPT CPU PASS
```

### MMU、外设与集成中断

```tcl
vivado -mode batch -source script/run_mmu_walker_xsim.tcl
vivado -mode batch -source script/run_top_sim_sv32_xsim.tcl
vivado -mode batch -source script/run_clint_xsim.tcl
vivado -mode batch -source script/run_boot_plic_xsim.tcl
vivado -mode batch -source script/run_uart_plic_xsim.tcl
vivado -mode batch -source script/run_computer_plic_irq_xsim.tcl
vivado -mode batch -source script/run_computer_smode_plic_irq_xsim.tcl
```

对应 pass marker：

```text
MMU WALKER PASS
TOP SIM SV32 PASS
CLINT PASS
BOOT/PLIC PASS
UART PLIC PASS
COMPUTER PLIC IRQ PASS
COMPUTER S-MODE PLIC IRQ PASS
```

### DDR3/MIG

DDR3/MIG 仿真依赖生成好的 MIG/clock IP。先生成 IP 工程：

```tcl
vivado -mode batch -source ../mmu/script/create_project.tcl -tclargs --project_dir D:/code/vivado/computer/build/mmu_ip_check --project_name mmu_ip_check
```

再运行：

```tcl
vivado -mode batch -source script/run_mig_example_xsim.tcl
vivado -mode batch -source script/run_computer_ddr_xsim.tcl
vivado -mode batch -source script/run_computer_ddr_sv32_xsim.tcl
```

对应 pass marker：

```text
TEST PASSED
COMPUTER DDR SMOKE PASS
COMPUTER DDR SV32 PASS
```

### 启动链路 smoke

这些测试用于验证 boot ROM/RAM、DDR preload、固件跳转和 UART 输出，不是 README 的主线，但对硬件集成很有用：

```tcl
vivado -mode batch -source script/run_firmware_boot_xsim.tcl
vivado -mode batch -source script/run_branch_handoff_xsim.tcl
vivado -mode batch -source script/run_core_branch_handoff_xsim.tcl
vivado -mode batch -source script/run_core_linux_smoke_xsim.tcl
vivado -mode batch -source script/run_core_linux_smoke_preload_xsim.tcl
```

```text
FIRMWARE BOOT PASS
BRANCH HANDOFF PASS
CORE BRANCH HANDOFF PASS
CORE LINUX SMOKE PASS
CORE LINUX PRELOAD SMOKE PASS
```

## Vivado FPGA 工程

生成工程：

```tcl
vivado -mode batch -source script/create_computer_fpga_project.tcl
```

生成 bitstream：

```tcl
vivado -mode batch -source script/create_computer_fpga_project.tcl -tclargs --build
```

常用参数：

| 参数 | 说明 |
| --- | --- |
| `--build` | 创建工程后直接综合、实现并生成 bitstream。 |
| `--disable_fpu` | 关闭 FPU，减少资源占用。 |
| `--clk_freq_hz <hz>` | 设置 CPU clock，默认 `100000000`。 |
| `--loader_baud <baud>` | UART DDR loader 波特率。 |
| `--linux_uart_boot` | 启用 boot ROM/RAM 固件启动路径。 |
| `--enable_ethernet_lite` | 加入 AXI Ethernet Lite IP。 |
| `--project_dir <path>` | 指定 Vivado 工程输出目录。 |
| `--jobs <n>` | 并行任务数。 |

下载 bitstream：

```tcl
vivado -mode batch -source script/program_computer_fpga.tcl -tclargs --bit path/to/computer_top_fpga.bit
```

## Vivado FPU IP

FPU wrapper 可以使用 Vivado Floating Point IP。生成脚本：

```tcl
vivado -mode batch -source script/create_fpu_ip.tcl -tclargs --project_dir build/fpu_ip_check --project_name fpu_ip_check
```

生成的 IP 名称：

```text
fp_add_s
fp_sub_s
fp_mul_s
fp_div_s
fp_sqrt_s
```

XSim 的 FPU smoke 默认有 fallback 模型，因此普通仿真不强制依赖这些 IP；综合到 FPGA 并启用真实 FPU IP 时，需要将输出产物加入工程并定义 `USE_VIVADO_FPU_IP`。

## 软件与固件的位置

软件目录主要服务硬件验证和启动实验：

| 路径 | 作用 |
| --- | --- |
| `software/firmware/fwok-smoke` | 最小 UART MMIO smoke 固件。 |
| `software/firmware/opensbi-lite` | 小型 M-mode 固件，用于特权级和 S-mode handoff 验证。 |
| `software/firmware/linux-smoke` | S-mode banner payload，用于验证 MMU/DDR/UART 启动链路。 |
| `software/firmware/linux-uart-loader` | 上板启动固件，可通过 UART/UDP 接收镜像后跳转。 |
| `software/dts/computer-rv32.dts` | 描述当前硬件地址和中断拓扑的 DTS。 |
| `software/scripts/` | preload 转换、固件构建、串口/UDP 上传辅助脚本。 |

这些内容不是硬件模块本身，但它们能帮助验证 CPU、MMU、DDR 和外设是否按预期工作。

## 目录结构

```text
src/
  cpu/                  CPU、CSR、控制器、数据通路、执行单元
  cpu/utils/            ALU、乘除法、寄存器堆、FPU 等工具模块
  mmu/                  Sv32 MMU、TLB、cache、DDR adapter
  io/                   CLINT、PLIC、IOMUX、UART
  integration/          computer_core、DDR bridge、boot ROM/RAM、仿真 top
  fpga/                 FPGA 顶层、UART DDR loader、CDC、AXI-Lite bridge
  tb/                   定向 testbench 与 smoke 程序

constraints/
  computer_top_fpga.xdc
  computer_ethernet_lite.xdc

script/
  run_*_xsim.tcl
  create_computer_fpga_project.tcl
  create_fpu_ip.tcl
  program_computer_fpga.tcl

software/
  firmware/
  scripts/
  dts/
  linux/
  buildroot/

docs/
  linux_porting_roadmap.md
```

## 当前硬件限制与后续方向

- `C` 压缩指令未实现。
- `D` 双精度浮点未实现。
- RV32F 已有主要单精度路径，但完整 FPU 异常标志、舍入模式细节和系统级上下文管理仍需继续验证。
- Sv32 walker 目前不写回 PTE `A/D` bit。
- PLIC 是单核/少量 source 的简化实现。
- `SFENCE.VMA` 当前按全局 flush 处理，尚未做 ASID/地址选择性 flush。
- cache 与 DMA 一致性契约尚未扩展；添加 DMA 外设前需要明确硬件策略。
- 当前没有块存储控制器；如需完整系统应用，可继续添加 SPI/SD/块设备。

## 推荐阅读顺序

如果第一次看这个项目，建议按下面顺序读 RTL：

1. `src/integration/computer_core.v`：先看 SoC 内部如何连 CPU、MMU、cache 和 MMIO。
2. `src/cpu/cpu.v`：看 CPU 顶层接口和 control/datapath/CSR 的连接。
3. `src/mmu/mmu.v` 与 `src/mmu/cache.v`：看地址翻译和 cache-line 访问。
4. `src/io/iomux.v`、`src/io/clint.v`、`src/io/plic.v`：看外设寄存器模型。
5. `src/integration/computer_ddr_bridge.v`：看核心如何连到 MIG。
6. `src/fpga/computer_top_fpga.v`：最后看板级时钟、DDR、loader 和可选 Ethernet Lite。

修改硬件后，优先跑对应 testbench，再跑集成 DDR/MIG 测试，这样比较容易定位问题属于 CPU、MMU、cache、外设还是板级集成。
