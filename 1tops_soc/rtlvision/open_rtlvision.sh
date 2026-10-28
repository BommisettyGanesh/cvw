#!/bin/bash
# ==============================================================================
# Script to launch RTLvision PRO for CORE-V Wally RV32 SoC (1tops_soc)
# ==============================================================================

# Activate Environment Module for RTLvision PRO (version 2025.1 has verified license)
module load altairdsim/RTLvisionPRO/2025.1

# Navigate to script directory so relative paths in files.f resolve properly
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "=========================================================================="
echo "Launching RTLvision PRO GUI for 1TOPS SoC..."
echo "Top Module: riscv_soc_ahb (from src2/main/soc/riscv_soc_ahb.v)"
echo "Working Directory: $SCRIPT_DIR"
echo "=========================================================================="

rtlvisionpro -sv -top riscv_soc_ahb -f files.f -logfile rtlvision.log "$@" &
