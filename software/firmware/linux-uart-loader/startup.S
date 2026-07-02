.option norvc

.macro UART_PUTC_REG reg
.Luart_wait_\@:
    lw t5, 20(t3)
    andi t5, t5, 0x20
    beqz t5, .Luart_wait_\@
    sw \reg, 0(t3)
.endm

.macro UART_PUTC_IMM value
    li t4, \value
    UART_PUTC_REG t4
.endm

.macro UART_PUTC_U32 reg
    mv t4, \reg
    UART_PUTC_REG t4
    srli t4, \reg, 8
    UART_PUTC_REG t4
    srli t4, \reg, 16
    UART_PUTC_REG t4
    srli t4, \reg, 24
    UART_PUTC_REG t4
.endm

.section .text.init, "ax"
.globl _start
_start:
    la sp, _m_stack_top
    csrw mscratch, sp
    la t0, machine_trap_entry
    csrw mtvec, t0

    la t0, _bss_start
    la t1, _bss_end
1:
    bgeu t0, t1, 2f
    sw zero, 0(t0)
    addi t0, t0, 4
    j 1b
2:
    call boot_main

3:
    wfi
    j 3b

.section .text.trap, "ax"
.align 2
.globl machine_trap_entry
machine_trap_entry:
    csrr t0, mcause
#ifdef LINUX_BOOT_DEBUG_TRAPS
    li t1, 9
    beq t0, t1, 1f
    li t1, 4
    beq t0, t1, 1f
    li t1, 6
    beq t0, t1, 1f

    csrw satp, zero
    sfence.vma
    fence.i

    mv s0, t0
    csrr s1, mepc
    csrr s2, mtval
    mv s3, a0
    mv s4, a1

    li t3, 0x10010000
    UART_PUTC_IMM 13
    UART_PUTC_IMM 10
    UART_PUTC_IMM 88
    UART_PUTC_IMM 67
    UART_PUTC_U32 s0
    UART_PUTC_IMM 69
    UART_PUTC_U32 s1
    UART_PUTC_IMM 86
    UART_PUTC_U32 s2
    UART_PUTC_IMM 65
    UART_PUTC_U32 s3
    UART_PUTC_IMM 66
    UART_PUTC_U32 s4
    UART_PUTC_IMM 13
    UART_PUTC_IMM 10

2:
    wfi
    j 2b
1:
#endif
    csrrw sp, mscratch, sp
    addi sp, sp, -128

    sw x1,   4(sp)
    sw x3,  12(sp)
    sw x4,  16(sp)
    sw x5,  20(sp)
    csrr x5, mscratch
    sw x5,   8(sp)
    sw x6,  24(sp)
    sw x7,  28(sp)
    sw x8,  32(sp)
    sw x9,  36(sp)
    sw x10, 40(sp)
    sw x11, 44(sp)
    sw x12, 48(sp)
    sw x13, 52(sp)
    sw x14, 56(sp)
    sw x15, 60(sp)
    sw x16, 64(sp)
    sw x17, 68(sp)
    sw x18, 72(sp)
    sw x19, 76(sp)
    sw x20, 80(sp)
    sw x21, 84(sp)
    sw x22, 88(sp)
    sw x23, 92(sp)
    sw x24, 96(sp)
    sw x25, 100(sp)
    sw x26, 104(sp)
    sw x27, 108(sp)
    sw x28, 112(sp)
    sw x29, 116(sp)
    sw x30, 120(sp)
    sw x31, 124(sp)

    mv a0, sp
    call machine_trap

    lw x1,   4(sp)
    lw x3,  12(sp)
    lw x4,  16(sp)
    lw x6,  24(sp)
    lw x7,  28(sp)
    lw x8,  32(sp)
    lw x9,  36(sp)
    lw x10, 40(sp)
    lw x11, 44(sp)
    lw x12, 48(sp)
    lw x13, 52(sp)
    lw x14, 56(sp)
    lw x15, 60(sp)
    lw x16, 64(sp)
    lw x17, 68(sp)
    lw x18, 72(sp)
    lw x19, 76(sp)
    lw x20, 80(sp)
    lw x21, 84(sp)
    lw x22, 88(sp)
    lw x23, 92(sp)
    lw x24, 96(sp)
    lw x25, 100(sp)
    lw x26, 104(sp)
    lw x27, 108(sp)
    lw x28, 112(sp)
    lw x29, 116(sp)
    lw x30, 120(sp)
    lw x31, 124(sp)
    lw x5,  20(sp)

    addi sp, sp, 128
    csrrw sp, mscratch, sp
    mret
