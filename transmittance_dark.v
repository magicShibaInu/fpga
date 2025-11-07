`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// 模块名称: transmittance_dark
// 模块功能: 根据暗通道计算透射率
//           输入暗通道图像，计算暗通道最大值，并通过查表或近似计算透射率
// 输入信号: i_dark   - 暗通道像素值
//           i_hsync  - 行同步信号
//           i_vsync  - 场同步信号
//           i_de     - 数据有效信号
//           i_thre   - 最小透射率阈值
// 输出信号: o_dark_max       - 当前帧暗通道最大值
//           o_transmittance  - 输出透射率
//           o_hsync/o_vsync/o_de - 对齐的同步信号
//////////////////////////////////////////////////////////////////////////////////

module transmittance_dark(
	input         pixelclk       , // 像素时钟
	input         reset_n        , // 低有效复位
    input  [7:0]  i_dark         , // 暗通道输入
	input         i_hsync        , // 行同步
	input         i_vsync        , // 场同步
	input         i_de           , // 数据有效
	input [7:0]   i_thre         , // 透射率最小阈值
	output [7:0]  o_dark_max     , // 当前帧暗通道最大值
    output [7:0]  o_transmittance, // 输出透射率
	output        o_hsync        ,
	output        o_vsync        ,                                                                                                  
	output        o_de                                                                                                       
);

//////////////////////////////////////////
// 信号寄存，延迟3拍对齐同步信号和像素值
//////////////////////////////////////////
reg        hsync_r, hsync_r0, hsync_r1;
reg        vsync_r, vsync_r0, vsync_r1;
reg        de_r, de_r0, de_r1;
reg  [7:0] r_i_dark;

always @(posedge pixelclk) begin
    hsync_r  <= i_hsync;
    vsync_r  <= i_vsync;
    de_r     <= i_de;
    r_i_dark <= i_dark;
    
    hsync_r0 <= hsync_r;
    vsync_r0 <= vsync_r;
    de_r0    <= de_r;
    
    hsync_r1 <= hsync_r0;
    vsync_r1 <= vsync_r0;
    de_r1    <= de_r0;
end

assign o_hsync = hsync_r1;
assign o_vsync = vsync_r1;
assign o_de    = de_r1;

//////////////////////////////////////////
// 暗通道最大值计算
// 遍历一帧像素，记录最大暗通道值
//////////////////////////////////////////
reg [7:0] max_dark;
reg [7:0] max_dark_data;

always @(posedge pixelclk) begin
    if(!reset_n) begin
        max_dark      <= 8'b0;
        max_dark_data <= 8'b0;
    end
    else if(de_r) begin
        if(r_i_dark > max_dark)
            max_dark <= r_i_dark;
        max_dark_data <= max_dark;
    end
end

assign o_dark_max = max_dark_data;

//////////////////////////////////////////
// 透射率计算（近似查表或移位加法法）
// 根据暗通道最大值范围选择不同的计算方式
// t(x) = 1 - w * minI(y)/A
//////////////////////////////////////////
reg [7:0] transmittance_img;
reg [7:0] transmittance;

always @(posedge pixelclk) begin
    if(!reset_n) begin
        transmittance_img <= 0;
        transmittance     <= 0;
    end
    else if(max_dark_data>8'd160 && max_dark_data<8'd170) begin
        transmittance <= r_i_dark;
        transmittance_img <= 8'd255 - transmittance;
    end
    else if(max_dark_data>8'd170 && max_dark_data<8'd180) begin
        transmittance <= (r_i_dark[7:1] + r_i_dark[7:2] + r_i_dark[7:3] + r_i_dark[7:4]); // 约 0.9375
        transmittance_img <= 8'd255 - transmittance;
    end
    else if(max_dark_data>8'd180 && max_dark_data<8'd190) begin
        transmittance <= (r_i_dark[7:1] + r_i_dark[7:2] + r_i_dark[7:3]); // 约 0.875
        transmittance_img <= 8'd255 - transmittance;
    end
    else if(max_dark_data>8'd190 && max_dark_data<8'd200) begin
        transmittance <= (r_i_dark[7:1] + r_i_dark[7:2] + r_i_dark[7:4]); // 约 0.8125
        transmittance_img <= 8'd255 - transmittance;
    end
    else if(max_dark_data>8'd200 && max_dark_data<8'd210) begin
        transmittance <= (r_i_dark[7:1] + r_i_dark[7:2] + r_i_dark[7:5]); // 约 0.78125
        transmittance_img <= 8'd255 - transmittance;
    end
    else if(max_dark_data>8'd210 && max_dark_data<8'd220) begin
        transmittance <= (r_i_dark[7:1] + r_i_dark[7:2]); // 约 0.75
        transmittance_img <= 8'd255 - transmittance;
    end
    else if(max_dark_data>8'd220 && max_dark_data<8'd230) begin
        transmittance <= (r_i_dark[7:1] + r_i_dark[7:3] + r_i_dark[7:4] + r_i_dark[7:5]); // 约 0.725
        transmittance_img <= 8'd255 - transmittance;
    end
    else if(max_dark_data>8'd230 && max_dark_data<8'd240) begin
        transmittance <= (r_i_dark[7:1] + r_i_dark[7:3] + r_i_dark[7:4]); // 约 0.6875
        transmittance_img <= 8'd255 - transmittance;
    end
    else if(max_dark_data>8'd240) begin
        transmittance <= (r_i_dark[7:1] + r_i_dark[7:3] + r_i_dark[7:6]); // 约 0.65
        transmittance_img <= 8'd255 - transmittance;
    end
    else begin
        transmittance_img <= 0;
        transmittance     <= 0;
    end
end

//////////////////////////////////////////
// 最终透射率输出
// 最小透射率阈值 i_thre 保护
//////////////////////////////////////////
reg [7:0] transmittance_result;

always @(posedge pixelclk) begin
    if(!reset_n)
        transmittance_result <= 8'b0;
    else if(transmittance_img > i_thre)
        transmittance_result <= transmittance_img;
    else
        transmittance_result <= i_thre;
end

assign o_transmittance = transmittance_result;

endmodule
