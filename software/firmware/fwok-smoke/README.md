# FWOK Smoke Firmware

This tiny RV32IMA firmware is only for the DDR/XSim Linux boot harness smoke
test.  It starts at physical `0x00000000`, writes `FWOK` to the UART THR MMIO
register at `0x10010000`, and loops forever.

It deliberately does not poll UART busy status.  The testbench observes the
CPU's MMIO writes directly, so this keeps the DDR3/MIG simulation short while
still proving that the CPU fetched and executed code from the preloaded DDR
image.
