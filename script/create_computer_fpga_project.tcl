# Recreate the board-level computer FPGA project.
#
# Usage:
#   vivado -mode batch -source script/create_computer_fpga_project.tcl
#   vivado -mode batch -source script/create_computer_fpga_project.tcl -tclargs --build

set script_dir [file normalize [file dirname [info script]]]
set root_dir   [file normalize [file join $script_dir ..]]
set mmu_root   [file normalize [file join $root_dir .. mmu]]

set project_name computer_fpga
set project_dir  [file normalize [file join $root_dir build]]
set part_name    xc7a200tfbg676-2
set jobs         8
set run_build    0
set enable_fpu   1
set clk_freq_hz  100000000
set loader_baud  230400
set linux_uart_boot 0
set enable_ethernet_lite 0
set boot_rom_words 8192
set boot_ram_words 8192
set boot_rom_init [file normalize [file join $root_dir build software linux-uart-loader boot_rom.hex]]
set boot_ram_init [file normalize [file join $root_dir build software linux-uart-loader boot_ram.hex]]

proc print_help {} {
    puts ""
    puts "Usage:"
    puts "  vivado -mode batch -source script/create_computer_fpga_project.tcl"
    puts "  vivado -mode batch -source script/create_computer_fpga_project.tcl -tclargs --build"
    puts ""
    puts "Options:"
    puts "  --build                 Run IP synthesis, top synthesis, implementation, and bitstream."
    puts "  --project_name <name>   Project name. Default: computer_fpga"
    puts "  --project_dir <path>    Project directory. Default: <repo>/build"
    puts "  --jobs <n>              Parallel jobs. Default: 8"
    puts "  --disable_fpu           Build an RV32IMA soft-float/Linux bring-up bitstream."
    puts "  --clk_freq_hz <hz>      CPU clock frequency and UART/CLINT parameter. Default: 100000000"
    puts "  --loader_baud <baud>    UART DDR loader baud rate. Default: 230400"
    puts "  --linux_uart_boot       Boot the CPU from M-mode UART Linux loader firmware."
    puts "  --enable_ethernet_lite  Add AXI Ethernet Lite for M-mode Linux netboot."
    puts "  --boot_rom_init <path>  Boot firmware instruction hex. Default: build/software/linux-uart-loader/boot_rom.hex"
    puts "  --boot_ram_init <path>  Boot firmware data hex. Default: build/software/linux-uart-loader/boot_ram.hex"
    puts "  --boot_rom_words <n>    Boot ROM words. Default: 8192"
    puts "  --boot_ram_words <n>    Boot RAM words. Default: 8192"
    puts "  --help                  Show this help."
    puts ""
}

if {![info exists ::argv]} {
    set ::argv {}
}
if {![info exists ::argc]} {
    set ::argc [llength $::argv]
}

