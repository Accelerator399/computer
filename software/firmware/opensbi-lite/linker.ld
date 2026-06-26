OUTPUT_ARCH(riscv)
ENTRY(_start)

SECTIONS
{
    . = FW_BASE;

    .text : ALIGN(4)
    {
        KEEP(*(.text.start))
        *(.text*)
    }

    .rodata : ALIGN(4)
    {
        *(.rodata*)
    }

    .data : ALIGN(4)
    {
        *(.sdata*)
        *(.data*)
    }

    .bss : ALIGN(4)
    {
        __bss_start = .;
        *(.sbss*)
        *(.bss*)
        *(COMMON)
        __bss_end = .;
    }

    . = ALIGN(16);
    __stack_bottom = .;
    . += STACK_SIZE;
    __stack_top = .;
}
