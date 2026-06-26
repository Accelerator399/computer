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
}
