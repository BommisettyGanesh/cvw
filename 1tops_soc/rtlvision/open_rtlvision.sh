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
echo "Top Module: wallypipelinedsocwrapper"
echo "Working Directory: $SCRIPT_DIR"
echo "=========================================================================="

rtlvisionpro -sv -top wallypipelinedsocwrapper -f files.f -logfile rtlvision.log "$@" &
