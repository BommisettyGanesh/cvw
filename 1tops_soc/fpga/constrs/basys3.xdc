##=============================================================================
## Basys 3 Master Constraints for CORE-V Wally RISC-V SoC with Dual-Protocol Debug
## Target Device: xc7a35tcpg236-1
##=============================================================================

## 1. 100 MHz On-Board Oscillator
set_property PACKAGE_PIN W5 [get_ports clk]
set_property IOSTANDARD LVCMOS33 [get_ports clk]
create_clock -add -name sys_clk_pin -period 10.00 -waveform {0 5} [get_ports clk]

## 2. System Reset (Center Pushbutton btnC - Active High converted to rst_n)
set_property PACKAGE_PIN U18 [get_ports reset_btn]
set_property IOSTANDARD LVCMOS33 [get_ports reset_btn]

## 3. Protocol Selection Switch (Slide Switch SW0)
##    SW0 = 0 (Down) -> PMOD JA UART Active
##    SW0 = 1 (Up)   -> PMOD JB FT1248 Active
set_property PACKAGE_PIN V17 [get_ports dbg_sel]
set_property IOSTANDARD LVCMOS33 [get_ports dbg_sel]
set_property PULLDOWN TRUE [get_ports dbg_sel]

## 4. Dedicated Debugger UART on PMOD JA (Top Row)
## Pin 1 (J1) = uart_rx (Connect to external USB-UART Dongle TXD)
set_property PACKAGE_PIN J1 [get_ports uart_rx]
set_property IOSTANDARD LVCMOS33 [get_ports uart_rx]
set_property PULLUP TRUE [get_ports uart_rx]

## Pin 2 (L2) = uart_tx (Connect to external USB-UART Dongle RXD)
set_property PACKAGE_PIN L2 [get_ports uart_tx]
set_property IOSTANDARD LVCMOS33 [get_ports uart_tx]

## 5. Dedicated FT1248 High-Speed Interface on PMOD JB (Top Row)
## Pin 1 (A14) = SCLK Clock Out
set_property PACKAGE_PIN A14 [get_ports ft1248_clk]
set_property IOSTANDARD LVCMOS33 [get_ports ft1248_clk]
set_property SLEW FAST [get_ports ft1248_clk]

## Pin 2 (A16) = SS# Slave Select Out
set_property PACKAGE_PIN A16 [get_ports ft1248_ss_n]
set_property IOSTANDARD LVCMOS33 [get_ports ft1248_ss_n]
set_property SLEW FAST [get_ports ft1248_ss_n]

## Pin 3 (B15) = MISO / RXF# In
set_property PACKAGE_PIN B15 [get_ports ft1248_miso]
set_property IOSTANDARD LVCMOS33 [get_ports ft1248_miso]
set_property PULLUP TRUE [get_ports ft1248_miso]

## Pin 4 (B16) = MIOSIO Bidirectional Data Bus
set_property PACKAGE_PIN B16 [get_ports ft1248_miosio]
set_property IOSTANDARD LVCMOS33 [get_ports ft1248_miosio]
set_property PULLUP TRUE [get_ports ft1248_miosio]
set_property SLEW FAST [get_ports ft1248_miosio]
set_property DRIVE 8 [get_ports ft1248_miosio]

## 6. Optional: Uncore Application 16550 UART (on On-Board Micro-USB Port B18/A18)
##    Allows viewing runtime printf() console output through the onboard USB cable!
set_property PACKAGE_PIN B18 [get_ports UARTSin]
set_property IOSTANDARD LVCMOS33 [get_ports UARTSin]
set_property PULLUP TRUE [get_ports UARTSin]

set_property PACKAGE_PIN A18 [get_ports UARTSout]
set_property IOSTANDARD LVCMOS33 [get_ports UARTSout]

## 7. Status LEDs (Optional visual feedback)
set_property PACKAGE_PIN U16 [get_ports led_core_halted]
set_property IOSTANDARD LVCMOS33 [get_ports led_core_halted]

set_property PACKAGE_PIN E19 [get_ports led_dbg_sel]
set_property IOSTANDARD LVCMOS33 [get_ports led_dbg_sel]

## 8. Asynchronous I/O False Paths (Buttons, Switches, LEDs, Serial Lines, FT1248 PMOD)
set_false_path -from [get_ports reset_btn]
set_false_path -from [get_ports dbg_sel]
set_false_path -from [get_ports uart_rx]
set_false_path -from [get_ports UARTSin]
set_false_path -from [get_ports ft1248_miso]
set_false_path -from [get_ports ft1248_miosio*]
set_false_path -to   [get_ports led_*]
set_false_path -to   [get_ports uart_tx]
set_false_path -to   [get_ports UARTSout]
set_false_path -to   [get_ports ft1248_*]

## 9. Bitstream Generation Configuration (SPI Quad-Mode for Fast Basys 3 Boot)
set_property BITSTREAM.CONFIG.SPI_BUSWIDTH 4 [current_design]
set_property CONFIG_MODE SPIx4 [current_design]

