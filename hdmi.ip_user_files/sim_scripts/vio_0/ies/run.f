-makelib ies_lib/xpm -sv \
  "E:/Vivado/2021.1/data/ip/xpm/xpm_cdc/hdl/xpm_cdc.sv" \
  "E:/Vivado/2021.1/data/ip/xpm/xpm_memory/hdl/xpm_memory.sv" \
-endlib
-makelib ies_lib/xpm \
  "E:/Vivado/2021.1/data/ip/xpm/xpm_VCOMP.vhd" \
-endlib
-makelib ies_lib/xil_defaultlib \
  "../../../../ov5640_ddr3_hdmi_vga.gen/sources_1/ip/vio_0/sim/vio_0.v" \
-endlib
-makelib ies_lib/xil_defaultlib \
  glbl.v
-endlib

