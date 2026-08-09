// ==============================================================================
// CORE-V-Wally Complete RTL Filelist for my_minimal_rv32
// Top Module: wallypipelinedsoc (or wallypipelinedcore)
// ==============================================================================

+incdir+config
+incdir+src

// SystemVerilog Package Definition
src/cvw.sv

// Uncore / Peripherals / Bus
src/uncore/ahbapbbridge.sv
src/uncore/clint_apb.sv
src/uncore/gpio_apb.sv
src/uncore/plic_apb.sv
src/uncore/ram_ahb.sv
src/uncore/rom_ahb.sv
src/uncore/spi_apb.sv
src/uncore/spi_controller.sv
src/uncore/spi_fifo.sv
src/uncore/trickbox_apb.sv
src/uncore/uartPC16550D.sv
src/uncore/uart_apb.sv
src/uncore/uncore.sv

// Generic Memory Primitives
src/generic/mem/*.sv

// Core Submodules
src/cache/*.sv
src/ebu/*.sv
src/fpu/*.sv
src/hazard/*.sv
src/ieu/*.sv
src/ifu/*.sv
src/ifu/bpred/*.sv
src/lsu/*.sv
src/mdu/*.sv
src/mmu/*.sv
src/privileged/*.sv

// Top Level Modules
src/wally/wallypipelinedcore.sv
src/wally/wallypipelinedsoc.sv
