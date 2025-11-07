// Copyright 1986-2021 Xilinx, Inc. All Rights Reserved.
// --------------------------------------------------------------------------------
// Tool Version: Vivado v.2021.1 (win64) Build 3247384 Thu Jun 10 19:36:33 MDT 2021
// Date        : Sat Oct 11 10:47:48 2025
// Host        : DESKTOP-NADJUM6 running 64-bit major release  (build 9200)
// Command     : write_verilog -force -mode synth_stub
//               e:/BaiduNetdiskDownload/ZILIAO/SHILI/LICHEN/200t/HDMI/HDMI/32BIT/ov5640_ddr3_hdmi_vga.gen/sources_1/ip/vio_0/vio_0_stub.v
// Design      : vio_0
// Purpose     : Stub declaration of top-level module interface
// Device      : xc7a200tfbg484-2
// --------------------------------------------------------------------------------

// This empty module with port declaration file causes synthesis tools to infer a black box for IP.
// The synthesis directives are for Synopsys Synplify support to prevent IO buffer insertion.
// Please paste the declaration into a Verilog source file or add the file as an additional source.
(* X_CORE_INFO = "vio,Vivado 2021.1" *)
module vio_0(clk, probe_out0)
/* synthesis syn_black_box black_box_pad_pin="clk,probe_out0[7:0]" */;
  input clk;
  output [7:0]probe_out0;
endmodule
