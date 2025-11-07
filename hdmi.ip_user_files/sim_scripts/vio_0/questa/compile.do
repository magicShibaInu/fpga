vlib questa_lib/work
vlib questa_lib/msim

vlib questa_lib/msim/xpm
vlib questa_lib/msim/xil_defaultlib

vmap xpm questa_lib/msim/xpm
vmap xil_defaultlib questa_lib/msim/xil_defaultlib

vlog -work xpm  -incr -mfcu -sv "+incdir+../../../../ov5640_ddr3_hdmi_vga.gen/sources_1/ip/vio_0/hdl/verilog" "+incdir+../../../../ov5640_ddr3_hdmi_vga.gen/sources_1/ip/vio_0/hdl" \
"E:/Vivado/2021.1/data/ip/xpm/xpm_cdc/hdl/xpm_cdc.sv" \
"E:/Vivado/2021.1/data/ip/xpm/xpm_memory/hdl/xpm_memory.sv" \

vcom -work xpm  -93 \
"E:/Vivado/2021.1/data/ip/xpm/xpm_VCOMP.vhd" \

vlog -work xil_defaultlib  -incr -mfcu "+incdir+../../../../ov5640_ddr3_hdmi_vga.gen/sources_1/ip/vio_0/hdl/verilog" "+incdir+../../../../ov5640_ddr3_hdmi_vga.gen/sources_1/ip/vio_0/hdl" \
"../../../../ov5640_ddr3_hdmi_vga.gen/sources_1/ip/vio_0/sim/vio_0.v" \

vlog -work xil_defaultlib \
"glbl.v"

