`timescale 1ns / 1ps
module gamma(
input           clk         ,
input           rst_n       ,
input   [23:0]  i_rgb888    ,
input           i_vsync     ,
input           i_hsync     ,
input           i_vaild     ,
output  [23:0]  o_rgb888    ,
output          o_vsync     ,
output          o_hsync     ,
output          o_vaild   
    );
    
 
reg [1:0]   i_vsync_r;
reg [1:0]   i_hsync_r;
reg [1:0]   i_vaild_r;
 
    //红色
    gamma_adjust gamma_adjust_u1(
.  clk        (clk),
.  rst_n      (rst_n),
.  i_rgb888   (i_rgb888[23:16]),
.  o_rgb888   (o_rgb888[23:16])
    );
    //绿色
    gamma_adjust gamma_adjust_u2(
.  clk        (clk),
.  rst_n      (rst_n),
.  i_rgb888   (i_rgb888[15:8]),
.  o_rgb888   (o_rgb888[15:8])
    );
    //蓝色
    gamma_adjust gamma_adjust_u3(
.  clk        (clk),
.  rst_n      (rst_n),
.  i_rgb888   (i_rgb888[7:0]),
.  o_rgb888   (o_rgb888[7:0])
    );
//同步打拍，否则图像会平移
always @(posedge clk) begin
    i_vsync_r <= {i_vsync_r[0],i_vsync};
    i_hsync_r <= {i_hsync_r[0],i_hsync};
    i_vaild_r <= {i_vaild_r[0],i_vaild};
end
 
assign o_vsync = i_vsync_r[1];
assign o_hsync = i_hsync_r[1];
assign o_vaild = i_vaild_r[1];
 
 
    
endmodule