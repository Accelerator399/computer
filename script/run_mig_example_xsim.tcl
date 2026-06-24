set root [file normalize [file join [file dirname [info script]] ..]]
set mig_root [file join $root build mmu_ip_check mmu_ip_check.gen sources_1 ip mig_7series_0 mig_7series_0]
set sim_dir [file join $mig_root example_design sim]
set ex_rtl_dir [file join $mig_root example_design rtl]
set user_rtl_dir [file join $mig_root user_design rtl]

if {![file exists $sim_dir]} {
    puts "ERROR: MIG example simulation files were not generated."
    puts "Run first:"
    puts "  vivado -mode batch -source ../mmu/script/create_project.tcl -tclargs --project_dir D:/code/vivado/computer/build/mmu_ip_check --project_name mmu_ip_check"
    exit 1
}

proc require_file {path desc} {
    if {![file exists $path]} {
        puts "ERROR: missing $desc: $path"
        exit 1
    }
}

proc add_verilog {fh path} {
    require_file $path "Verilog source"
    puts $fh "verilog work \"$path\""
}

proc add_sv {fh path args} {
    require_file $path "SystemVerilog source"
    puts $fh "sv work \"$path\" [join $args " "]"
}

proc add_glob {fh pattern} {
    set files [lsort [glob -nocomplain $pattern]]
    if {[llength $files] == 0} {
        puts "ERROR: no files matched: $pattern"
        exit 1
    }
    foreach f $files {
        add_verilog $fh $f
    }
}

set vivado_root ""
if {[info exists ::env(XILINX_VIVADO)]} {
    set vivado_root $::env(XILINX_VIVADO)
} elseif {[file exists "D:/Xilinx/2025.1/Vivado/data/verilog/src/glbl.v"]} {
    set vivado_root "D:/Xilinx/2025.1/Vivado"
}

if {$vivado_root eq ""} {
    puts "ERROR: cannot locate XILINX_VIVADO for glbl.v"
    exit 1
}

set glbl_v [file join $vivado_root data verilog src glbl.v]
require_file $glbl_v "Vivado glbl.v"

set prj_file [file join $sim_dir xsim_files_local.prj]
set fh [open $prj_file w]

add_glob $fh [file join $ex_rtl_dir traffic_gen *.v]
add_verilog $fh [file join $ex_rtl_dir example_top.v]
add_glob $fh [file join $user_rtl_dir clocking *.v]
add_glob $fh [file join $user_rtl_dir controller *.v]
add_glob $fh [file join $user_rtl_dir ecc *.v]
add_glob $fh [file join $user_rtl_dir ip_top *.v]
add_verilog $fh [file join $user_rtl_dir mig_7series_0.v]
add_verilog $fh [file join $user_rtl_dir mig_7series_0_mig_sim.v]
add_glob $fh [file join $user_rtl_dir phy *.v]
add_glob $fh [file join $user_rtl_dir ui *.v]
add_verilog $fh $glbl_v
add_sv $fh [file join $sim_dir ddr3_model.sv] -d x1Gb -d sg125 -d x16
add_verilog $fh [file join $sim_dir wiredly.v]
add_verilog $fh [file join $sim_dir sim_tb_top.v]

close $fh

set batch_tcl [file join $sim_dir xsim_batch_local.tcl]
set fh [open $batch_tcl w]
puts $fh "run 1000 us"
puts $fh "exit"
close $fh

cd $sim_dir

puts "Elaborating MIG example simulation..."
puts [exec xelab work.sim_tb_top work.glbl -prj $prj_file -L unisims_ver -L secureip -s xsim_mig_example -debug typical]

puts "Running MIG example simulation..."
puts [exec xsim xsim_mig_example -tclbatch $batch_tcl -wdb xsim_mig_example.wdb]
