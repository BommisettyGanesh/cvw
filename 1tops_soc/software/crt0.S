.section .text._start
.global _start

_start:
    # Initialize stack pointer to end of 8KB dmem (0x80002000 + 8192)
    li sp, 0x80004000

    # Clear BSS
    la a0, __bss_start
    la a1, __bss_end
    bge a0, a1, end_clear_bss
clear_bss:
    sw zero, 0(a0)
    addi a0, a0, 4
    blt a0, a1, clear_bss
end_clear_bss:

    # Jump to main
    call main

    # Infinite loop if main returns
inf_loop:
    j inf_loop
