+incdir+config
+incdir+src
+incdir+src/debugger
+incdir+src/core
+incdir+src/core/components
src/cvw.sv
src/generic/decoder.sv
src/generic/priorityonehot.sv
src/generic/flop/synchronizer.sv
src/generic/flop/flopen.sv
src/generic/flop/flopr.sv
src/generic/flop/flop.sv
src/generic/flop/flopenl.sv
src/generic/flop/flopenrc.sv
src/generic/flop/flopenr.sv
src/generic/mem/rom1p1r_128x32.sv
src/generic/mem/ram1p1rwbe_64x44.sv
src/generic/mem/ram1p1rwbe_64x22.sv
src/generic/mem/ram1p1rwbe_64x128.sv
src/generic/mem/rom1p1r_128x64.sv
src/generic/mem/ram1p1rwbe.sv
src/generic/mem/rom1p1r.sv
src/generic/mux.sv
src/generic/counter.sv
src/generic/adder.sv

src/mmu/adrdecs.sv
src/mmu/adrdec.sv

src/uncore/gpio_apb.sv
src/uncore/spi_fifo.sv
src/uncore/ahbapbbridge.sv
src/uncore/spi_apb.sv
src/uncore/rom_ahb.sv
src/uncore/uart_apb.sv
src/uncore/ram_ahb.sv
src/uncore/uartPC16550D.sv
src/uncore/clint_apb.sv
src/uncore/uncore.sv
src/uncore/spi_controller.sv
src/uncore/plic_apb.sv

src/core/components/alu_decoder.v

src/core/components/alu.v
src/core/components/branching_unit.v
src/core/components/main_decoder.v
src/core/components/priv_decoder.v
src/core/components/controller.v
src/core/components/csr_file.v
src/core/components/hazard.v
src/core/components/imm_extend.v
src/core/components/pl_reg_de.v
src/core/components/pl_reg_em.v
src/core/components/pl_reg_fd.v
src/core/components/pl_reg_mw.v
src/core/components/reg_file.v
src/core/components/reset_ff.v
src/core/components/subword_unit.v
src/core/components/trap_unit.v
src/core/components/ahbinterface.v
src/core/components/ebu.v
src/core/components/datapath.v
src/core/riscv_cpu.v

src/wally/wallypipelinedcore.sv
src/wally/riscv_soc_ahb.v
src/wally/wallypipelinedsoc.sv

src/accelerator/multiplier_ahb.sv

src/debugger/socdebug_adp_control.v
src/debugger/socdebug_ahb.v
src/debugger/socdebug_uart.v
src/debugger/socdebug_ft1248_control.v
src/debugger/ahb_mux.sv
src/debugger/riscv_debugger_top.sv
src/debugger/core_step_controller.sv