for {set i 0} {$i < $::argc} {incr i} {
    set option [lindex $::argv $i]
    switch -- $option {
        "--build" {
            set run_build 1
        }
        "--project_name" {
            incr i
            if {$i >= $::argc} {
                puts "ERROR: --project_name needs a value"
                exit 1
            }
            set project_name [lindex $::argv $i]
        }
        "--project_dir" {
            incr i
            if {$i >= $::argc} {
                puts "ERROR: --project_dir needs a value"
                exit 1
            }
            set project_dir [file normalize [lindex $::argv $i]]
        }
        "--jobs" {
            incr i
            if {$i >= $::argc} {
                puts "ERROR: --jobs needs a value"
                exit 1
            }
            set jobs [lindex $::argv $i]
        }
        "--disable_fpu" {
            set enable_fpu 0
        }
        "--enable_fpu" {
            set enable_fpu 1
        }
        "--clk_freq_hz" {
            incr i
            if {$i >= $::argc} {
                puts "ERROR: --clk_freq_hz needs a value"
                exit 1
            }
            set clk_freq_hz [lindex $::argv $i]
        }
        "--loader_baud" {
            incr i
            if {$i >= $::argc} {
                puts "ERROR: --loader_baud needs a value"
                exit 1
            }
            set loader_baud [lindex $::argv $i]
        }
        "--linux_uart_boot" {
            set linux_uart_boot 1
        }
        "--enable_ethernet_lite" {
            set enable_ethernet_lite 1
        }
        "--boot_rom_init" {
            incr i
            if {$i >= $::argc} {
                puts "ERROR: --boot_rom_init needs a value"
                exit 1
            }
            set boot_rom_init [file normalize [lindex $::argv $i]]
        }
        "--boot_ram_init" {
            incr i
            if {$i >= $::argc} {
                puts "ERROR: --boot_ram_init needs a value"
                exit 1
            }
            set boot_ram_init [file normalize [lindex $::argv $i]]
        }
        "--boot_rom_words" {
            incr i
            if {$i >= $::argc} {
                puts "ERROR: --boot_rom_words needs a value"
                exit 1
            }
            set boot_rom_words [lindex $::argv $i]
        }
        "--boot_ram_words" {
            incr i
            if {$i >= $::argc} {
                puts "ERROR: --boot_ram_words needs a value"
                exit 1
            }
            set boot_ram_words [lindex $::argv $i]
        }
        "--help" {
            print_help
            exit 0
        }
        default {
            puts "ERROR: unknown option: $option"
            print_help
            exit 1
        }
    }
}

if {![string is double -strict $clk_freq_hz] || $clk_freq_hz <= 0} {
    puts "ERROR: --clk_freq_hz must be a positive number"
    exit 1
}
if {![string is integer -strict $loader_baud] || $loader_baud <= 0} {
    puts "ERROR: --loader_baud must be a positive integer"
    exit 1
}
if {![string is integer -strict $boot_rom_words] || $boot_rom_words <= 0} {
    puts "ERROR: --boot_rom_words must be a positive integer"
    exit 1
}
if {![string is integer -strict $boot_ram_words] || $boot_ram_words <= 0} {
    puts "ERROR: --boot_ram_words must be a positive integer"
    exit 1
}
set cpu_clk_mhz [format "%.3f" [expr {double($clk_freq_hz) / 1000000.0}]]

proc require_file {path desc} {
    if {![file exists $path]} {
        puts "ERROR: missing $desc: $path"
        exit 1
    }
}

proc verilog_string_define {name value} {
    set normalized [string map {\\ /} [file normalize $value]]
    return "${name}=\"$normalized\""
}

proc create_ip_checked {ip_name vendor library version module_name} {
    puts "Create IP: $module_name"
    if {[catch {
        create_ip -name $ip_name -vendor $vendor -library $library -version $version -module_name $module_name
    } msg]} {
        puts "WARN: create_ip with version $version failed:"
        puts "WARN: $msg"
        puts "WARN: retry without explicit version"
        create_ip -name $ip_name -vendor $vendor -library $library -module_name $module_name
    }
}

proc get_ip_xci {ip_name} {
    set ip_obj [get_ips $ip_name]
    set xci_path ""
    catch {set xci_path [get_property IP_FILE $ip_obj]}
    if {$xci_path eq ""} {
        foreach f [get_files -quiet -of_objects $ip_obj] {
            if {[string equal -nocase [file extension $f] ".xci"]} {
                set xci_path $f
                break
            }
        }
    }
    if {$xci_path eq ""} {
        puts "ERROR: cannot locate XCI for IP: $ip_name"
        exit 1
    }
    return [file normalize $xci_path]
}

proc configure_fp_ip {module_name operation add_sub_value latency mult_usage} {
    create_ip_checked floating_point xilinx.com ip 7.1 $module_name
    set_property -dict [list \
        CONFIG.Operation_Type $operation \
        CONFIG.Add_Sub_Value $add_sub_value \
        CONFIG.A_Precision_Type Single \
        CONFIG.Result_Precision_Type Single \
        CONFIG.Flow_Control NonBlocking \
        CONFIG.Has_RESULT_TREADY false \
        CONFIG.Maximum_Latency false \
        CONFIG.C_Latency $latency \
        CONFIG.C_Rate 1 \
        CONFIG.C_Mult_Usage $mult_usage \
        CONFIG.C_Has_UNDERFLOW false \
        CONFIG.C_Has_OVERFLOW false \
        CONFIG.C_Has_INVALID_OP false \
    ] [get_ips $module_name]
}

