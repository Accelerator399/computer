# Program the connected FPGA with the computer board bitstream.
#
# Usage:
#   vivado -mode batch -source script/program_computer_fpga.tcl
#   vivado -mode batch -source script/program_computer_fpga.tcl -tclargs --bit path/to.bit

set script_dir [file normalize [file dirname [info script]]]
set root_dir   [file normalize [file join $script_dir ..]]
set bit_file   [file normalize [file join $root_dir build computer_fpga.runs impl_1 computer_top_fpga.bit]]

if {![info exists ::argv]} {
    set ::argv {}
}
if {![info exists ::argc]} {
    set ::argc [llength $::argv]
}

for {set i 0} {$i < $::argc} {incr i} {
    set option [lindex $::argv $i]
    switch -- $option {
        "--bit" {
            incr i
            if {$i >= $::argc} {
                puts "ERROR: --bit needs a value"
                exit 1
            }
            set bit_file [file normalize [lindex $::argv $i]]
        }
        "--help" {
            puts "Usage: vivado -mode batch -source script/program_computer_fpga.tcl ?-tclargs --bit FILE?"
            exit 0
        }
        default {
            puts "ERROR: unknown option: $option"
            exit 1
        }
    }
}

if {![file exists $bit_file]} {
    puts "ERROR: bitstream not found: $bit_file"
    exit 1
}

open_hw_manager
connect_hw_server
open_hw_target

set devs [get_hw_devices xc7a200t_0]
if {[llength $devs] == 0} {
    set devs [get_hw_devices]
}
if {[llength $devs] == 0} {
    puts "ERROR: no hardware devices found"
    close_hw_manager
    exit 1
}

set dev [lindex $devs 0]
current_hw_device $dev
refresh_hw_device $dev
set_property PROGRAM.FILE $bit_file $dev
puts "Programming $dev with $bit_file"
program_hw_devices $dev
refresh_hw_device $dev
puts "PROGRAM DONE"

close_hw_manager
