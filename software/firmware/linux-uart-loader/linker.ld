OUTPUT_ARCH(riscv)
ENTRY(_start)

MEMORY
{
    imem (rx)  : ORIGIN = 0x00000000, LENGTH = 0x00008000
    dmem (rw)  : ORIGIN = 0x00008000, LENGTH = 0x00008000
}

SECTIONS
{
    .text : {
        *(.text.init)
        *(.text.trap)
        *(.text)
        *(.text.*)
    } > imem

    .rodata : {
        *(.srodata)
        *(.srodata.*)
        *(.rodata)
        *(.rodata.*)
    } > dmem

    .data : {
        *(.sdata)
        *(.sdata.*)
        *(.data)
        *(.data.*)
    } > dmem

    .bss (NOLOAD) : {
        . = ALIGN(16);
        _bss_start = .;
        *(.sbss)
        *(.sbss.*)
        *(.bss)
        *(.bss.*)
        *(COMMON)
        . = ALIGN(16);
        _bss_end = .;
    } > dmem

    . = ALIGN(16);
    _m_stack_top = ORIGIN(dmem) + LENGTH(dmem) - 16;
}
