    .section .text.start, "ax", @progbits
    .globl _start
    .option push
    .option norvc

#define SYS_write   64
#define SYS_reboot  142

#define LINUX_REBOOT_MAGIC1       0xfee1dead
#define LINUX_REBOOT_MAGIC2       672274793
#define LINUX_REBOOT_CMD_POWER_OFF 0x4321fedc

_start:
    la      a1, banner
    li      a0, 1
    la      t0, banner_end
    sub     a2, t0, a1
    li      a7, SYS_write
    ecall

    li      a0, LINUX_REBOOT_MAGIC1
    li      a1, LINUX_REBOOT_MAGIC2
    li      a2, LINUX_REBOOT_CMD_POWER_OFF
    li      a3, 0
    li      a7, SYS_reboot
    ecall

1:
    j       1b

    .section .rodata, "a", @progbits
banner:
    .ascii "Hello from real RV32 Linux kernel on computer\n"
banner_end:

    .option pop
