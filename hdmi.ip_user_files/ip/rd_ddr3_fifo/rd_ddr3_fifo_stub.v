// Copyright 1986-2021 Xilinx, Inc. All Rights Reserved.
// --------------------------------------------------------------------------------
// Tool Version: Vivado v.2021.1 (win64) Build 3247384 Thu Jun 10 19:36:33 MDT 2021
// Date        : Fri Oct 10 20:27:06 2025
// Host        : DESKTOP-NADJUM6 running 64-bit major release  (build 9200)
// Command     : write_verilog -force -mode synth_stub
//               e:/BaiduNetdiskDownload/ZILIAO/SHILI/LICHEN/200t/HDMI/HDMI/32BIT/ov5640_ddr3_hdmi_vga.gen/sources_1/ip/rd_ddr3_fifo/rd_ddr3_fifo_stub.v
// Design      : rd_ddr3_fifo
// Purpose     : Stub declaration of top-level module interface
// Device      : xc7a200tfbg484-2
// --------------------------------------------------------------------------------

// This empty module with port declaration file causes synthesis tools to infer a black box for IP.
// The synthesis directives are for Synopsys Synplify support to prevent IO buffer insertion.
// Please paste the declaration into a Verilog source file or add the file as an additional source.
(* x_core_info = "fifo_generator_v13_2_5,Vivado 2021.1" *)
module rd_ddr3_fifo(rst, wr_clk, rd_clk, din, wr_en, rd_en, dout, full, 
  empty, rd_data_count, wr_data_count, wr_rst_busy, rd_rst_busy)
/* synthesis syn_black_box black_box_pad_pin="rst,wr_clk,rd_clk,din[127:0],wr_en,rd_en,dout[15:0],full,empty,rd_data_count[8:0],wr_data_count[5:0],wr_rst_busy,rd_rst_busy" */;
  input rst;
  input wr_clk;
  input rd_clk;
  input [127:0]din;
  input wr_en;
  input rd_en;
  output [15:0]dout;
  output full;
  output empty;
  output [8:0]rd_data_count;
  output [5:0]wr_data_count;
  output wr_rst_busy;
  output rd_rst_busy;
endmodule