proc run_and_check {run_name {to_step ""}} {
    if {[llength [get_runs -quiet $run_name]] == 0} {
        puts "ERROR: run not found: $run_name"
        exit 1
    }

    catch {reset_run $run_name}
    if {$to_step eq ""} {
        launch_runs $run_name -jobs $::jobs
    } else {
        launch_runs $run_name -to_step $to_step -jobs $::jobs
    }
    wait_on_run $run_name

    set progress [get_property PROGRESS [get_runs $run_name]]
    set status   [get_property STATUS   [get_runs $run_name]]
    if {$progress ne "100%" || [string match -nocase "*fail*" $status]} {
        puts "ERROR: $run_name failed"
        puts "  status:   $status"
        puts "  progress: $progress"
        exit 1
    }
    puts "DONE: $run_name ($status)"
}

set rtl_files [list \
    [file join $root_dir src cpu utils regfile.v] \
    [file join $root_dir src cpu utils fregfile.v] \
    [file join $root_dir src cpu utils imm_gen.v] \
    [file join $root_dir src cpu utils alu_control.v] \
    [file join $root_dir src cpu utils alu.v] \
    [file join $root_dir src cpu utils mul.v] \
    [file join $root_dir src cpu utils div.v] \
    [file join $root_dir src cpu utils fpu_single.v] \
    [file join $root_dir src cpu csr.v] \
    [file join $root_dir src cpu control.v] \
    [file join $root_dir src cpu datapath.v] \
    [file join $root_dir src cpu cpu.v] \
    [file join $root_dir src mmu mmu_tlb.v] \
    [file join $root_dir src mmu mmu.v] \
    [file join $root_dir src mmu cache.v] \
    [file join $root_dir src mmu mmu_ddr_adapter.v] \
    [file join $root_dir src io uart baud_gen.v] \
    [file join $root_dir src io uart rx.v] \
    [file join $root_dir src io uart tx.v] \
    [file join $root_dir src io uart uart.v] \
    [file join $root_dir src io clint.v] \
    [file join $root_dir src io plic.v] \
    [file join $root_dir src io iomux.v] \
    [file join $root_dir src integration boot_rom.v] \
    [file join $root_dir src integration boot_ram.v] \
    [file join $root_dir src integration computer_core.v] \
    [file join $root_dir src integration computer_ddr_bridge.v] \
    [file join $root_dir src fpga axi_lite_mmio_bridge.v] \
    [file join $root_dir src fpga byte_fifo.v] \
    [file join $root_dir src fpga mig_app_cdc_bridge.v] \
    [file join $root_dir src fpga uart_ddr_loader.v] \
    [file join $root_dir src fpga computer_top_fpga.v] \
]

set constr_file [file join $root_dir constraints computer_top_fpga.xdc]
set eth_constr_file [file join $root_dir constraints computer_ethernet_lite.xdc]
set mig_prj     [file join $mmu_root ip mig_7series_0.prj]

foreach f $rtl_files {
    require_file $f "RTL source"
}
require_file $constr_file "constraint file"
if {$enable_ethernet_lite} {
    require_file $eth_constr_file "Ethernet Lite constraint file"
}
require_file $mig_prj "MIG PRJ file"
if {$linux_uart_boot} {
    require_file $boot_rom_init "boot ROM init file"
    require_file $boot_ram_init "boot RAM init file"
}

