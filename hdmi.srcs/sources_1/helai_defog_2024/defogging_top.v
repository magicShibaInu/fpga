`timescale 1ns / 1ps


module defogging_top (
	input		  pixelclk     ,	//像素时钟
	input         reset_n      ,	//低电平复位
	input  [23:0] i_rgb        ,	//原始图像像素数据
	input		  i_hsync      ,	//原始图像行同步
	input		  i_vsync      ,	//原始图像场同步
	input		  i_de         ,	//原始图像数据有效
	input [7:0]   i_thre       ,	//大气光阈值,初始值为8'd26
	output [23:0] o_defog_rgb  ,	//去雾图像像素数据
	output		  o_defog_hsync,	//去雾图像行同步
	output		  o_defog_vsync,	//去雾图像场同步      
	output		  o_defog_de    	//去雾图像数据有效             
);

wire [ 7:0] o_dark         ;
wire		o_hsync        ;
wire		o_vsync        ;
wire		o_de           ;
wire [7: 0] dark_max       ;
wire [7:0]  o_transmittance;
wire		o_hsync_1      ;
wire		o_vsync_1      ;
wire		o_de_1         ;
wire        r_defog_hs     ;
wire        r_defog_vs     ;
wire        r_defog_de     ;
wire [23:0] r_defog_rgb    ;

//////////////////////////////////////////
//求RGB分量的最小值
//即求出暗通道
//////////////////////////////////////////   		
rgb_dark u_rgb_dark(
    .pixelclk(pixelclk),
	.reset_n (reset_n ),
  	.i_rgb   (i_rgb   ),
	.i_hsync (i_hsync ),
	.i_vsync (i_vsync ),
	.i_de    (i_de    ),	   
    .o_dark  (o_dark  ),
	.o_hsync (o_hsync ),
	.o_vsync (o_vsync ),                                                                                                  
	.o_de    (o_de    )                                                                                                
);	

//////////////////////////////////////////
//求暗通道最大值和折射率
//////////////////////////////////////////	
transmittance_dark u_transmittance_dark(
    .pixelclk       (pixelclk        ),
	.reset_n        (reset_n         ),
  	.i_dark         (o_dark          ),
	.i_hsync        (o_hsync         ),
	.i_vsync        (o_vsync         ),
	.i_de           (o_de            ),
	.i_thre         (i_thre          ),
	.o_dark_max     (dark_max        ),
    .o_transmittance(o_transmittance ),
	.o_hsync        (o_hsync_1       ),
	.o_vsync        (o_vsync_1       ),                                                                                                  
	.o_de           (o_de_1          )                                                                                               
);	

//////////////////////////////////////////
//去雾,判断为雾点则被算法取代像素值
//判断为非雾点则填充原始的像素值
//////////////////////////////////////////
defogging u_defogging(
    .pixelclk       (pixelclk       ),
	.reset_n        (reset_n        ),
  	.i_rgb          (i_rgb          ),
	.i_transmittance(o_transmittance),
	.dark_max       (dark_max       ),
	.i_hsync        (o_hsync_1      ),
	.i_vsync        (o_vsync_1      ),
	.i_de           (o_de_1         ),	   
    .o_defogging    (o_defog_rgb    ),
	.o_hsync        (o_defog_hsync  ),
	.o_vsync        (o_defog_vsync  ),                                                                                                  
	.o_de           (o_defog_de     )                                                                                               
);

endmodule
