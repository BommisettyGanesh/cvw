.section .init
.global _start
.type _start, @function

_start:
    /* Set stack pointer to top of RAM */
    li sp, 0x87FFFFF0
    /* Call main function */
    call main

_halt:
    j _halt
