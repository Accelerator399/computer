# Linux Banner Smoke Payload

This is not Linux.  It is a tiny S-mode payload used to test the same DDR/XSim
boot path before a real kernel image is available.

`opensbi-lite` enters this image at physical `0x00400000` with `a0 = 0` and
`a1 = 0x00800000`.  The payload checks those boot arguments, writes
`Hello from RV32 Linux on computer` to the UART THR MMIO register, and loops.

The Linux boot testbench uses the same banner that the first initramfs `/init`
will print later, so this smoke test proves the firmware-to-S-mode handoff and
DDR payload layout without requiring a Linux toolchain yet.
