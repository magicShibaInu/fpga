// Copyright 1986-2019 Xilinx, Inc. All Rights Reserved.
// --------------------------------------------------------------------------------
// Tool Version: Vivado v.2019.2 (win64) Build 2708876 Wed Nov  6 21:40:23 MST 2019
// Date        : Mon Oct 13 15:43:45 2025
// Host        : liuxiahui running 64-bit major release  (build 9200)
// Command     : write_verilog -force -mode synth_stub
//               e:/acx750/a32bit1/ov5640_ddr3_hdmi_vga.srcs/sources_1/ip/blk_mem_gen_2/blk_mem_gen_2_stub.v
// Design      : blk_mem_gen_2
// Purpose     : Stub declaration of top-level module interface
// Device      : xc7a200tfbg484-2
// --------------------------------------------------------------------------------

// This empty module with port declaration file causes synthesis tools to infer a black box for IP.
// The synthesis directives are for Synopsys Synplify support to prevent IO buffer insertion.
// Please paste the declaration into a Verilog source file or add the file as an additional source.
(* x_core_info = "blk_mem_gen_v8_4_4,Vivado 2019.2" *)
module blk_mem_gen_2(clka, ena, wea, addra, dina, douta, clkb, enb, web, addrb, 
  dinb, doutb)
/* synthesis syn_black_box black_box_pad_pin="clka,ena,wea[0:0],addra[7:0],dina[19:0],douta[19:0],clkb,enb,web[0:0],addrb[7:0],dinb[19:0],doutb[19:0]" */;
  input clka;
  input ena;
  input [0:0]wea;
  input [7:0]addra;
  input [19:0]dina;
  output [19:0]douta;
  input clkb;
  input enb;
  input [0:0]web;
  input [7:0]addrb;
  input [19:0]dinb;
  output [19:0]doutb;
endmodule
