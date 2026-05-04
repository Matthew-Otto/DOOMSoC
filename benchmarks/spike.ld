OUTPUT_ARCH("riscv")
ENTRY(_start)

MEMORY {
  RAM (rwx)   : ORIGIN = 0x80000000, LENGTH = 16M
  HOSTIO (rw) : ORIGIN = 0x90000000, LENGTH = 100
}

SECTIONS {
  .tohost : ALIGN(4) {
    KEEP(*(.tohost))
  } > HOSTIO

  .fromhost : ALIGN(4) {
    KEEP(*(.fromhost))
  } > HOSTIO

  .text : ALIGN(4) {
    KEEP(*(.text.start))
    *(.text*)
    . = ALIGN(4);
  } > RAM =0

  .rodata : ALIGN(4) {
    *(.rodata*)
    . = ALIGN(4);
  } > RAM =0

  .data : ALIGN(4) {
    *(.data*)
    . = ALIGN(4);
  } > RAM =0

  .bss : ALIGN(4) {
    *(.bss*)
    *(COMMON)
    . = ALIGN(4);
  } > RAM 
}