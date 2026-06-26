# OpenSBI-Lite Firmware

This is a small M-mode firmware for the first simulation Linux bring-up on the
local RV32IMA computer.  It is not a full OpenSBI replacement, but it provides
the pieces needed to start a uniprocessor S-mode kernel:

- configure trap delegation for S-mode Linux;
- enable the UART pad alternate functions;
- pass `a0 = 0` and `a1 = DTB_ADDR`;
- enter S-mode at `LINUX_ENTRY` with `satp = 0`;
- print the short `FWOK` marker for simulation smoke tests;
- handle a minimal set of SBI calls for timer, base probing, legacy console,
  IPI no-op, and RFENCE no-op.

Build in WSL:

```bash
cd /mnt/d/code/vivado/computer
make -C software/firmware/opensbi-lite
```

Useful build-time addresses:

```bash
make -C software/firmware/opensbi-lite \
  LINUX_ENTRY=0x00400000 \
  DTB_ADDR=0x00800000 \
  FW_BASE=0x00000000
```

The default output is:

```text
build/software/opensbi-lite/fw_jump.elf
build/software/opensbi-lite/fw_jump.bin
```

Load `fw_jump.bin` at physical `0x00000000`, the Linux `Image` at
`0x00400000`, and the DTB at `0x00800000`.
