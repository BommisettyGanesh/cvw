/* =============================================================================
 * Startup Code for RISC-V AHB-Lite Bare-Metal System (RV32I)
 * Initializes registers, stack pointer, clears BSS, and calls main()
 * ============================================================================= */

  .section ".text.init", "ax", @progbits
  .globl _start
  .type _start, @function

_start:
  /* Zero out integer registers x1-x31 */
  li  x1, 0
  li  x2, 0
  li  x3, 0
  li  x4, 0
  li  x5, 0
  li  x6, 0
  li  x7, 0
  li  x8, 0
  li  x9, 0
  li  x10, 0
  li  x11, 0
  li  x12, 0
  li  x13, 0
  li  x14, 0
  li  x15, 0
  li  x16, 0
  li  x17, 0
  li  x18, 0
  li  x19, 0
  li  x20, 0
  li  x21, 0
  li  x22, 0
  li  x23, 0
  li  x24, 0
  li  x25, 0
  li  x26, 0
  li  x27, 0
  li  x28, 0
  li  x29, 0
  li  x30, 0
  li  x31, 0

  /* Set stack pointer */
  la  sp, __stack_top

  /* Initialize global pointer */
.option push
.option norelax
  la  gp, __global_pointer$
.option pop

  /* Set default trap handler */
  la  t0, trap_entry
  csrw mtvec, t0

  /* Clear BSS section */
  la  t0, __bss_start
  la  t1, __bss_end
bss_clear_loop:
  bgeu t0, t1, bss_clear_done
  sw   zero, 0(t0)
  addi t0, t0, 4
  j    bss_clear_loop
bss_clear_done:

  /* Call main(0, NULL) */
  li   a0, 0
  li   a1, 0
  jal  ra, main

  /* Main returned: write exit code to tohost */
  la   t0, tohost
  /* Encode exit code: (a0 << 1) | 1, or 1 for success if a0 == 0 */
  slli t1, a0, 1
  ori  t1, t1, 1
  sw   t1, 0(t0)

exit_loop:
  wfi
  j    exit_loop

  .align 4
trap_entry:
  /* On unexpected trap, write error code 0x1337 to tohost */
  la   t0, tohost
  li   t1, 0x1337
  sw   t1, 0(t0)
trap_halt:
  wfi
  j    trap_halt

/* tohost communication section */
  .section ".tohost", "aw", @progbits
  .align 6
  .globl tohost
tohost:
  .word 0
  .word 0

  .align 6
  .globl fromhost
fromhost:
  .word 0
  .word 0
