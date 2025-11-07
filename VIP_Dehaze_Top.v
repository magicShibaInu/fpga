`timescale 1ns / 1ps

module VIP_Dehaze_Top #(
    // -------------------------- 统一分辨率参数（仅长和宽） --------------------------
    parameter   IMG_HDISP  = 11'd800,  // 图像水平分辨率（宽），默认800
    parameter   IMG_VDISP  = 11'd600   // 图像垂直分辨率（长），默认600
) (
    input              clk,         // 全局时钟
    input              rst_n,       // 全局复位（低有效）
    // 输入雾天图像信号
    input              per_frame_vsync,  // 场同步
    input              per_frame_href,   // 行同步
    input              per_frame_clken,  // 像素时钟使能
    input      [23:0]  per_img_data,     // 输入像素：{R[23:16], G[15:8], B[7:0]}
    // 输出去雾后图像信号
    output             post_frame_vsync, // 输出场同步
    output             post_frame_href,  // 输出行同步
    output             post_frame_clken, // 输出像素时钟使能
    output     [7:0]   post_img_red,     // 去雾后R通道
    output     [7:0]   post_img_green,   // 去雾后G通道
    output     [7:0]   post_img_blue     // 去雾后B通道
);
 
    // 分解输入RGB为单独通道
    wire [7:0] per_img_red   = per_img_data[23:16];
    wire [7:0] per_img_green = per_img_data[15:8];
    wire [7:0] per_img_blue  = per_img_data[7:0];

    // ---------------------------------------------------
    // 1. 计算暗通道（RGB三通道最小值）：调用 vp_rgb888_min
    wire        min_frame_vsync;   // vp_rgb888_min 输出的场同步
    wire        min_frame_href;    // vp_rgb888_min 输出的行同步
    wire        min_frame_clken;   // vp_rgb888_min 输出的像素使能
    wire [7:0]  img_dark_channel;  // 暗通道结果（RGB最小值，未滤波）

    VIP_RGB888_MIN u_vp_rgb888_min (
        .clk                (clk),
        .rst_n              (rst_n),
        .per_frame_vsync    (per_frame_vsync),
        .per_frame_href     (per_frame_href),
        .per_frame_clken    (per_frame_clken),
        .per_img_data       (per_img_data),
        .post_frame_vsync   (min_frame_vsync),
        .post_frame_href    (min_frame_href),
        .post_frame_clken   (min_frame_clken),
        .post_RGB_MIN       (img_dark_channel)  
    );

    // ---------------------------------------------------
    // 1.5 最小值滤波：对暗通道进行3x3最小值滤波，调用 min_filter
    wire        filter_frame_vsync;   // 滤波后场同步
    wire        filter_frame_href;    // 滤波后行同步
    wire        filter_frame_clken;   // 滤波后像素使能
    wire [7:0]  img_dark_channel_filtered;  // 滤波后的暗通道

    min_filter #(
        .DATA_WIDTH (8)  // 数据位宽保持8位（与RGB通道一致）
    ) u_min_filter (
        .clk            (clk),
        .reset_p        (!rst_n),  // 复位极性转换（顶层低有效→子模块高有效）
        .data_in        (img_dark_channel),
        .data_in_valid  (min_frame_clken),
        .data_in_hs     (min_frame_href),
        .data_in_vs     (min_frame_vsync),
        .data_out       (img_dark_channel_filtered),
        .data_out_valid (filter_frame_clken),
        .data_out_hs    (filter_frame_href),
        .data_out_vs    (filter_frame_vsync)
    );

    // assign post_frame_vsync = filter_frame_vsync;
    // assign post_frame_href  = filter_frame_href;
    // assign post_frame_clken = filter_frame_clken;

    // assign post_img_red     = img_dark_channel_filtered;
    // assign post_img_green   = img_dark_channel_filtered;
    // assign post_img_blue    = img_dark_channel_filtered;

    // ---------------------------------------------------
    // // 2. 计算大气光照强度：调用 VIP_Atmospheric_Light，传递统一分辨率
    // wire [7:0]   atmospheric_light; // 大气光照强度结果
    // wire [9:0]   atmospheric_pos_x; // 大气光照位置X（位宽适配最大分辨率）
    // wire [9:0]   atmospheric_pos_y; // 大气光照位置Y

    // VIP_Atmospheric_Light #(
    //     .IMG_HDISP  (IMG_HDISP),  // 传递顶层统一的水平分辨率（宽）
    //     .IMG_VDISP  (IMG_VDISP)   // 传递顶层统一的垂直分辨率（长）
    // ) u_VIP_Atmospheric_Light (
    //     .clk                (clk),
    //     .rst_n              (rst_n),
    //     .per_frame_vsync    (filter_frame_vsync),
    //     .per_frame_href     (filter_frame_href),
    //     .per_frame_clken    (filter_frame_clken),
    //     .per_img_Dark       (img_dark_channel_filtered),
    //     .per_img_red        (per_img_red),
    //     .per_img_green      (per_img_green),
    //     .per_img_blue       (per_img_blue),
    //     .atmospheric_light  (atmospheric_light),
    //     .atmospheric_pos_x  (atmospheric_pos_x),
    //     .atmospheric_pos_y  (atmospheric_pos_y)
    // );

    // // ---------------------------------------------------
    // // 3. 计算透射率图像：调用 VIP_Transmission_Map
    // wire        trans_frame_vsync;  // 透射率模块输出场同步
    // wire        trans_frame_href;   // 透射率模块输出行同步
    // wire        trans_frame_clken;  // 透射率模块输出像素使能
    // wire [7:0]  post_transmission;  // 透射率结果

    // VIP_Transmission_Map u_VIP_Transmission_Map (
    //     .clk                (clk),
    //     .rst_n              (rst_n),
    //     .per_frame_vsync    (filter_frame_vsync),
    //     .per_frame_href     (filter_frame_href),
    //     .per_frame_clken    (filter_frame_clken),
    //     .per_img_Dark       (img_dark_channel_filtered),
    //     .atmospheric_light  (atmospheric_light),
    //     .post_frame_vsync   (trans_frame_vsync),
    //     .post_frame_href    (trans_frame_href),
    //     .post_frame_clken   (trans_frame_clken),
    //     .post_transmission  (post_transmission)
    // );

    // assign post_frame_vsync = trans_frame_vsync;
    // assign post_frame_href  = trans_frame_href;
    // assign post_frame_clken = trans_frame_clken;

    // assign post_img_red     = post_transmission;
    // assign post_img_green   = post_transmission;
    // assign post_img_blue    = post_transmission;
    // ---------------------------------------------------
    wire        trans_frame_vsync;  // 透射率模块输出场同步
    wire        trans_frame_href;   // 透射率模块输出行同步
    wire        trans_frame_clken;  // 透射率模块输出像素使能
    wire [7:0]  post_transmission;  // 透射率结果
    transmittance_dark u_transmittance_dark(
    .pixelclk       (clk),
	.reset_n        (rst_n),
  	.i_dark         (img_dark_channel_filtered),
	.i_hsync        (filter_frame_href),
	.i_vsync        (filter_frame_vsync),
	.i_de           (filter_frame_clken),
	.i_thre         (8'd20),
	.o_dark_max     (atmospheric_light),
    .o_transmittance(post_transmission),
	.o_hsync        (trans_frame_href),
	.o_vsync        (trans_frame_vsync),                                                                                                  
	.o_de           (trans_frame_clken)                                                                                               
);	
    // assign post_frame_vsync=trans_frame_vsync;
    // assign post_frame_href=trans_frame_href;
    // assign post_frame_clken=trans_frame_clken;
    // assign post_img_red=post_transmission;
    // assign post_img_green=post_transmission;
    // assign post_img_blue=post_transmission;

    //4. 恢复场景辐射（去雾）：调用 VIP_scene_radiance，传递统一分辨率
    VIP_scene_radiance #(
        .IMG_HDISP  (IMG_HDISP),  // 传递顶层统一的水平分辨率（宽）
        .IMG_VDISP  (IMG_VDISP)   // 传递顶层统一的垂直分辨率（长）
    ) u_VIP_scene_radiance (
        .clk                (clk),
        .rst_n              (rst_n),
        .per_frame_vsync    (trans_frame_vsync),
        .per_frame_href     (trans_frame_href),
        .per_frame_clken    (trans_frame_clken),
        .per_transmission   (post_transmission),
        .per_img_red        (per_img_red),
        .per_img_green      (per_img_green),
        .per_img_blue       (per_img_blue),
        .atmospheric_light  (atmospheric_light),
        .post_frame_vsync   (post_frame_vsync),
        .post_frame_href    (post_frame_href),
        .post_frame_clken   (post_frame_clken),
        .post_img_red       (post_img_red),
        .post_img_green     (post_img_green),
        .post_img_blue      (post_img_blue)
    );

endmodule
