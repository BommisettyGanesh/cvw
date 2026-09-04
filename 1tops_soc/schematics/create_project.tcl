# ==============================================================================
# Vivado Project Creation Script for CORE-V-Wally RV32 Core (rv32_core)
# ==============================================================================
# Target Core: rv32_core (32-bit RISC-V SoC)
# Top Module: wallypipelinedsocwrapper (SoC Top Wrapper)
# ==============================================================================

# 1. Define Project Name and Paths
set proj_name "rv32_core_schematic"
set script_dir [file dirname [file normalize [info script]]]
set proj_dir [file join $script_dir $proj_name]
set src_dir [file normalize [file join $script_dir ".." "src"]]
set config_dir [file normalize [file join $script_dir ".." "config"]]

puts "=========================================================================="
puts "Creating Vivado Project: $proj_name"
puts "Script Directory:        $script_dir"
puts "Source Directory:        $src_dir"
puts "Config Directory:        $config_dir"
puts "=========================================================================="

# 2. Close any existing open project and create a new project
close_project -quiet

# Target FPGA Part: Xilinx Artix-7 xc7a100tcsg324-1 (Standard FPGA Part)
create_project $proj_name $proj_dir -part xc7a100tcsg324-1 -force

# 3. Configure Include Directories for SystemVerilog headers (`include "config.vh"`)
set_property include_dirs [list $config_dir $src_dir $script_dir] [get_filesets sources_1]

# 4. Add Configuration Header Files (.vh)
set vh_files [glob -nocomplain [file join $config_dir "*.vh"]]
if {[llength $vh_files] > 0} {
    add_files -norecurse -fileset sources_1 {*}$vh_files
}

# 5. Add Package file cvw.sv first
add_files -norecurse -fileset sources_1 [file join $src_dir "cvw.sv"]

# 6. Add Top Wrapper file
add_files -norecurse -fileset sources_1 [file join $script_dir "wallypipelinedsocwrapper.sv"]

# 7. Add all SystemVerilog Source Files (.sv) under src/ recursively
set sv_patterns [list \
    [file join $src_dir "*.sv"] \
    [file join $src_dir "*" "*.sv"] \
    [file join $src_dir "*" "*" "*.sv"] \
    [file join $src_dir "*" "*" "*" "*.sv"] \
]

foreach pat $sv_patterns {
    set match_files [glob -nocomplain $pat]
    if {[llength $match_files] > 0} {
        add_files -norecurse -fileset sources_1 {*}$match_files
    }
}

# 8. Set File Type to SystemVerilog for all .sv files
set sv_files [get_files -of_objects [get_filesets sources_1] *.sv]
if {[llength $sv_files] > 0} {
    set_property FILE_TYPE {SystemVerilog} $sv_files
}

# 9. Set Top Module to wallypipelinedsocwrapper
set_property top wallypipelinedsocwrapper [get_filesets sources_1]
update_compile_order -fileset sources_1

puts "=========================================================================="
puts "Vivado Project $proj_name Created Successfully!"
puts "Top Module set to: wallypipelinedsocwrapper"
puts "Project File: [file join $proj_dir $proj_name.xpr]"
puts "=========================================================================="
