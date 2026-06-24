set root [file normalize [file join [file dirname [info script]] ..]]
cd $root

set srcs {
    src/io/clint.v
    src/tb/tb_clint.v
}

set xvlog_args [list --sv]
foreach src $srcs {
    lappend xvlog_args $src
}

puts [exec xvlog {*}$xvlog_args]
puts [exec xelab tb_clint -debug typical --timescale 1ns/1ps --override_timeunit --override_timeprecision -s tb_clint_sim]
puts [exec xsim tb_clint_sim -runall]
