set root [file normalize [file join [file dirname [info script]] ..]]
cd $root

set srcs {
    src/cpu/utils/regfile.v
    src/cpu/utils/fregfile.v
    src/cpu/utils/fpu_single.v
    src/cpu/utils/mul.v
    src/cpu/utils/div.v
    src/cpu/utils/imm_gen.v
    src/cpu/utils/alu_control.v
    src/cpu/utils/alu.v
    src/cpu/control.v
    src/cpu/csr.v
    src/cpu/datapath.v
    src/cpu/cpu.v
    src/io/uart/baud_gen.v
    src/io/uart/tx.v
    src/io/uart/rx.v
    src/io/uart/uart.v
    src/io/clint.v
    src/io/plic.v
    src/io/iomux.v
    src/mmu/mmu_tlb.v
    src/mmu/mmu.v
    src/mmu/cache.v
    src/integration/boot_rom.v
    src/integration/simple_mem128.v
    src/integration/computer_core.v
    src/integration/top_sim.v
    src/tb/tb_core_linux_smoke.v
}

set xvlog_args [list --sv]
foreach src $srcs {
    lappend xvlog_args $src
}

puts [exec xvlog {*}$xvlog_args]
puts [exec xelab tb_core_linux_smoke -debug typical --timescale 1ns/1ps --override_timeunit --override_timeprecision -s tb_core_linux_smoke_sim]
puts [exec xsim tb_core_linux_smoke_sim -runall]
