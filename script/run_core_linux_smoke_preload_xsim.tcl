set root [file normalize [file join [file dirname [info script]] ..]]
cd $root

set preload_file [file join $root software image linux_smoke_preload.memh]

for {set i 0} {$i < $argc} {incr i} {
    set arg [lindex $argv $i]
    switch -- $arg {
        --preload {
            incr i
            set preload_file [file normalize [lindex $argv $i]]
        }
        default {
            puts "ERROR: unknown argument: $arg"
            puts "Usage: vivado -mode batch -source script/run_core_linux_smoke_preload_xsim.tcl -tclargs ?--preload FILE?"
            exit 1
        }
    }
}

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
    src/integration/boot_ram.v
    src/integration/computer_core.v
    src/tb/tb_core_linux_smoke_preload.v
}

set xvlog_args [list --sv]
foreach src $srcs {
    lappend xvlog_args $src
}

puts [exec xvlog {*}$xvlog_args]
set sim_name [format "tb_core_linux_smoke_preload_sim_%s" [clock seconds]]
puts [exec xelab tb_core_linux_smoke_preload -debug typical --timescale 1ns/1ps --override_timeunit --override_timeprecision -s $sim_name]
puts [exec xsim $sim_name -testplusarg PRELOAD=$preload_file -runall]
