// -----------------------------------------------------------------------------
// RTLvision PRO Filelist for CORE-V Wally RV32 SoC (1tops_soc)
// Sourced strictly from: 1tops_soc/src2/
// -----------------------------------------------------------------------------

// Include directories
+incdir+../src2/components
+incdir+../src2/debugger
+incdir+../src2/main
+incdir+../src2/main/soc
+incdir+../src2/uncore

// 1. Core Components (src2/components/)
../src2/components/adder.v
../src2/components/ahbinterface.v
../src2/components/alu.v
../src2/components/alu_decoder.v
../src2/components/branching_unit.v
../src2/components/controller.v
../src2/components/csr_file.v
../src2/components/datapath.v
../src2/components/ebu.v
../src2/components/hazard.v
../src2/components/imm_extend.v
../src2/components/main_decoder.v
../src2/components/mux2.v
../src2/components/mux3.v
../src2/components/mux4.v
../src2/components/mux5.v
../src2/components/pl_reg_de.v
../src2/components/pl_reg_em.v
../src2/components/pl_reg_fd.v
../src2/components/pl_reg_mw.v
../src2/components/priv_decoder.v
../src2/components/reg_file.v
../src2/components/reset_ff.v
../src2/components/subword_unit.v
../src2/components/trap_unit.v

// 2. CPU Core Top Level (src2/main/)
../src2/main/riscv_cpu.v

// 3. Post-Mortem Hardware Debugger Subsystem (src2/debugger/)
../src2/debugger/core_debug_ahb.v
../src2/debugger/core_step_controller.sv
../src2/debugger/ahb_mux.sv
../src2/debugger/riscv_debugger_top.sv
../src2/debugger/socdebug_adp_control.v
../src2/debugger/socdebug_ahb.v
../src2/debugger/socdebug_ft1248_control.v
../src2/debugger/socdebug_uart.v

// 4. Uncore Subsystem & Peripherals (src2/uncore/)
../src2/uncore/ahbapbbridge.sv
../src2/uncore/clint_apb.sv
../src2/uncore/gpio_apb.sv
../src2/uncore/plic_apb.sv
../src2/uncore/ram_ahb.sv
../src2/uncore/rom_ahb.sv
../src2/uncore/spi_apb.sv
../src2/uncore/spi_controller.sv
../src2/uncore/spi_fifo.sv
../src2/uncore/uart_apb.sv
../src2/uncore/uartPC16550D.sv
../src2/uncore/uncore.sv

// 5. SoC Interconnect, Accelerator & Top-Level (src2/main/soc/)
../src2/main/soc/ahb_interconnect.v
../src2/main/soc/multiplier_ahb.v
../src2/main/soc/riscv_soc_ahb.v
