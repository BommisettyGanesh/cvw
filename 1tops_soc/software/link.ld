OUTPUT_ARCH("riscv")
ENTRY(_start)

MEMORY
{
  ram (rwx) : ORIGIN = 0x80000000, LENGTH = 16K
}

SECTIONS
{
  .text : {
    *(.text._start)
    *(.text*)
    *(.rodata*)
  } > ram

  .data : {
    *(.data*)
    *(.sdata*)
  } > ram

  .bss : {
    __bss_start = .;
    *(.bss*)
    *(.sbss*)
    __bss_end = .;
  } > ram

  . = ALIGN(8);
  /* Stack will be placed at the end of RAM by crt0 */
}
