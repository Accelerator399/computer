#define UART_BASE 0x10010000
#define UART_THR  0x00

    .section .text.start, "ax", @progbits
    .globl _start
    .option push
    .option norvc

_start:
    bnez    a0, bad_boot
    li      t0, DTB_ADDR
    bne     a1, t0, bad_boot

    li      t0, UART_BASE
    la      t1, linux_banner

1:
    lbu     t2, 0(t1)
    beqz    t2, done
    sw      t2, UART_THR(t0)
    addi    t1, t1, 1
    j       1b

done:
    wfi
    j       done

bad_boot:
    li      t0, UART_BASE
    la      t1, bad_boot_banner
2:
    lbu     t2, 0(t1)
    beqz    t2, done
    sw      t2, UART_THR(t0)
    addi    t1, t1, 1
    j       2b

    .section .rodata, "a", @progbits
linux_banner:
    .asciz "Hello from RV32 Linux on computer"
bad_boot_banner:
    .asciz "BADBOOT"

    .option pop
