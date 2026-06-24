set root [file normalize [file join [file dirname [info script]] ..]]
cd $root

set srcs {
    src/mmu/mmu_tlb.v
    src/mmu/mmu.v
    src/tb/tb_mmu_walker.v
}

set xvlog_args [list --sv]
foreach src $srcs {
    lappend xvlog_args $src
}

puts [exec xvlog {*}$xvlog_args]
puts [exec xelab tb_mmu_walker -debug typical --timescale 1ns/1ps --override_timeunit --override_timeprecision -s tb_mmu_walker_sim]
puts [exec xsim tb_mmu_walker_sim -runall]
