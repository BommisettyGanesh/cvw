OUTPUT_ARCH( "riscv" )
ENTRY(_start)

SECTIONS
{
  . = 0x80000000;
  .init : { *(.init) }
  .text : { *(.text) }
  .data : { *(.data) }
  .sdata : { *(.sdata) }
  .bss : { *(.bss) }
  _end = .;
}
