`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// 公司: 
// 工程师: 
// 
// 创建日期: 2022/05/08 14:28:15
// 模块名称: defogging_top
// 项目名称: 
// 目标器件: 
// 工具版本: 
// 模块功能: 图像去雾顶层模块
//           输入原始 RGB 图像，通过暗通道计算透射率，然后进行去雾处理，输出去雾后的 RGB 图像
//
// 依赖模块: 
//           rgb_dark            - 计算暗通道
//           transmittance_dark  - 计算暗通道最大值与透射率
//           defogging           - 根据透射率进行去雾处理
//
// 修订记录:
// Revision 0.01 - 文件创建
//
//////////////////////////////////////////////////////////////////////////////////

module defogging_top (
	input		  pixelclk     ,	// 像素时钟
	input         reset_n      ,	// 复位信号，低电平有效
	input  [23:0] i_rgb        ,	// 原始 RGB 图像像素数据
	input		  i_hsync      ,	// 行同步信号
	input		  i_vsync      ,	// 场同步信号
	input		  i_de         ,	// 图像数据有效信号
	input [7:0]   i_thre       ,	// 大气光阈值，初始值建议 8'd26
	output [23:0] o_defog_rgb  ,	// 去雾后 RGB 图像像素数据
	output		  o_defog_hsync,	// 去雾后行同步信号
	output		  o_defog_vsync,	// 去雾后场同步信号    
	output		  o_defog_de    	// 去雾后数据有效信号         
);

//////////////////////////////////////////
// 计算 RGB 各通道最小值
// 即得到暗通道图像
//////////////////////////////////////////
wire [7:0] o_dark;         
wire       o_hsync;        
wire       o_vsync;        
wire       o_de;           

rgb_dark u_rgb_dark(
    .pixelclk(pixelclk),
	.reset_n (reset_n),
  	.i_rgb   (i_rgb),
	.i_hsync (i_hsync),
	.i_vsync (i_vsync),
	.i_de    (i_de),	   
    .o_dark  (o_dark),
	.o_hsync (o_hsync),
	.o_vsync (o_vsync),                                                                                                  
	.o_de    (o_de)                                                                                                
);	

	wire        filter_frame_vsync;   // 滤波后场同步
    wire        filter_frame_href;    // 滤波后行同步
    wire        filter_frame_clken;   // 滤波后像素使能
    wire [7:0]  img_dark_channel_filtered;  // 滤波后的暗通道

    min_filter #(
        .DATA_WIDTH (8)  // 数据位宽保持8位（与RGB通道一致）
    ) u_min_filter (
        .clk            (pixelclk),
        .reset_p        (!reset_n),  // 复位极性转换（顶层低有效→子模块高有效）
        .data_in        (o_dark),
        .data_in_valid  (o_de),
        .data_in_hs     (i_hsync),
        .data_in_vs     (i_vsync),
        .data_out       (img_dark_channel_filtered),
        .data_out_valid (filter_frame_clken),
        .data_out_hs    (filter_frame_href),
        .data_out_vs    (filter_frame_vsync)
    );
	//  assign o_defog_rgb={img_dark_channel_filtered,img_dark_channel_filtered,img_dark_channel_filtered};
	//  assign o_defog_hsync=filter_frame_href;
	//  assign o_defog_vsync=filter_frame_vsync;
	//  assign o_defog_de=filter_frame_clken;	
//////////////////////////////////////////
// 计算暗通道最大值及透射率
//////////////////////////////////////////
wire [7:0] dark_max;        
wire [7:0] o_transmittance; 
wire       o_hsync_1;      
wire       o_vsync_1;      
wire       o_de_1;          

transmittance_dark u_transmittance_dark(
    .pixelclk       (pixelclk),
	.reset_n        (reset_n),
  	.i_dark         (img_dark_channel_filtered),
	.i_hsync        (filter_frame_href),
	.i_vsync        (filter_frame_vsync),
	.i_de           (filter_frame_clken),
	.i_thre         (i_thre),
	.o_dark_max     (dark_max),
    .o_transmittance(o_transmittance),
	.o_hsync        (o_hsync_1),
	.o_vsync        (o_vsync_1),                                                                                                  
	.o_de           (o_de_1)                                                                                               
);	

assign o_defog_rgb={o_transmittance,o_transmittance,o_transmittance};
assign o_defog_hsync=o_hsync_1;
assign o_defog_vsync=o_vsync_1;
assign o_defog_de=o_de_1;
//////////////////////////////////////////
//去雾模块
//根据透射率判断像素是否为雾点
//雾点使用去雾算法处理，非雾点保留原始像素
// ////////////////////////////////////////
// defogging u_defogging(
//     .pixelclk       (pixelclk),
// 	.reset_n        (reset_n),
//   	.i_rgb          (i_rgb),
// 	.i_transmittance(o_transmittance),
// 	.dark_max       (dark_max),
// 	.i_hsync        (o_hsync_1),
// 	.i_vsync        (o_vsync_1),
// 	.i_de           (o_de_1),	   
//     .o_defogging    (o_defog_rgb),
// 	.o_hsync        (o_defog_hsync),
// 	.o_vsync        (o_defog_vsync),                                                                                                  
// 	.o_de           (o_defog_de)                                                                                               
// );

endmodule
