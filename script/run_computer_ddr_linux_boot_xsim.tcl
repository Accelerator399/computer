set root [file normalize [file join [file dirname [info script]] ..]]
set ip_build [file join $root build mmu_ip_check]
set mig_root [file join $ip_build mmu_ip_check.gen sources_1 ip mig_7series_0 mig_7series_0]
set sim_dir [file join $mig_root example_design sim]
set user_rtl_dir [file join $mig_root user_design rtl]
set clk_wiz_dir [file join $ip_build mmu_ip_check.gen sources_1 ip clk_wiz_0]
set preload_file [file join $root software image linux_preload.memh]
set fwok_smoke_preload_file [file join $root software image fwok_smoke_preload.memh]
set linux_smoke_preload_file [file join $root software image linux_smoke_preload.memh]
set uart_log_file [file join $root software image uart.log]
set timeout_cycles 50000
set expect_banner 0
set verify_preload 0
set verify_preload_only 0

for {set i 0} {$i < $argc} {incr i} {
    set arg [lindex $argv $i]
    switch -- $arg {
        --preload {
            incr i
            set preload_file [file normalize [lindex $argv $i]]
        }
        --uart_log {
            incr i
            set uart_log_file [file normalize [lindex $argv $i]]
        }
        --timeout_cycles {
            incr i
            set timeout_cycles [lindex $argv $i]
        }
        --expect_banner {
            incr i
            set expect_banner [lindex $argv $i]
        }
        --verify_preload {
            set verify_preload 1
        }
        --verify_preload_only {
            set verify_preload 1
            set verify_preload_only 1
            set expect_banner 0
        }
        --linux {
            set expect_banner 1
            set timeout_cycles 1200000
        }
        --firmware {
            set expect_banner 2
            set timeout_cycles 450000
        }
        --fwok_smoke {
            set preload_file $fwok_smoke_preload_file
            set expect_banner 2
            set timeout_cycles 40000
        }
        --linux_smoke {
            set preload_file $linux_smoke_preload_file
            set expect_banner 1
            set timeout_cycles 120000
        }
        default {
            puts "ERROR: unknown argument: $arg"
            puts "Usage: vivado -mode batch -source script/run_computer_ddr_linux_boot_xsim.tcl -tclargs ?--preload FILE? ?--uart_log FILE? ?--timeout_cycles N? ?--expect_banner 0|1|2? ?--verify_preload? ?--verify_preload_only? ?--linux? ?--firmware? ?--fwok_smoke? ?--linux_smoke?"
            exit 1
        }
    }
}

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
require_file $preload_file "Linux DDR preload file"

set prj_file [file join $sim_dir xsim_computer_ddr_linux_boot.prj]
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
add_sv $fh [file join $root src tb tb_computer_ddr_linux_boot.v]

close $fh

set batch_tcl [file join $sim_dir xsim_computer_ddr_linux_boot_batch.tcl]
set fh [open $batch_tcl w]
puts $fh "run all"
puts $fh "exit"
close $fh

cd $sim_dir

puts "Elaborating computer DDR3 Linux-boot simulation..."
puts [exec xelab work.tb_computer_ddr_linux_boot work.glbl -prj $prj_file -L unisims_ver -L secureip -s xsim_computer_ddr_linux_boot -debug typical --timescale 1ps/1ps --override_timeunit --override_timeprecision]

puts "Running computer DDR3 Linux-boot simulation..."
puts "  preload       = $preload_file"
puts "  uart_log      = $uart_log_file"
puts "  timeout       = $timeout_cycles ui_clk cycles"
puts "  expect_banner = $expect_banner"
puts "  verify_preload = $verify_preload"
puts "  verify_preload_only = $verify_preload_only"
puts [exec xsim xsim_computer_ddr_linux_boot \
    -testplusarg PRELOAD=$preload_file \
    -testplusarg UART_LOG=$uart_log_file \
    -testplusarg TIMEOUT_CYCLES=$timeout_cycles \
    -testplusarg EXPECT_BANNER=$expect_banner \
    -testplusarg VERIFY_PRELOAD=$verify_preload \
    -testplusarg VERIFY_PRELOAD_ONLY=$verify_preload_only \
    -tclbatch $batch_tcl]
