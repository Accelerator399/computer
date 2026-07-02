#define UART_BASE           0x10010000
#define UART_THR            0x00
#define UART_LSR            0x14
#define UART_LSR_THRE       0x20
#define GPIO_AFEN           0x1002000c
#define UART_PAD_MASK       0x00000600
#define CLINT_MTIMECMP      0x10004000

#define MSTATUS_MPP_S       0x00000800
#define MIP_STIP            0x00000020
#define MIE_MTIE            0x00000080
#define MEDELEG_VALUE       0x0000b1ff
#define MIDELEG_VALUE       0x00000222
#define MCAUSE_MACHINE_TIMER 0x80000007

#define SBI_SUCCESS         0
#define SBI_ERR_NOT_SUPPORTED -2

#define SBI_EXT_LEGACY_SET_TIMER      0x0
#define SBI_EXT_LEGACY_CONSOLE_PUTCHAR 0x1
#define SBI_EXT_LEGACY_CONSOLE_GETCHAR 0x2
#define SBI_EXT_LEGACY_SHUTDOWN       0x8
#define SBI_EXT_BASE                  0x10
#define SBI_EXT_TIME                  0x54494d45
#define SBI_EXT_IPI                   0x735049
#define SBI_EXT_RFENCE                0x52464e43

    .section .text.start, "ax", @progbits
    .globl _start
    .option push
    .option norvc

_start:
    la      t0, trap_vector
    csrw    mtvec, t0
    la      t0, __stack_top
    csrw    mscratch, t0

    li      t0, MEDELEG_VALUE
    csrw    medeleg, t0
    li      t0, MIDELEG_VALUE
    csrw    mideleg, t0

    csrw    satp, zero
    sfence.vma
    fence.i

    li      t0, GPIO_AFEN
    li      t1, UART_PAD_MASK
    sw      t1, 0(t0)

    call    emit_fwok

    li      a0, 0
    li      a1, DTB_ADDR
    li      t0, LINUX_ENTRY
    csrw    mepc, t0
    li      t0, MSTATUS_MPP_S
    csrw    mstatus, t0
    mret

zero_bss:
    la      t0, __bss_start
    la      t1, __bss_end
1:
    bgeu    t0, t1, 2f
    sw      zero, 0(t0)
    addi    t0, t0, 4
    j       1b
2:
    ret

puts:
    addi    sp, sp, -4
    sw      ra, 0(sp)
    mv      t2, a0
1:
    lbu     a0, 0(t2)
    beqz    a0, 2f
    call    putchar
    addi    t2, t2, 1
    j       1b
2:
    lw      ra, 0(sp)
    addi    sp, sp, 4
    ret

putchar:
    li      t0, UART_BASE
1:
    lw      t1, UART_LSR(t0)
    andi    t1, t1, UART_LSR_THRE
    beqz    t1, 1b
    sw      a0, UART_THR(t0)
    ret

emit_fwok:
    li      t0, UART_BASE
    li      t1, 'F'
1:
    lw      t2, UART_LSR(t0)
    andi    t2, t2, UART_LSR_THRE
    beqz    t2, 1b
    sw      t1, UART_THR(t0)
    li      t1, 'W'
2:
    lw      t2, UART_LSR(t0)
    andi    t2, t2, UART_LSR_THRE
    beqz    t2, 2b
    sw      t1, UART_THR(t0)
    li      t1, 'O'
3:
    lw      t2, UART_LSR(t0)
    andi    t2, t2, UART_LSR_THRE
    beqz    t2, 3b
    sw      t1, UART_THR(t0)
    li      t1, 'K'
4:
    lw      t2, UART_LSR(t0)
    andi    t2, t2, UART_LSR_THRE
    beqz    t2, 4b
    sw      t1, UART_THR(t0)
    ret

