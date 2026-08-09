# ==============================================================================
# Dynamic Project Update & RTL Schematic Re-Elaboration Script
# CORE-V-Wally Minimal 32-Bit Core & SoC (my_minimal_rv32)
# ==============================================================================
# Purpose: Dynamically rescans src/ and config/ for added/removed files and
#          re-elaborates the RTL Schematic to reflect config.vh feature changes.
# ==============================================================================

set script_dir [file dirname [file normalize [info script]]]
set proj_file [file join $script_dir "my_minimal_rv32_schematic" "my_minimal_rv32_schematic.xpr"]
set src_dir [file normalize [file join $script_dir ".." "src"]]
set config_dir [file normalize [file join $script_dir ".." "config"]]

puts "=========================================================================="
puts "Updating Vivado Project Sources & Configuration..."
puts "=========================================================================="

# Create project if it doesn't exist, otherwise open existing project
if {![file exists $proj_file]} {
    puts "Project file not found. Running create_project.tcl..."
    source [file join $script_dir "create_project.tcl"]
} else {
    puts "Opening Vivado project: $proj_file"
    open_project -quiet $proj_file
}

# 1. Update include directories
set_property include_dirs [list $config_dir $src_dir $script_dir] [get_filesets sources_1]

# 2. Rescan and add any new .sv or .vh files added to src/ or config/
set vh_files [glob -nocomplain [file join $config_dir "*.vh"]]
if {[llength $vh_files] > 0} {
    add_files -norecurse -quiet -fileset sources_1 {*}$vh_files
}

set sv_patterns [list \
    [file join $src_dir "*.sv"] \
    [file join $src_dir "*" "*.sv"] \
    [file join $src_dir "*" "*" "*.sv"] \
    [file join $src_dir "*" "*" "*" "*.sv"] \
]

foreach pat $sv_patterns {
    set match_files [glob -nocomplain $pat]
    if {[llength $match_files] > 0} {
        add_files -norecurse -quiet -fileset sources_1 {*}$match_files
    }
}

# Set all .sv file types to SystemVerilog
set sv_files [get_files -of_objects [get_filesets sources_1] *.sv]
if {[llength $sv_files] > 0} {
    set_property FILE_TYPE {SystemVerilog} $sv_files
}

# 3. Update compile order & set top module
set_property top wallypipelinedsocwrapper [get_filesets sources_1]
update_compile_order -fileset sources_1

puts "=========================================================================="
puts "Re-elaborating RTL Schematic Design to reflect config.vh feature changes..."
puts "Top Module: wallypipelinedsocwrapper"
puts "=========================================================================="

# Force re-elaboration of RTL design
close_design -quiet
synth_design -rtl -name rtl_1 -force

puts "=========================================================================="
puts "RTL Schematic Updated Successfully!"
puts "=========================================================================="
