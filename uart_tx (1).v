`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2025/10/22 22:25:32
// Design Name: 
// Module Name: uart_tx
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module uart_tx
#(parameter CLK = 100_000_000,  //100MHZ时钟
  parameter BPS = 9600,         //9600波特率
  parameter BPS_CNT = CLK/BPS   //波特率计数
  )
(clk,rst_n,din,din_vld,dout);
input wire clk;
input wire rst_n;
input wire [7:0]din;   //输入数据
input wire din_vld;    //输入数据的有效指示
output reg dout;       //输出数据

reg flag;
reg [7:0]din_tmp;
reg [15:0]cnt0;      //波特率计数
wire add_cnt0;
wire end_cnt0;
reg [3:0]cnt1;       //数据位计数
wire add_cnt1;
wire end_cnt1;
wire [9:0]data;      //发送数据

//数据暂存（din可能会消失）
always @(posedge clk or negedge rst_n)
  begin
    if(!rst_n)
      din_tmp <= 8'd0;
    else if(din_vld)
      din_tmp <= din;
  end

//发送状态指示
always @(posedge clk or negedge rst_n)
  begin
    if(!rst_n)
      flag <= 0;
    else if(din_vld)
      flag <= 1;
    else if(end_cnt1)
      flag <= 0;
  end

//波特率计数
always @(posedge clk or negedge rst_n)
  begin
    if(!rst_n)
      cnt0 <= 0;
    else if(add_cnt0)
      begin
        if(end_cnt0)
          cnt0 <= 0;
        else
          cnt0 <= cnt0 + 1'b1;
      end
  end

assign add_cnt0 = flag;
assign end_cnt0 = (cnt0 == (BPS_CNT-1)) || end_cnt1;
//开始1位+数据8位+停止1位，共10位
always @(posedge clk or negedge rst_n)
  begin
    if(!rst_n)
      cnt1 <= 0;
    else if(add_cnt1)
      begin
        if(end_cnt1) 
          cnt1 <= 0;
        else
          cnt1 <= cnt1 + 1'b1;
      end
  end

assign add_cnt1 = end_cnt0;
assign end_cnt1 = (cnt1 == (10-1))&&(cnt0==(BPS_CNT/2-1));
//数据输出
assign data = {1'b1,din_tmp,1'b0};

always @(posedge clk or negedge rst_n)
  begin
    if(!rst_n)
      dout <= 1'b1;
    else if(flag)
      dout <= data[cnt1];
  end

endmodule

