OUTPUT_ARCH(riscv)
ENTRY(_start)

SECTIONS
{
    . = PAYLOAD_BASE;

    .text : {
        KEEP(*(.text.start))
        *(.text*)
    }

    .rodata : {
        *(.rodata*)
    }

    . = ALIGN(4);
    .data : {
        *(.sdata*)
        *(.data*)
    }

    . = ALIGN(4);
    .bss : {
        __bss_start = .;
        *(.sbss*)
        *(.bss*)
        *(COMMON)
        __bss_end = .;
    }
}
