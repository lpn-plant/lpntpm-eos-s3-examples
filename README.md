## QORC "EOS S3" Application with embedded "LPC Peripheral" (Verilog RTL)
### Intro

This is application for SOC "EOS S3" (Quicklogic company) with embedded 
"LPC Peripheral" driver (implemented in FPGA part of SOC). The FPGA part is 
listening for LPC protocol cycles on I/O pins derived on SOC board sockets. 
When I/O cycles of LPC protocol are detected, their data (LPC address and LPC data)
are send to MCU part by "Wishbone Bus" bridge to MCU ARM Cortex-M4 and displayed 
by MCU UART.