puts "============================================================"
puts "Project:      $project_name"
puts "Root:         $root_dir"
puts "Project dir:  $project_dir"
puts "Part:         $part_name"
puts "Build:        $run_build"
puts "Jobs:         $jobs"
puts "CLK_FREQ:     $clk_freq_hz"
puts "CPU CLK MHz:  $cpu_clk_mhz"
puts "Loader baud:  $loader_baud"
puts "FPU:          $enable_fpu"
puts "UART boot:    $linux_uart_boot"
puts "Ethernet:     $enable_ethernet_lite"
if {$linux_uart_boot} {
    puts "Boot ROM:     $boot_rom_init ($boot_rom_words words)"
    puts "Boot RAM:     $boot_ram_init ($boot_ram_words words)"
}
puts "============================================================"

if {[llength [get_projects -quiet]] > 0} {
    close_project -quiet
}

file mkdir $project_dir
create_project $project_name $project_dir -part $part_name -force
set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]
catch {set_param general.maxThreads $jobs}

puts ""
puts "Add RTL sources"
foreach f $rtl_files {
    add_files -norecurse $f
    puts "  [file tail $f]"
}
set verilog_defines [list COMPUTER_CLK_FREQ=$clk_freq_hz COMPUTER_UI_CLK_FREQ=100000000 COMPUTER_ENABLE_FPU=$enable_fpu COMPUTER_LOADER_BAUD_RATE=$loader_baud]
if {$enable_fpu} {
    lappend verilog_defines USE_VIVADO_FPU_IP=1
}
if {$linux_uart_boot} {
    lappend verilog_defines COMPUTER_USE_UART_DDR_LOADER=0
    lappend verilog_defines COMPUTER_BOOT_ROM_ENABLE=1
    lappend verilog_defines COMPUTER_BOOT_ROM_WORDS=$boot_rom_words
    lappend verilog_defines [verilog_string_define COMPUTER_BOOT_ROM_INIT_FILE $boot_rom_init]
    lappend verilog_defines COMPUTER_BOOT_RAM_ENABLE=1
    lappend verilog_defines COMPUTER_BOOT_RAM_WORDS=$boot_ram_words
    lappend verilog_defines [verilog_string_define COMPUTER_BOOT_RAM_INIT_FILE $boot_ram_init]
}
if {$enable_ethernet_lite} {
    lappend verilog_defines COMPUTER_ENABLE_ETHERNET_LITE=1
}
set_property verilog_define $verilog_defines [get_filesets sources_1]

puts ""
puts "Add constraints"
add_files -fileset constrs_1 -norecurse $constr_file
puts "  $constr_file"
if {$enable_ethernet_lite} {
    add_files -fileset constrs_1 -norecurse $eth_constr_file
    puts "  $eth_constr_file"
}

puts ""
puts "Create clk_wiz_0"
create_ip_checked clk_wiz xilinx.com ip 6.0 clk_wiz_0
set_property -dict [list \
    CONFIG.PRIM_SOURCE {Single_ended_clock_capable_pin} \
    CONFIG.PRIM_IN_FREQ {100.000} \
    CONFIG.CLKOUT1_USED {true} \
    CONFIG.CLKOUT1_REQUESTED_OUT_FREQ $cpu_clk_mhz \
    CONFIG.CLKOUT2_USED {true} \
    CONFIG.CLKOUT2_REQUESTED_OUT_FREQ {200.000} \
    CONFIG.NUM_OUT_CLKS {2} \
    CONFIG.USE_RESET {true} \
    CONFIG.USE_LOCKED {true} \
] [get_ips clk_wiz_0]

puts ""
puts "Create mig_7series_0 from PRJ"
create_ip_checked mig_7series xilinx.com ip 4.2 mig_7series_0
set mig_xci    [get_ip_xci mig_7series_0]
set mig_ip_dir [file dirname $mig_xci]
file copy -force $mig_prj [file join $mig_ip_dir mig_a.prj]
set_property -dict [list \
    CONFIG.XML_INPUT_FILE {mig_a.prj} \
    CONFIG.RESET_BOARD_INTERFACE {Custom} \
    CONFIG.MIG_DONT_TOUCH_PARAM {Custom} \
    CONFIG.BOARD_MIG_PARAM {Custom} \
] [get_ips mig_7series_0]
puts "  PRJ: $mig_prj"
puts "  XCI: $mig_xci"

