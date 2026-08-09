#!/bin/bash
# ==============================================================================
# Shell Launcher for Vivado Project & Dynamic Schematic Viewer
# CORE-V-Wally Minimal 32-Bit Core & SoC (my_minimal_rv32)
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJ_XPR="$SCRIPT_DIR/my_minimal_rv32_schematic/my_minimal_rv32_schematic.xpr"

# Find Vivado executable
VIVADO_BIN="$(which vivado 2>/dev/null)"
if [ -z "$VIVADO_BIN" ]; then
    if [ -f "/home/ganesh/Xilinx/2025.2/Vivado/bin/vivado" ]; then
        VIVADO_BIN="/home/ganesh/Xilinx/2025.2/Vivado/bin/vivado"
    fi
fi

if [ -z "$VIVADO_BIN" ]; then
    echo "Error: Vivado executable not found in PATH or /home/ganesh/Xilinx/2025.2/Vivado/bin/vivado."
    exit 1
fi

echo "=========================================================================="
echo "Starting Xilinx Vivado for CORE-V-Wally (my_minimal_rv32)"
echo "Vivado Executable: $VIVADO_BIN"
echo "=========================================================================="

# Automatically sync files and open RTL Schematic in GUI mode
echo "Opening Vivado GUI with dynamic RTL Schematic elaboration..."
"$VIVADO_BIN" -mode gui -source "$SCRIPT_DIR/update_and_elaborate.tcl" &
