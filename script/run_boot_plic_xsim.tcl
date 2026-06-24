set root [file normalize [file join [file dirname [info script]] ..]]
cd $root

set srcs {
    src/cpu/utils/regfile.v
    src/cpu/utils/mul.v
    src/cpu/utils/div.v
    src/cpu/utils/imm_gen.v
    src/cpu/utils/alu_control.v
    src/cpu/utils/alu.v
    src/cpu/control.v
    src/cpu/csr.v
    src/cpu/datapath.v
    src/cpu/cpu.v
    src/io/plic.v
    src/integration/boot_rom.v
    src/tb/tb_boot_plic.v
}

set xvlog_args [list --sv]
foreach src $srcs {
    lappend xvlog_args $src
}

puts [exec xvlog {*}$xvlog_args]
puts [exec xelab tb_boot_plic -debug typical --timescale 1ns/1ps --override_timeunit --override_timeprecision -s tb_boot_plic_sim]
puts [exec xsim tb_boot_plic_sim -runall]
