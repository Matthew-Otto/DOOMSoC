ENTRY(_start)

MEMORY
{
    ROM (rx)  : ORIGIN = 0x20000000, LENGTH = 8K
    RAM (rwx) : ORIGIN = 0x80000000, LENGTH = 8M
}

__stack_top = ORIGIN(RAM) + LENGTH(RAM) - 16;

SECTIONS
{
    .boot : {
        KEEP(*(.boot))
    } > ROM

    .text : {
        *(.text*)
        *(.rodata*)
        . = ALIGN(4);
    } > ROM

    .data : {
        . = ALIGN(4);
        _sdata = .;
        *(.data*)
        . = ALIGN(4);
        _edata = .;
    } > RAM AT > ROM

    _sidata = LOADADDR(.data);

    .bss : {
        . = ALIGN(4);
        _sbss = .;
        *(.bss*)
        *(COMMON)
        . = ALIGN(4);
        _ebss = .;
    } > RAM
}