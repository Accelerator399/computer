set root [file normalize [file join [file dirname [info script]] ..]]
set ip_build [file join $root build mmu_ip_check]
set mig_root [file join $ip_build mmu_ip_check.gen sources_1 ip mig_7series_0 mig_7series_0]
set sim_dir [file join $mig_root example_design sim]
set user_rtl_dir [file join $mig_root user_design rtl]
set clk_wiz_dir [file join $ip_build mmu_ip_check.gen sources_1 ip clk_wiz_0]

if {![file exists $sim_dir]} {
    puts "ERROR: MIG/clock IP output products were not generated."
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

proc add_sv {fh path} {
    require_file $path "SystemVerilog source"
    puts $fh "sv work \"$path\""
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

set prj_file [file join $sim_dir xsim_computer_ddr.prj]
set fh [open $prj_file w]

add_verilog $fh [file join $clk_wiz_dir clk_wiz_0_clk_wiz.v]
add_verilog $fh [file join $clk_wiz_dir clk_wiz_0.v]

add_glob $fh [file join $user_rtl_dir clocking *.v]
add_glob $fh [file join $user_rtl_dir controller *.v]
add_glob $fh [file join $user_rtl_dir ecc *.v]
add_glob $fh [file join $user_rtl_dir ip_top *.v]
add_verilog $fh [file join $user_rtl_dir mig_7series_0.v]
add_verilog $fh [file join $user_rtl_dir mig_7series_0_mig_sim.v]
add_glob $fh [file join $user_rtl_dir phy *.v]
add_glob $fh [file join $user_rtl_dir ui *.v]

add_verilog $fh [file join $root src cpu utils regfile.v]
add_verilog $fh [file join $root src cpu utils fregfile.v]
add_sv $fh [file join $root src cpu utils fpu_single.v]
add_verilog $fh [file join $root src cpu utils mul.v]
add_verilog $fh [file join $root src cpu utils div.v]
add_verilog $fh [file join $root src cpu utils imm_gen.v]
add_verilog $fh [file join $root src cpu utils alu_control.v]
add_verilog $fh [file join $root src cpu utils alu.v]
add_verilog $fh [file join $root src cpu control.v]
add_verilog $fh [file join $root src cpu csr.v]
add_verilog $fh [file join $root src cpu datapath.v]
add_verilog $fh [file join $root src cpu cpu.v]
add_verilog $fh [file join $root src io uart baud_gen.v]
add_verilog $fh [file join $root src io uart tx.v]
add_verilog $fh [file join $root src io uart rx.v]
add_verilog $fh [file join $root src io uart uart.v]
add_verilog $fh [file join $root src io clint.v]
add_verilog $fh [file join $root src io plic.v]
add_verilog $fh [file join $root src io iomux.v]
add_verilog $fh [file join $root src mmu mmu_tlb.v]
add_verilog $fh [file join $root src mmu mmu.v]
add_verilog $fh [file join $root src mmu cache.v]
add_verilog $fh [file join $root src mmu mmu_ddr_adapter.v]
add_verilog $fh [file join $root src integration boot_rom.v]
add_verilog $fh [file join $root src integration computer_core.v]
add_verilog $fh [file join $root src integration computer_ddr_bridge.v]

add_verilog $fh $glbl_v
add_sv $fh [file join $sim_dir ddr3_model.sv]
add_verilog $fh [file join $sim_dir wiredly.v]
add_sv $fh [file join $root src tb tb_computer_ddr_smoke.v]

close $fh

set batch_tcl [file join $sim_dir xsim_computer_ddr_batch.tcl]
set fh [open $batch_tcl w]
puts $fh "run all"
puts $fh "exit"
close $fh

cd $sim_dir

puts "Elaborating computer DDR3 simulation..."
puts [exec xelab work.tb_computer_ddr_smoke work.glbl -prj $prj_file -L unisims_ver -L secureip -s xsim_computer_ddr -debug typical --timescale 1ps/1ps --override_timeunit --override_timeprecision]

puts "Running computer DDR3 simulation..."
puts [exec xsim xsim_computer_ddr -tclbatch $batch_tcl -wdb xsim_computer_ddr.wdb]