trap_vector:
    csrrw   sp, mscratch, sp
    addi    sp, sp, -64
    sw      ra, 0(sp)
    sw      t0, 4(sp)
    sw      t1, 8(sp)
    sw      t2, 12(sp)
    sw      t3, 16(sp)
    sw      t4, 20(sp)
    sw      t5, 24(sp)
    sw      t6, 28(sp)
    sw      a2, 32(sp)
    sw      a3, 36(sp)
    sw      a4, 40(sp)
    sw      a5, 44(sp)
    sw      a6, 48(sp)
    sw      a7, 52(sp)

    csrr    t0, mcause
    li      t1, MCAUSE_MACHINE_TIMER
    beq     t0, t1, trap_machine_timer
    li      t1, 9
    bne     t0, t1, trap_panic

    csrr    t0, mepc
    addi    t0, t0, 4
    csrw    mepc, t0

    li      t0, SBI_EXT_TIME
    beq     a7, t0, sbi_time
    li      t0, SBI_EXT_BASE
    beq     a7, t0, sbi_base
    li      t0, SBI_EXT_IPI
    beq     a7, t0, sbi_success
    li      t0, SBI_EXT_RFENCE
    beq     a7, t0, sbi_success
    li      t0, SBI_EXT_LEGACY_SET_TIMER
    beq     a7, t0, sbi_legacy_set_timer
    li      t0, SBI_EXT_LEGACY_CONSOLE_PUTCHAR
    beq     a7, t0, sbi_legacy_putchar
    li      t0, SBI_EXT_LEGACY_CONSOLE_GETCHAR
    beq     a7, t0, sbi_legacy_getchar
    li      t0, SBI_EXT_LEGACY_SHUTDOWN
    beq     a7, t0, sbi_shutdown
    j       sbi_not_supported

sbi_time:
    bnez    a6, sbi_not_supported
sbi_legacy_set_timer:
    li      t0, CLINT_MTIMECMP
    li      t1, -1
    sw      t1, 4(t0)
    sw      a0, 0(t0)
    sw      a1, 4(t0)
    li      t0, MIP_STIP
    csrc    mip, t0
    li      t0, MIE_MTIE
    csrs    mie, t0
    j       sbi_success

trap_machine_timer:
    li      t0, MIE_MTIE
    csrc    mie, t0
    li      t0, MIP_STIP
    csrs    mip, t0
    j       trap_return

sbi_base:
    beqz    a6, sbi_get_spec_version
    li      t0, 1
    beq     a6, t0, sbi_get_impl_id
    li      t0, 2
    beq     a6, t0, sbi_get_impl_version
    li      t0, 3
    beq     a6, t0, sbi_probe_extension
    li      t0, 4
    beq     a6, t0, sbi_zero_value
    li      t0, 5
    beq     a6, t0, sbi_marchid
    li      t0, 6
    beq     a6, t0, sbi_mimpid
    j       sbi_not_supported

sbi_get_spec_version:
    li      a0, SBI_SUCCESS
    li      a1, 2
    j       trap_return

sbi_get_impl_id:
    li      a0, SBI_SUCCESS
    li      a1, 0
    j       trap_return

sbi_get_impl_version:
    li      a0, SBI_SUCCESS
    li      a1, 1
    j       trap_return

sbi_probe_extension:
    li      a1, 0
    li      t0, SBI_EXT_BASE
    beq     a0, t0, 1f
    li      t0, SBI_EXT_TIME
    beq     a0, t0, 1f
    li      t0, SBI_EXT_IPI
    beq     a0, t0, 1f
    li      t0, SBI_EXT_RFENCE
    bne     a0, t0, 2f
1:
    li      a1, 1
2:
    li      a0, SBI_SUCCESS
    j       trap_return

sbi_marchid:
    li      a0, SBI_SUCCESS
    li      a1, 1
    j       trap_return

sbi_mimpid:
    li      a0, SBI_SUCCESS
    li      a1, 1
    j       trap_return

sbi_zero_value:
    li      a0, SBI_SUCCESS
    li      a1, 0
    j       trap_return

sbi_legacy_putchar:
    call    putchar
    j       sbi_success

sbi_legacy_getchar:
    li      a0, -1
    li      a1, 0
    j       trap_return

sbi_success:
    li      a0, SBI_SUCCESS
    li      a1, 0
    j       trap_return

sbi_not_supported:
    li      a0, SBI_ERR_NOT_SUPPORTED
    li      a1, 0
    j       trap_return

sbi_shutdown:
    la      a0, shutdown_msg
    call    puts
1:
    wfi
    j       1b

trap_panic:
    la      a0, trap_msg
    call    puts
1:
    wfi
    j       1b

trap_return:
    lw      ra, 0(sp)
    lw      t0, 4(sp)
    lw      t1, 8(sp)
    lw      t2, 12(sp)
    lw      t3, 16(sp)
    lw      t4, 20(sp)
    lw      t5, 24(sp)
    lw      t6, 28(sp)
    lw      a2, 32(sp)
    lw      a3, 36(sp)
    lw      a4, 40(sp)
    lw      a5, 44(sp)
    lw      a6, 48(sp)
    lw      a7, 52(sp)
    addi    sp, sp, 64
    csrrw   sp, mscratch, sp
    mret

    .section .rodata, "a", @progbits
trap_msg:
    .asciz "OpenSBI-lite: unexpected M-mode trap\r\n"
shutdown_msg:
    .asciz "OpenSBI-lite: shutdown\r\n"

    .option pop
