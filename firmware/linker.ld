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
    } > ROM

    .data : {
        *(.data*)
    } > RAM

    .bss : {
        *(.bss*)
        *(COMMON)
    } > RAM
}