# OpenSBI Build Notes

First Linux simulation target:

```bash
make PLATFORM=generic \
     PLATFORM_RISCV_XLEN=32 \
     FW_PAYLOAD_PATH=/path/to/linux/arch/riscv/boot/Image \
     FW_FDT_PATH=/path/to/computer-rv32.dtb
```

Expected output:

```text
build/platform/generic/firmware/fw_payload.bin
build/platform/generic/firmware/fw_payload.elf
```

Use `software/scripts/bin_to_ddr_preload.py` to convert `fw_payload.bin` into a
DDR preload file for `tb_computer_ddr_linux_boot`.

If generic OpenSBI assumes a PLIC/CLINT detail that this RTL does not yet
provide, the fallback is a tiny custom M-mode firmware with these jobs:

1. Set up `mtvec`, `medeleg`, `mideleg`, `mie`, and `mstatus`.
2. Enable GPIO alternate functions for UART pads 9 and 10 if serial is needed
   before Linux configures the UART.
3. Put hart ID 0 in `a0`.
4. Put the DTB physical address in `a1`.
5. Clear `satp`.
6. Set `mstatus.MPP=S`, set `mepc` to the Linux Image address, and execute
   `mret`.
