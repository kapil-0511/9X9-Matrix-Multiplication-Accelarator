# setup_project.tcl — create Vivado project for matmul_9x9
# Usage: vivado -mode batch -source setup_project.tcl

set script_dir [file normalize [file dirname [info script]]]
set proj_name  "matmul_9x9"
set proj_dir   [file join $script_dir "vivado_proj"]
set rtl_dir    [file join $script_dir "rtl"]
set tb_dir     [file join $script_dir "tb"]

# Change part to match your board
set part "xc7a35tcpg236-1"

create_project $proj_name $proj_dir -part $part -force
set_property target_language    Verilog        [current_project]
set_property simulator_language Mixed          [current_project]
set_property default_lib        xil_defaultlib [current_project]

# RTL sources — pe.v before mac_array_3x3.v (instantiation order)
set rtl_files [list \
    [file join $rtl_dir "sram.v"]            \
    [file join $rtl_dir "pe.v"]              \
    [file join $rtl_dir "mac_array_3x3.v"]   \
    [file join $rtl_dir "tile_controller.v"] \
    [file join $rtl_dir "apb_slave.v"]       \
    [file join $rtl_dir "matmul_top.v"]      \
]
add_files -norecurse $rtl_files
set_property file_type {Verilog} [get_files $rtl_files]
set_property top matmul_top [current_fileset]
update_compile_order -fileset sources_1

# Testbench (sim_1 only)
set tb_file [file join $tb_dir "tb_matmul.sv"]
add_files -fileset sim_1 -norecurse $tb_file
set_property file_type {SystemVerilog} [get_files $tb_file]
set_property top     tb_matmul     [get_filesets sim_1]
set_property top_lib xil_defaultlib [get_filesets sim_1]

set_property -name {xsim.simulate.runtime}          -value {0}              -objects [get_filesets sim_1]
set_property -name {xsim.simulate.log_all_signals}  -value {true}           -objects [get_filesets sim_1]
set_property -name {xsim.elaborate.xelab.more_options} -value {--debug typical} -objects [get_filesets sim_1]
update_compile_order -fileset sim_1

puts "Project created: [file join $proj_dir ${proj_name}.xpr]"
puts "Open GUI : vivado [file join $proj_dir ${proj_name}.xpr]"
puts "Run sim  : launch_simulation; run all"
