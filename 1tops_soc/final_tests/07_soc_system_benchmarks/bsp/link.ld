/* =============================================================================
 * Linker Script for RISC-V AHB-Lite Bare-Metal System (RV32I)
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
    KEEP(*(.tohost))
  } > RAM

  .text : {
    . = ALIGN(4);
    *(.text .text.*)
  } > RAM

  .rodata : {
    . = ALIGN(4);
    *(.rodata .rodata.*)
    *(.srodata .srodata.*)
  } > RAM

  .data : {
    . = ALIGN(4);
    *(.data .data.*)
  } > RAM

  .sdata : {
    . = ALIGN(4);
    __global_pointer$ = . + 0x800;
    *(.sdata .sdata.*)
  } > RAM

  .sbss : {
    . = ALIGN(4);
    __bss_start = .;
    *(.sbss .sbss.*)
  } > RAM

  .bss : {
    . = ALIGN(4);
    *(.bss .bss.*)
    *(COMMON)
    . = ALIGN(4);
    __bss_end = .;
  } > RAM

  _end = .;
  PROVIDE(__stack_top = 0x801FF000);
}
