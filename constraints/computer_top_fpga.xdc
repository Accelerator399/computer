# System clock: 100 MHz
set_property PACKAGE_PIN AC19 [get_ports clk]
set_property IOSTANDARD LVCMOS33 [get_ports clk]

# Board reset input, active low on the LS-CPU-EXB-003 style board.
set_property PACKAGE_PIN Y3 [get_ports rst]
set_property IOSTANDARD LVCMOS33 [get_ports rst]

# USB-UART pins reused from the original cache/display project.
set_property PACKAGE_PIN H19 [get_ports uart_tx]
set_property PACKAGE_PIN F23 [get_ports uart_rx]
set_property IOSTANDARD LVCMOS33 [get_ports uart_tx]
set_property IOSTANDARD LVCMOS33 [get_ports uart_rx]

set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]
set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]
set_property BITSTREAM.CONFIG.SPI_BUSWIDTH 4 [current_design]

set_clock_groups -asynchronous \
    -group [get_clocks -quiet clk_out1_clk_wiz_0] \
    -group [get_clocks -quiet clk_pll_i]

set_property SEVERITY {Warning} [get_drc_checks NSTD-1]
set_property SEVERITY {Warning} [get_drc_checks UCIO-1]
set_property SEVERITY {Warning} [get_drc_checks PDRC-34]
set_property SEVERITY {Warning} [get_drc_checks PDRC-43]
