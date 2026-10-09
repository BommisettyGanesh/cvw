# ==============================================================================
# build_fpga.tcl
# Vivado Automated Project Generation Script for CORE-V Wally RISC-V SoC
# on Digilent Basys 3 (xc7a35tcpg236-1) with Dual-Protocol Hardware Debugger
#
# Usage:
#   cd 1tops_soc/fpga
#   vivado -mode gui -source build_fpga.tcl
#   or in batch mode:
#   vivado -mode batch -source build_fpga.tcl
# ==============================================================================

set proj_name "wally_fpga_soc"
set proj_dir  "./vivado_project"
set part_num  "xc7a35tcpg236-1"

puts "=========================================================================="
puts "Building Vivado Project for Digilent Basys 3: $proj_name"
puts "Target Device: $part_num"
puts "=========================================================================="

# 1. Close any existing project and create new project
close_project -quiet
create_project $proj_name $proj_dir -part $part_num -force

# 2. Add configuration include paths
set inc_dirs [list [file normalize "./config"] [file normalize "./src"] [file normalize "./src/debugger"] [file normalize "./top"]]
set_property include_dirs $inc_dirs [get_filesets sources_1]

# 3. Add configuration header files (.vh)
set vh_files [glob -nocomplain "./config/*.vh"]
if {[llength $vh_files] > 0} {
    add_files -norecurse -fileset sources_1 {*}$vh_files
}

# 4. Add Core Package cvw.sv
if {[file exists "./src/cvw.sv"]} {
    add_files -norecurse -fileset sources_1 "./src/cvw.sv"
}

# 5. Add Top-Level FPGA Wrapper
if {[file exists "./top/wally_soc_fpga_top.sv"]} {
    add_files -norecurse -fileset sources_1 "./top/wally_soc_fpga_top.sv"
}

# 6. Add all SystemVerilog (.sv) and Verilog (.v) sources recursively
set patterns [list \
    "./src/*.sv"       "./src/*.v" \
    "./src/*/*.sv"     "./src/*/*.v" \
    "./src/*/*/*.sv"   "./src/*/*/*.v" \
    "./src/*/*/*/*.sv" "./src/*/*/*/*.v" \
]

set all_files {}
foreach pat $patterns {
    set match_files [glob -nocomplain $pat]
    foreach f $match_files {
        # Exclude simulation testbenches & BFMs
        if {[string match "*tb_*" $f] || [string match "*_stream.v" $f] || [string match "*/tb/*" $f] || [string match "*testbench/*" $f]} {
            continue
        }
        lappend all_files $f
    }
}

if {[llength $all_files] > 0} {
    add_files -norecurse -fileset sources_1 [lsort -unique $all_files]
}

# 7. Set SystemVerilog file type on .sv files
set sv_files [get_files -of_objects [get_filesets sources_1] *.sv]
if {[llength $sv_files] > 0} {
    set_property FILE_TYPE {SystemVerilog} $sv_files
}

# 8. Add Basys 3 Physical Constraints File
set xdc_file "./constrs/basys3.xdc"
if {[file exists $xdc_file]} {
    add_files -fileset constrs_1 -norecurse $xdc_file
    puts "[+] Added Basys 3 constraints: $xdc_file"
}

# 9. Set Top Module
set_property top wally_soc_fpga_top [get_filesets sources_1]
update_compile_order -fileset sources_1

puts "=========================================================================="
puts "Vivado Project Created Successfully!"
puts "Project File: [file join $proj_dir $proj_name.xpr]"
puts "Top Module:   wally_soc_fpga_top"
puts "Constraints:  $xdc_file"
puts "  - Debugger UART : PMOD JA (J1/L2)"
puts "  - Debugger FT1248: PMOD JB (A14/A16/B15/B16)"
puts "  - Protocol Switch: SW0 (V17)"
puts "  - Uncore UART   : Onboard USB (B18/A18)"
puts "  - Clock         : 100 MHz (W5)"
puts "Ready for synthesis, implementation, and bitstream generation!"
puts "=========================================================================="
