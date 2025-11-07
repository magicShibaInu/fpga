vlib work
vlib riviera

vlib riviera/xpm
vlib riviera/xil_defaultlib

vmap xpm riviera/xpm
vmap xil_defaultlib riviera/xil_defaultlib

vlog -work xpm  -sv2k12 "+incdir+../../../../ov5640_ddr3_hdmi_vga.gen/sources_1/ip/vio_0/hdl/verilog" "+incdir+../../../../ov5640_ddr3_hdmi_vga.gen/sources_1/ip/vio_0/hdl" \
"E:/Vivado/2021.1/data/ip/xpm/xpm_cdc/hdl/xpm_cdc.sv" \
"E:/Vivado/2021.1/data/ip/xpm/xpm_memory/hdl/xpm_memory.sv" \

vcom -work xpm -93 \
"E:/Vivado/2021.1/data/ip/xpm/xpm_VCOMP.vhd" \

vlog -work xil_defaultlib  -v2k5 "+incdir+../../../../ov5640_ddr3_hdmi_vga.gen/sources_1/ip/vio_0/hdl/verilog" "+incdir+../../../../ov5640_ddr3_hdmi_vga.gen/sources_1/ip/vio_0/hdl" \
"../../../../ov5640_ddr3_hdmi_vga.gen/sources_1/ip/vio_0/sim/vio_0.v" \

vlog -work xil_defaultlib \
"glbl.v"

