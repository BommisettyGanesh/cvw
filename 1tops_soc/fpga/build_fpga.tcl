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

# 1. Close open project only if one exists
if {[llength [get_projects -quiet]] > 0} {
    puts "Closing currently open Vivado project..."
    close_project
}

# Destroy previous project folder if it exists
if {[file exists $proj_dir]} {
    puts "Destroying previous Vivado project folder: $proj_dir"
    file delete -force $proj_dir
}

# 2. Create fresh project
create_project $proj_name $proj_dir -part $part_num -force

# 3. Add configuration include paths
set inc_dirs [list [file normalize "./config"] [file normalize "./src"] [file normalize "./src/debugger"] [file normalize "./top"]]
set_property include_dirs $inc_dirs [get_filesets sources_1]
if {[llength [get_filesets -quiet sim_1]] > 0} {
    set_property include_dirs $inc_dirs [get_filesets sim_1]
}

# 4. Add configuration header files (.vh)
set vh_files [glob -nocomplain "./config/*.vh"]
if {[llength $vh_files] > 0} {
    add_files -norecurse -fileset sources_1 {*}$vh_files
    set_property file_type {Verilog Header} [get_files -of_objects [get_filesets sources_1] -filter {NAME =~ "*.vh"}]
}

# 5. Add Core Package cvw.sv
if {[file exists "./src/cvw.sv"]} {
    add_files -norecurse -fileset sources_1 "./src/cvw.sv"
}

# 6. Add Top-Level FPGA Wrapper
if {[file exists "./top/wally_soc_fpga_top.sv"]} {
    add_files -norecurse -fileset sources_1 "./top/wally_soc_fpga_top.sv"
}

# 7. Add all SystemVerilog (.sv) and Verilog (.v) sources recursively
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
        # Exclude duplicate cvw.sv, simulation testbenches, BFMs, and unused ASIC foundry hard macro wrappers
        if {[string match "*cvw.sv" $f] ||
            [string match "*tb_*" $f] || [string match "*_stream.v" $f] || [string match "*/tb/*" $f] || [string match "*testbench/*" $f] ||
            [string match "*128x32*" $f] || [string match "*128x64*" $f] || [string match "*64x128*" $f] || [string match "*64x44*" $f] || [string match "*64x22*" $f] ||
            [string match "*generic/adder.sv" $f] || [string match "*generic/decoder.sv" $f]} {
            continue
        }
        lappend all_files $f
    }
}

if {[llength $all_files] > 0} {
    add_files -norecurse -fileset sources_1 [lsort -unique $all_files]
}

# 8. Set SystemVerilog file type on all .sv files
set sv_files [get_files -of_objects [get_filesets sources_1] -filter {NAME =~ "*.sv"}]
if {[llength $sv_files] > 0} {
    set_property file_type {SystemVerilog} $sv_files
}

# 9. Add Basys 3 Physical Constraints File
set xdc_file "./constrs/basys3.xdc"
if {[file exists $xdc_file]} {
    add_files -fileset constrs_1 -norecurse $xdc_file
    puts "Added Basys 3 constraints: $xdc_file"
}

# 10. Set Top Module and Update Compile Order
set_property top wally_soc_fpga_top [get_filesets sources_1]
update_compile_order -fileset sources_1

# 11. Disable incremental synthesis/implementation to prevent missing .dcp checkpoint warnings
if {[llength [get_runs -quiet synth_1]] > 0} {
    catch {set_property auto_incremental_checkpoint 0 [get_runs synth_1]}
    catch {set_property incremental_checkpoint {} [get_runs synth_1]}
}
if {[llength [get_runs -quiet impl_1]] > 0} {
    catch {set_property auto_incremental_checkpoint 0 [get_runs impl_1]}
    catch {set_property incremental_checkpoint {} [get_runs impl_1]}
}

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
