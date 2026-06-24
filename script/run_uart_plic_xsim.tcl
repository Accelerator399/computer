set root [file normalize [file join [file dirname [info script]] ..]]
cd $root

set srcs {
    src/io/uart/baud_gen.v
    src/io/uart/tx.v
    src/io/uart/rx.v
    src/io/uart/uart.v
    src/io/iomux.v
    src/io/plic.v
    src/tb/tb_uart_plic.v
}

set xvlog_args [list --sv]
foreach src $srcs {
    lappend xvlog_args $src
}

puts [exec xvlog {*}$xvlog_args]
puts [exec xelab tb_uart_plic -debug typical --timescale 1ns/1ps --override_timeunit --override_timeprecision -s tb_uart_plic_sim]
puts [exec xsim tb_uart_plic_sim -runall]
