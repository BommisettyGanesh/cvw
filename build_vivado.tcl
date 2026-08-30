# -----------------------------------------------------------------------------
# build_vivado.tcl
# Automatically generates a Vivado project for the 1tops_soc configuration
#
# Usage:
#   vivado -mode gui -source build_vivado.tcl
# -----------------------------------------------------------------------------

set project_name "1tops_soc_project"
set project_dir  "./vivado_workspace"

# 1. Create a new Vivado project (Overwrite if exists)
create_project $project_name $project_dir -force

# 2. Add SystemVerilog sources recursively from 1tops_soc/src
set src_files [glob -nocomplain -type f 1tops_soc/src/*.sv 1tops_soc/src/*/*.sv 1tops_soc/src/*/*/*.sv]
if {[llength $src_files] > 0} {
    add_files $src_files
} else {
    puts "ERROR: Could not find RTL source files in 1tops_soc/src/"
}

# 3. Add configuration headers
set inc_dirs [list "1tops_soc/config" "1tops_soc/src"]
set_property include_dirs $inc_dirs [current_fileset]

# Optional: if config.vh is required directly in the hierarchy
add_files -norecurse 1tops_soc/config/config.vh

# 4. Set the top-level module (System-on-Chip wrapper)
set_property top wallypipelinedsoc [current_fileset]

# 5. Update compilation order automatically
update_compile_order -fileset sources_1

puts "========================================================================"
puts "Vivado Project Successfully Created!"
puts "Top Module: wallypipelinedsoc"
puts "You can now run synthesis, implementation, or add your accelerator IP."
puts "========================================================================"
