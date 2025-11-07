`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2025/10/22 22:24:46
// Design Name: 
// Module Name: uart_top
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


module uart_top(clk,rst_n,uart_rx,uart_tx);
input clk;       //时钟，100MHZ
input rst_n;     //复位，低电平有效
input uart_rx;   //FPGA通过串口接收的数据
output uart_tx;  //FPGA通过串口发送的数据

wire [7:0]data;
wire data_vld;

//接收模块
uart_rx u1(.clk(clk),    
           .rst_n(rst_n),
           .din(uart_rx),
           .dout(data),
           .dout_vld(data_vld)
           );

//发送模块
uart_tx u2(.clk(clk),
           .rst_n(rst_n),
           .din_vld(data_vld),
           .din(data),
           .dout(uart_tx)
           );

endmodule
