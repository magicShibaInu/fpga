`timescale 1ns / 1ps
module His_Top#
(parameter IMG_TOTAL = 480000)
(
    input  wire        clk,
    input  wire        rst_n,

    // 输入图像接口
    input  wire        per_img_vsync,
    input  wire        per_img_href,
    input  wire [7:0]  per_img_gray,

    // 输出均衡化图像接口
    output wire        post_img_vsync,
    output wire        post_img_href,
    output wire [7:0]  post_img_gray
);

    //----------------------------------------------------------------------
    // 信号声明
    //----------------------------------------------------------------------
    wire        histEQ_start_flag;
    wire [7:0]  pixel_level;
    wire [19:0] pixel_level_acc_num;
    wire        pixel_level_valid;

    //----------------------------------------------------------------------
    // 直方图统计模块
    //----------------------------------------------------------------------
    his_stat u_his_stat (
        .clk                  (clk),
        .rst_n                (rst_n),
        .img_vsync            (per_img_vsync),
        .img_href             (per_img_href),
        .img_gray             (per_img_gray),
        .pixel_level          (pixel_level),
        .pixel_level_acc_num  (pixel_level_acc_num),
        .pixel_level_valid    (pixel_level_valid)
    );

    //----------------------------------------------------------------------
    // 直方图均衡化映射模块
    //----------------------------------------------------------------------
    hisproc #(
        .IMG_TOTAL(IMG_TOTAL))
        u_hisproc (
        .clk                  (clk),
        .rst_n                (rst_n),
        .pixel_level          (pixel_level),
        .pixel_level_acc_num  (pixel_level_acc_num),
        .pixel_level_valid    (pixel_level_valid),
        .histEQ_start_flag    (histEQ_start_flag),
        .per_img_vsync        (per_img_vsync),
        .per_img_href         (per_img_href),
        .per_img_gray         (per_img_gray),
        .post_img_vsync       (post_img_vsync),
        .post_img_href        (post_img_href),
        .post_img_gray        (post_img_gray)
    );

endmodule
