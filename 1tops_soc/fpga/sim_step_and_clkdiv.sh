#!/usr/bin/env bash
# ==============================================================================
# sim_step_and_clkdiv.sh
# Automated Vivado XSIM Test Runner for CORE-V Wally SoCDebug
# Verifies:
#   1. Core Instruction-Step and Clock-Cycle Step FSM Controller
#   2. Reconfigurable UART & FT1248 Clock Dividers
#   3. Dual-Protocol (UART & FT1248) Stream Multiplexing & Isolation
# ==============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

echo "=============================================================================="
echo "Starting SoCDebug Step & Clock Division Simulation (Vivado XSIM)"
echo "=============================================================================="

# Ensure Vivado environment is available
if ! command -v xvlog &> /dev/null; then
    if [ -f "/etc/profile" ]; then
        source /etc/profile
    fi
    module load xilinx/vivado/2024.2 2>/dev/null || true
fi

if ! command -v xvlog &> /dev/null; then
    if [ -f "/home/ganesh/Xilinx/2025.2/Vivado/settings64.sh" ]; then
        source "/home/ganesh/Xilinx/2025.2/Vivado/settings64.sh"
    elif [ -f "/tools/Xilinx/Vivado/2025.2/settings64.sh" ]; then
        source "/tools/Xilinx/Vivado/2025.2/settings64.sh"
    else
        echo "[-] Error: Vivado (xvlog/xelab/xsim) not found in PATH."
        exit 1
    fi
fi

# 1. Compile SystemVerilog Sources
echo "[1/3] Compiling SystemVerilog and Verilog Sources with xvlog..."
xvlog -sv \
  -i ../src2/debugger \
  ../src2/debugger/socdebug_adp_control.v \
  ../src2/debugger/socdebug_ahb.v \
  ../src2/debugger/socdebug_uart.v \
  ../src2/debugger/socdebug_ft1248_control.v \
  ../src2/debugger/core_step_controller.sv \
  ../src2/debugger/core_debug_ahb.v \
  ../src2/debugger/riscv_debugger_top.sv \
  ../src2/debugger/ahb_mux.sv \
  ../src2/main/soc/multiplier_ahb.v \
  ../src2/debugger/tb/f232h_ft1248_stream.v \
  ../src2/debugger/tb/tb_debugger.sv

# 2. Elaborate Design
echo "[2/3] Elaborating simulation snapshot with xelab..."
xelab --timescale 1ns/1ps -debug typical tb_debugger -s tb_debugger_sim

# 3. Execute Simulation
echo "[3/3] Running simulation in xsim batch mode..."
xsim tb_debugger_sim -runall

echo "=============================================================================="
echo "[SUCCESS] Simulation completed successfully!"
echo "=============================================================================="
