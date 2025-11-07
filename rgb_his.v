`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Top-Level: RGB → YCbCr → Y直方图均衡 → YCbCr → RGB
// 输出带同步有效信号 valid
//////////////////////////////////////////////////////////////////////////////////
module rgb_his #
(
    parameter IMG_TOTAL = 480000
)
(
    input  wire        clk,
    input  wire        rst_n,

    // 输入RGB图像
    input               rgb_valid,
    input  wire        per_rgb_vsync,
    input  wire        per_rgb_href,
    input  wire [7:0]  per_rgb_r,
    input  wire [7:0]  per_rgb_g,
    input  wire [7:0]  per_rgb_b,

    // 输出RGB图像
    output wire        post_rgb_vsync,
    output wire        post_rgb_href,
    output wire [7:0]  post_rgb_r,
    output wire [7:0]  post_rgb_g,
    output wire [7:0]  post_rgb_b,
    output wire        post_rgb_valid
);

    //========================================================
    // 1. RGB → YCbCr
    //========================================================
    wire [7:0] ycbcr_y, ycbcr_cb, ycbcr_cr;
    wire       ycbcr_valid, ycbcr_hs, ycbcr_vs;

    rgb2ycber u_rgb2ycbcr (
        .clk        (clk),
        .reset_p    (~rst_n),
        .rgb_valid  (per_rgb_href),
        .rgb_hs     (per_rgb_href),
        .rgb_vs     (per_rgb_vsync),
        .red_8b_i   (per_rgb_r),
        .green_8b_i (per_rgb_g),
        .blue_8b_i  (per_rgb_b),
        .gray_8b_o  (ycbcr_y),
        .cb_8b_o    (ycbcr_cb),
        .cr_8b_o    (ycbcr_cr),
        .gray_valid (ycbcr_valid),
        .gray_hs    (ycbcr_hs),
        .gray_vs    (ycbcr_vs)
    );

    //========================================================
    // 2. Y通道直方图均衡
    //========================================================
    wire        hist_vsync, hist_href, hist_valid;
    wire [7:0]  hist_y;
    
    VIP_HistEQ_Top_2 #(
        .IMG_TOTAL(IMG_TOTAL)
    ) u_hist_eq (
        .clk           (clk),
        .rst_n         (rst_n),
        .per_img_vsync (ycbcr_vs),
        .per_img_href  (ycbcr_hs),
        .per_img_y     (ycbcr_y),
        .per_img_cb    (ycbcr_cb),
        .per_img_cr    (ycbcr_cr),
        .post_img_vsync(hist_vsync),
        .post_img_href (hist_href),
        .post_img_y    (hist_y),
        .post_img_cb   (),   // 不用
        .post_img_cr   ()    // 不用
    );

    //========================================================
    // 3. Cb/Cr 延迟同步到直方图输出
    //========================================================
    reg [7:0] cb_dly [0:4];
    reg [7:0] cr_dly [0:4];
    reg       valid_dly [0:4];
    integer i;

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            for(i=0;i<5;i=i+1) begin
                cb_dly[i] <= 8'd0;
                cr_dly[i] <= 8'd0;
                valid_dly[i] <= 1'b0;
            end
        end else begin
            cb_dly[0] <= ycbcr_cb;
            cr_dly[0] <= ycbcr_cr;
            valid_dly[0] <= hist_href;  // valid 信号同步
            for(i=1;i<5;i=i+1) begin
                cb_dly[i] <= cb_dly[i-1];
                cr_dly[i] <= cr_dly[i-1];
                valid_dly[i] <= valid_dly[i-1];
            end
        end
    end

    //========================================================
    // 4. YCbCr → RGB
    //========================================================
    ycbcr_to_rgb u_ycbcr2rgb (
        .clk        (clk),
        .reset_p    (~rst_n),
        .ycbcr_valid(valid_dly[4]),
        .ycbcr_hs   (hist_href),
        .ycbcr_vs   (hist_vsync),
        .y_8b_i     (hist_y),
        .cb_8b_i    (cb_dly[4]),
        .cr_8b_i    (cr_dly[4]),
        .red_8b_o   (post_rgb_r),
        .green_8b_o (post_rgb_g),
        .blue_8b_o  (post_rgb_b),
        .rgb_valid  (),
        .rgb_hs     (post_rgb_href),
        .rgb_vs     (post_rgb_vsync)
    );

    assign post_rgb_valid = valid_dly[4];

endmodule