puts ""
puts "Create Floating Point IP"
if {$enable_fpu} {
    configure_fp_ip fp_add_s Add_Subtract Add 4 No_Usage
    configure_fp_ip fp_sub_s Add_Subtract Subtract 4 No_Usage
    configure_fp_ip fp_mul_s Multiply Add 4 Full_Usage
    configure_fp_ip fp_div_s Divide Add 28 No_Usage
    configure_fp_ip fp_sqrt_s Square_root Add 28 No_Usage
} else {
    puts "  disabled for RV32IMA/Linux soft-float bring-up"
}

puts ""
puts "Create AXI Ethernet Lite IP"
if {$enable_ethernet_lite} {
    create_ip_checked axi_ethernetlite xilinx.com ip 3.0 axi_ethernetlite_0
    set_property -dict [list \
        CONFIG.C_INCLUDE_MDIO {1} \
        CONFIG.C_TX_PING_PONG {1} \
        CONFIG.C_RX_PING_PONG {1} \
    ] [get_ips axi_ethernetlite_0]
} else {
    puts "  disabled"
}

puts ""
puts "Generate IP output products"
set ip_objs [get_ips]
foreach ip_obj $ip_objs {
    generate_target {instantiation_template synthesis implementation} $ip_obj
}
export_ip_user_files -of_objects $ip_objs -no_script -sync -force -quiet
foreach ip_obj $ip_objs {
    create_ip_run $ip_obj
}

set_property top computer_top_fpga [current_fileset]
update_compile_order -fileset sources_1

set_property strategy Flow_PerfOptimized_high [get_runs synth_1]
set_property strategy Performance_ExplorePostRoutePhysOpt [get_runs impl_1]
catch {set_property STEPS.WRITE_BITSTREAM.ARGS.BIN_FILE true [get_runs impl_1]}

if {!$run_build} {
    puts ""
    puts "============================================================"
    puts "Project created."
    puts "Open project: $project_dir/$project_name.xpr"
    puts "To build bitstream, rerun with: -tclargs --build"
    puts "============================================================"
    close_project
    exit 0
}

puts ""
puts "Synthesize IP runs"
set ip_runs [list \
    clk_wiz_0_synth_1 \
    mig_7series_0_synth_1 \
]
if {$enable_fpu} {
    foreach fp_run [list \
        fp_add_s_synth_1 \
        fp_sub_s_synth_1 \
        fp_mul_s_synth_1 \
        fp_div_s_synth_1 \
        fp_sqrt_s_synth_1 \
    ] {
        lappend ip_runs $fp_run
    }
}
if {$enable_ethernet_lite} {
    lappend ip_runs axi_ethernetlite_0_synth_1
}
foreach ip_run $ip_runs {
    run_and_check $ip_run
}

puts ""
puts "Run top synthesis"
run_and_check synth_1

puts ""
puts "Run implementation and write bitstream"
run_and_check impl_1 write_bitstream

set report_dir [file join $project_dir reports]
file mkdir $report_dir
catch {
    open_run synth_1 -name synth_1
    report_utilization -file [file join $report_dir computer_utilization_synth.rpt]
    report_timing_summary -file [file join $report_dir computer_timing_synth.rpt]
}
catch {
    open_run impl_1 -name impl_1
    report_utilization -file [file join $report_dir computer_utilization_impl.rpt]
    report_timing_summary -file [file join $report_dir computer_timing_impl.rpt]
    report_clock_utilization -file [file join $report_dir computer_clock_utilization.rpt]
    report_power -file [file join $report_dir computer_power.rpt]
}

set bit_file [file normalize [file join $project_dir ${project_name}.runs impl_1 computer_top_fpga.bit]]
puts ""
puts "============================================================"
if {[file exists $bit_file]} {
    puts "Build completed."
    puts "Bitstream: $bit_file"
} else {
    puts "ERROR: bitstream not found: $bit_file"
    exit 1
}
puts "Reports:   $report_dir"
puts "============================================================"

close_project
