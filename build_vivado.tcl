# -----------------------------------------------------------------------------
# build_vivado.tcl
# Automatically generates a Vivado project for the 1tops_soc configuration
# on the Digilent Basys 3 board (xc7a35tcpg236-1)
#
# Usage:
#   vivado -mode gui -source build_vivado.tcl
#   or in terminal batch mode:
#   vivado -mode batch -source build_vivado.tcl
# -----------------------------------------------------------------------------

set project_name "1tops_soc_project"
set project_dir  "./vivado_workspace"

# 1. Create a new Vivado project targeting Basys 3 (xc7a35tcpg236-1)
#    (Overwrite existing project if it already exists)
create_project $project_name $project_dir -part xc7a35tcpg236-1 -force

# 2. Add configuration headers (.vh)
set inc_dirs [list "1tops_soc/config" "1tops_soc/src" "1tops_soc/src/debugger" "1tops_soc/schematics"]
set_property include_dirs $inc_dirs [get_filesets sources_1]

set vh_files [glob -nocomplain "1tops_soc/config/*.vh"]
if {[llength $vh_files] > 0} {
    add_files -norecurse -fileset sources_1 {*}$vh_files
}

# 3. Add core package file cvw.sv before dependent modules
if {[file exists "1tops_soc/src/cvw.sv"]} {
    add_files -norecurse -fileset sources_1 "1tops_soc/src/cvw.sv"
}

# 4. Add Top Wrapper from schematics (binds parameter P from config.vh)
if {[file exists "1tops_soc/schematics/wallypipelinedsocwrapper.sv"]} {
    add_files -norecurse -fileset sources_1 "1tops_soc/schematics/wallypipelinedsocwrapper.sv"
}

# 5. Add all SystemVerilog (.sv) and Verilog (.v) sources recursively (including debugger)
set src_patterns [list     "1tops_soc/src/*.sv"       "1tops_soc/src/*.v"     "1tops_soc/src/*/*.sv"     "1tops_soc/src/*/*.v"     "1tops_soc/src/*/*/*.sv"   "1tops_soc/src/*/*/*.v"     "1tops_soc/src/*/*/*/*.sv" "1tops_soc/src/*/*/*/*.v" ]

set all_files {}
foreach pat $src_patterns {
    set match_files [glob -nocomplain $pat]
    if {[llength $match_files] > 0} {
        foreach f $match_files {
            # Exclude testbenches and simulation models from synthesis
            if {[string match "*tb_*" $f] || [string match "*_stream.v" $f] || [string match "*testbench/*" $f] || [string match "*/tb/*" $f]} {
                continue
            }
            lappend all_files $f
        }
    }
}

if {[llength $all_files] > 0} {
    add_files -norecurse -fileset sources_1 [lsort -unique $all_files]
} else {
    puts "ERROR: Could not find RTL source files in 1tops_soc/src/"
}

# 6. Set SystemVerilog file type on all .sv files
set sv_files [get_files -of_objects [get_filesets sources_1] *.sv]
if {[llength $sv_files] > 0} {
    set_property FILE_TYPE {SystemVerilog} $sv_files
}

# 7. Add Basys 3 Physical Pin Constraints (.xdc)
set xdc_file "1tops_soc/basys3_soc.xdc"
if {[file exists $xdc_file]} {
    add_files -fileset constrs_1 -norecurse $xdc_file
    puts "Added constraints file: $xdc_file"
} elseif {[file exists "1tops_soc/src/debugger/basys3_soc.xdc"]} {
    add_files -fileset constrs_1 -norecurse "1tops_soc/src/debugger/basys3_soc.xdc"
    puts "Added constraints file: 1tops_soc/src/debugger/basys3_soc.xdc"
}

# 8. Set the top-level module
#    wallypipelinedsocwrapper is used because it elaborates parameter P from config.vh
if {[file exists "1tops_soc/schematics/wallypipelinedsocwrapper.sv"]} {
    set_property top wallypipelinedsocwrapper [get_filesets sources_1]
} else {
    set_property top wallypipelinedsoc [get_filesets sources_1]
}

# 9. Update compilation order automatically
update_compile_order -fileset sources_1

puts "========================================================================"
puts "Vivado Project Successfully Created!"
puts "Target Part: xc7a35tcpg236-1 (Digilent Basys 3)"
puts "Top Module:  [get_property top [get_filesets sources_1]]"
puts "Constraints: $xdc_file (UART on PMOD JA, FT1248 on PMOD JB, SW0=dbg_sel)"
puts "You can now run synthesis, implementation, and bitstream generation."
puts "========================================================================"
