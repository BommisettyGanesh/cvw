.section .text.init         # assembler directives
.globl rvtest_entry_point   # linker expects this global variable ath the start of the program
rvtest_entry_point:
    li a0, 42

self_loop:
    j self_loop
