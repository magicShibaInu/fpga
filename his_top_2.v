`timescale 1ns / 1ps
module VIP_HistEQ_Top_2#
(
    parameter IMG_TOTAL = 480000
)
(
    input  wire        clk,
    input  wire        rst_n,

    //==============================
    // 输入图像接口 (YCbCr 输入)
    //==============================
    input  wire        per_img_vsync,
    input  wire        per_img_href,
    input  wire [7:0]  per_img_y,      // 原 per_img_gray -> per_img_y
    input  wire [7:0]  per_img_cb,     // 新增 Cb 通道
    input  wire [7:0]  per_img_cr,     // 新增 Cr 通道

    //==============================
    // 输出均衡化图像接口 (YCbCr 输出)
    //==============================
    output wire        post_img_vsync,
    output wire        post_img_href,
    output wire [7:0]  post_img_y,
    output wire [7:0]  post_img_cb,
    output wire [7:0]  post_img_cr
);

    //==================================================================
    // 信号声明
    //==================================================================
    wire        histEQ_start_flag;
    wire [7:0]  pixel_level;
    wire [19:0] pixel_level_acc_num;
    wire        pixel_level_valid;

    //==================================================================
    // 亮度通道 Y 的直方图统计模块
    //==================================================================
    hist_stat u_hist_stat (
        .clk                  (clk),
        .rst_n                (rst_n),
        .img_vsync            (per_img_vsync),
        .img_href             (per_img_href),
        .img_gray             (per_img_y),          // 改为亮度通道
        .pixel_level          (pixel_level),
        .pixel_level_acc_num  (pixel_level_acc_num),
        .pixel_level_valid    (pixel_level_valid)
    );

    //==================================================================
    // 亮度通道 Y 的直方图均衡化处理模块
    //==================================================================
    histEQ_proc #(
        .IMG_TOTAL(IMG_TOTAL)
    ) u_histEQ_proc (
        .clk                  (clk),
        .rst_n                (rst_n),
        .pixel_level          (pixel_level),
        .pixel_level_acc_num  (pixel_level_acc_num),
        .pixel_level_valid    (pixel_level_valid),
        .histEQ_start_flag    (histEQ_start_flag),
        .per_img_vsync        (per_img_vsync),
        .per_img_href         (per_img_href),
        .per_img_gray         (per_img_y),
        .post_img_vsync       (post_img_vsync),
        .post_img_href        (post_img_href),
        .post_img_gray        (post_img_y)
    );

    //==================================================================
    // Cb、Cr 通道直接延迟同步输出（不参与均衡）
    //==================================================================
    // 延迟 Cb / Cr 同步 5 拍
        reg [7:0] cb_dly [0:4];
        reg [7:0] cr_dly [0:4];
        integer i;

        always @(posedge clk or negedge rst_n) begin
            if (!rst_n) begin
                for (i = 0; i < 5; i = i + 1) begin
                    cb_dly[i] <= 8'd0;
                    cr_dly[i] <= 8'd0;
                end
            end else begin
                cb_dly[0] <= per_img_cb;
                cr_dly[0] <= per_img_cr;
                for (i = 1; i < 5; i = i + 1) begin
                    cb_dly[i] <= cb_dly[i-1];
                    cr_dly[i] <= cr_dly[i-1];
                end
            end
        end

        assign post_img_cb = cb_dly[4];
        assign post_img_cr = cr_dly[4];

endmodule
