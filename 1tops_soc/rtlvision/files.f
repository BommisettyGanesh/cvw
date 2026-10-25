// -----------------------------------------------------------------------------
// RTLvision PRO Filelist for CORE-V Wally RV32 SoC (1tops_soc)
// -----------------------------------------------------------------------------

// Include directories
+incdir+../config
+incdir+../src
+incdir+../schematics
+incdir+../src/debugger

// SystemVerilog Package (Must be parsed before modules using cvw::*)
../src/cvw.sv

// Top-Level SoC Wrapper (instantiates wallypipelinedsoc with cvw_t P parameter)
../schematics/wallypipelinedsocwrapper.sv

// Accelerator
../src/accelerator/multiplier_ahb.sv

// Debugger Subsystem
../src/debugger/ahb_mux.sv
../src/debugger/core_step_controller.sv
../src/debugger/riscv_debugger_top.sv
../src/debugger/socdebug_adp_control.v
../src/debugger/socdebug_ahb.v
../src/debugger/socdebug_ft1248_control.v
../src/debugger/socdebug_uart.v

// External Bus Unit (EBU)
../src/ebu/ahbinterface.sv
../src/ebu/busfsm.sv
../src/ebu/controllerinput.sv
../src/ebu/ebufsmarb.sv
../src/ebu/ebu.sv

// Generic components & memory
../src/generic/adder.sv
../src/generic/counter.sv
../src/generic/decoder.sv
../src/generic/flop/flopenl.sv
../src/generic/flop/flopenrc.sv
../src/generic/flop/flopenr.sv
../src/generic/flop/flopen.sv
../src/generic/flop/flopr.sv
../src/generic/flop/flop.sv
../src/generic/flop/synchronizer.sv
../src/generic/mem/ram1p1rwbe_64x128.sv
../src/generic/mem/ram1p1rwbe_64x22.sv
../src/generic/mem/ram1p1rwbe_64x44.sv
../src/generic/mem/ram1p1rwbe.sv
../src/generic/mem/rom1p1r_128x32.sv
../src/generic/mem/rom1p1r_128x64.sv
../src/generic/mem/rom1p1r.sv
../src/generic/mux.sv
../src/generic/priorityonehot.sv

// Hazard Detection Unit
../src/hazard/hazard.sv

// Integer Execution Unit (IEU)
../src/ieu/alu.sv
../src/ieu/comparator.sv
../src/ieu/controller.sv
../src/ieu/datapath.sv
../src/ieu/extend.sv
../src/ieu/ieu.sv
../src/ieu/regfile.sv
../src/ieu/shifter.sv

// Instruction Fetch Unit (IFU)
../src/ifu/bpred/icpred.sv
../src/ifu/ifu.sv
../src/ifu/irom.sv

// Load Store Unit (LSU)
../src/lsu/align.sv
../src/lsu/amoalu.sv
../src/lsu/atomic.sv
../src/lsu/dtim.sv
../src/lsu/endianswap.sv
../src/lsu/lrsc.sv
../src/lsu/lsu.sv
../src/lsu/subwordread.sv
../src/lsu/subwordwrite.sv
../src/lsu/swbytemask.sv

// Memory Management Unit (MMU) & PMP
../src/mmu/adrdecs.sv
../src/mmu/adrdec.sv
../src/mmu/mmu.sv
../src/mmu/pmachecker.sv
../src/mmu/pmpadrdec.sv
../src/mmu/pmpchecker.sv

// Privileged Architecture & CSRs
../src/privileged/csrc.sv
../src/privileged/csri.sv
../src/privileged/csrm.sv
../src/privileged/csrsr.sv
../src/privileged/csrs.sv
../src/privileged/csr.sv
../src/privileged/csru.sv
../src/privileged/privdec.sv
../src/privileged/privileged.sv
../src/privileged/privmode.sv
../src/privileged/privpiperegs.sv
../src/privileged/trap.sv

// Uncore Subsystem & Peripherals
../src/uncore/ahbapbbridge.sv
../src/uncore/clint_apb.sv
../src/uncore/gpio_apb.sv
../src/uncore/plic_apb.sv
../src/uncore/ram_ahb.sv
../src/uncore/rom_ahb.sv
../src/uncore/spi_apb.sv
../src/uncore/spi_controller.sv
../src/uncore/spi_fifo.sv
../src/uncore/uart_apb.sv
../src/uncore/uartPC16550D.sv
../src/uncore/uncore.sv

// Wally Core & SoC
../src/wally/wallypipelinedcore.sv
../src/wally/wallypipelinedsoc.sv
