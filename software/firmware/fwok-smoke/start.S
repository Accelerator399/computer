#define UART_BASE 0x10010000

    .section .text.start, "ax", @progbits
    .globl _start
    .option push
    .option norvc

_start:
    li      t0, UART_BASE

    li      t1, 'F'
    sw      t1, 0(t0)
    li      t1, 'W'
    sw      t1, 0(t0)
    li      t1, 'O'
    sw      t1, 0(t0)
    li      t1, 'K'
    sw      t1, 0(t0)

1:
    j       1b

    .option pop
