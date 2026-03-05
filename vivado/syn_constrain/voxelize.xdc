# Minimal constraints for top: voxelize
# File: vivado/syn_rtl/voxelize.xdc
# Add this XDC into your Vivado project (Constraints -> Add Sources).

# ------------------------------------------------------------
# Clock
# ------------------------------------------------------------
# Assumes external free-running clock on port "clk".
# Change period to match your board clock frequency.
# 100 MHz -> 10.000 ns
create_clock -name clk -period 10.000 [get_ports clk]

# Optional: small uncertainty (adjust as needed)
set_clock_uncertainty 0.200 [get_clocks clk]

# ------------------------------------------------------------
# Reset
# ------------------------------------------------------------
# rst_n is active-low async reset in your RTL naming.
# Do NOT create a clock on reset.
# If reset is asynchronous, it is common to ignore timing on it:
set_false_path -from [get_ports rst_n]

# ------------------------------------------------------------
# (Optional) IO standards / pin locations (FILL THESE)
# ------------------------------------------------------------
# Without real pin constraints, implementation on a real FPGA board
# will fail. For synthesis-only, these can stay commented.
#
# Example for Xilinx boards (edit PACKAGE_PIN + IOSTANDARD):
# set_property PACKAGE_PIN <PIN>      [get_ports clk]
# set_property IOSTANDARD  LVCMOS33   [get_ports clk]
#
# set_property PACKAGE_PIN <PIN>      [get_ports rst_n]
# set_property IOSTANDARD  LVCMOS33   [get_ports rst_n]
#
# If you export debug signals to top (debug_a/debug_b/bram_addr_a/bram_addr_b),
# you can also constrain them here.
