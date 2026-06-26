# Create Vivado Floating Point IP cores used by src/cpu/utils/fpu_single.v.
#
# Usage:
#   vivado -mode batch -source script/create_fpu_ip.tcl
#   vivado -mode batch -source script/create_fpu_ip.tcl -tclargs --project_dir build/fpu_ip --project_name fpu_ip_check
#
# The RTL wrapper instantiates these module names when compiled with
# `USE_VIVADO_FPU_IP`:
#   fp_add_s  - single-precision add
#   fp_sub_s  - single-precision subtract
#   fp_mul_s  - single-precision multiply
#   fp_div_s  - single-precision divide
#   fp_sqrt_s - single-precision square-root

set script_dir [file normalize [file dirname [info script]]]
set root_dir   [file normalize [file join $script_dir ..]]

set project_name fpu_ip
set project_dir  [file normalize [file join $root_dir build fpu_ip]]
set part_name    xc7a200tfbg676-2

proc print_help {} {
    puts ""
    puts "Usage:"
    puts "  vivado -mode batch -source script/create_fpu_ip.tcl"
    puts "  vivado -mode batch -source script/create_fpu_ip.tcl -tclargs --project_dir build/fpu_ip --project_name fpu_ip_check"
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
        "--part" {
            incr i
            if {$i >= $::argc} {
                puts "ERROR: --part needs a value"
                exit 1
            }
            set part_name [lindex $::argv $i]
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

proc create_ip_checked {module_name} {
    puts "Create Floating Point IP: $module_name"
    if {[catch {
        create_ip -name floating_point -vendor xilinx.com -library ip -version 7.1 -module_name $module_name
    } msg]} {
        puts "WARN: create_ip floating_point v7.1 failed:"
        puts "WARN: $msg"
        puts "WARN: retry without explicit version"
        create_ip -name floating_point -vendor xilinx.com -library ip -module_name $module_name
    }
}

proc configure_fp_ip {module_name operation add_sub_value latency mult_usage} {
    create_ip_checked $module_name
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

puts "============================================================"
puts "Project:      $project_name"
puts "Root:         $root_dir"
puts "Project dir:  $project_dir"
puts "Part:         $part_name"
puts "============================================================"

if {[llength [get_projects -quiet]] > 0} {
    close_project -quiet
}

file mkdir $project_dir
create_project $project_name $project_dir -part $part_name -force
set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]

configure_fp_ip fp_add_s Add_Subtract Add 4 No_Usage
configure_fp_ip fp_sub_s Add_Subtract Subtract 4 No_Usage
configure_fp_ip fp_mul_s Multiply Add 4 Full_Usage
configure_fp_ip fp_div_s Divide Add 28 No_Usage
configure_fp_ip fp_sqrt_s Square_root Add 28 No_Usage

set ip_objs [get_ips]
generate_target all $ip_objs
export_ip_user_files -of_objects $ip_objs -no_script -sync -force -quiet
foreach ip_obj $ip_objs {
    create_ip_run $ip_obj
}

puts ""
puts "============================================================"
puts "FPU IP project created."
puts "Open project: $project_dir/$project_name.xpr"
puts "Compile src/cpu/utils/fpu_single.v with USE_VIVADO_FPU_IP to use:"
puts "  fp_add_s, fp_sub_s, fp_mul_s, fp_div_s, fp_sqrt_s"
puts "============================================================"

close_project
