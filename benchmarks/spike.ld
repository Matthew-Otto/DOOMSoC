OUTPUT_ARCH("riscv")
ENTRY(_start)

MEMORY {
  RAM (rwx)   : ORIGIN = 0x80000000, LENGTH = 16M
  HOSTIO (rw) : ORIGIN = 0x90000000, LENGTH = 100
}

SECTIONS {
  .tohost : {
    KEEP(*(.tohost))
  } > HOSTIO

  .fromhost : {
    KEEP(*(.fromhost))
  } > HOSTIO

  .text : {
    KEEP(*(.text.start))
    *(.text*)
  } > RAM

  .rodata : {
    *(.rodata*)
  } > RAM

  .data : {
    *(.data*)
  } > RAM

  .bss : {
    *(.bss*)
    *(COMMON)
  } > RAM
}
