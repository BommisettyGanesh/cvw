/* =============================================================================
 * Linker Script for Google RISCV-DV / Torture Tests on Pure CPU Core
 * Memory: 2 MB RAM starting at 0x80000000
 * ============================================================================= */

OUTPUT_ARCH("riscv")
ENTRY(_start)

MEMORY
{
  RAM (rwx) : ORIGIN = 0x80000000, LENGTH = 2048K
}

SECTIONS
{
  . = 0x80000000;

  .text.init : {
    KEEP(*(.text.init))
  } > RAM

  . = ALIGN(64);
  .tohost : {
    tohost = .;
    KEEP(*(.tohost))
  } > RAM

  .text : {
    . = ALIGN(4);
    *(.text .text.*)
  } > RAM

  .rodata : {
    . = ALIGN(4);
    *(.rodata .rodata.*)
  } > RAM

  .data : {
    . = ALIGN(4);
    *(.data .data.*)
    PROVIDE(__global_pointer$ = . + 0x800);
  } > RAM

  .bss : {
    . = ALIGN(4);
    *(.bss .bss.*)
  } > RAM

  _end = .;
  PROVIDE(__stack = 0x801FF000);
}
