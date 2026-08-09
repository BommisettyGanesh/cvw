# ==============================================================================
# Vivado RTL Schematic Elaborate Script for CORE-V-Wally (my_minimal_rv32)
# ==============================================================================

set script_dir [file dirname [file normalize [info script]]]
set proj_file [file join $script_dir "my_minimal_rv32_schematic" "my_minimal_rv32_schematic.xpr"]

# Create project if it doesn't exist yet
if {![file exists $proj_file]} {
    puts "Project file not found. Running create_project.tcl..."
    source [file join $script_dir "create_project.tcl"]
} else {
    puts "Opening existing Vivado project: $proj_file"
    open_project $proj_file
}

# Set top module to top wrapper
set_property top wallypipelinedsocwrapper [get_filesets sources_1]
update_compile_order -fileset sources_1

puts "=========================================================================="
puts "Elaborating RTL Design for Schematic Viewer..."
puts "Top Module: wallypipelinedsocwrapper"
puts "=========================================================================="

synth_design -rtl -name rtl_1

puts "=========================================================================="
puts "RTL Schematic Elaboration Complete!"
puts "You can now view and inspect the hierarchy schematic in Vivado GUI."
puts "=========================================================================="
