`timescale 1ns / 1ps
/////////////////////////////////////////////////////////////////////////////////
// 模块名称: ycbcr_to_rgb
// 功能描述: 将 YCbCr 转换回 RGB
// 特点: 移位加法实现近似乘法，无乘法器，带饱和保护
// 对应公式(整数近似):
// R = Y + 1.402  * (Cr - 128)
// G = Y - 0.344  * (Cb - 128) - 0.714 * (Cr - 128)
// B = Y + 1.772  * (Cb - 128)
/////////////////////////////////////////////////////////////////////////////////

module ycbcr_to_rgb (
  input           clk,
  input           reset_p,
  input           ycbcr_valid,
  input           ycbcr_hs,
  input           ycbcr_vs,
  input     [7:0] y_8b_i,
  input     [7:0] cb_8b_i,
  input     [7:0] cr_8b_i,

  output reg [7:0] red_8b_o,
  output reg [7:0] green_8b_o,
  output reg [7:0] blue_8b_o,
  output reg       rgb_valid,
  output reg       rgb_hs,
  output reg       rgb_vs
);

    //=========================
    // 1. 转换准备：Cb、Cr中心化
    //=========================
    wire signed [8:0] cb_off = $signed({1'b0, cb_8b_i}) - 9'sd128;
    wire signed [8:0] cr_off = $signed({1'b0, cr_8b_i}) - 9'sd128;
    wire [7:0] y_val = y_8b_i;

    //=========================
    // 2. 移位加法近似乘法
    //=========================
    // R = Y + 1.402*(Cr-128)  ≈ Y + (Cr*359)>>8
    // G = Y - 0.344*(Cb-128) - 0.714*(Cr-128) ≈ Y - (Cb*88 + Cr*183)>>8
    // B = Y + 1.772*(Cb-128)  ≈ Y + (Cb*454)>>8

    wire signed [15:0] cr_x359;
    wire signed [15:0] cb_x88;
    wire signed [15:0] cr_x183;
    wire signed [15:0] cb_x454;

    // 近似移位加法
    assign cr_x359 = (cr_off<<<8) + (cr_off<<<6) + (cr_off<<<5) + (cr_off<<<3) + (cr_off<<<1) + cr_off;  // ×359 ≈ 256+64+32+8+2+1
    assign cb_x88  = (cb_off<<<6) + (cb_off<<<4) + (cb_off<<<3);  // ×88 ≈ 64+16+8
    assign cr_x183 = (cr_off<<<7) + (cr_off<<<5) + (cr_off<<<4) + (cr_off<<<2) + (cr_off<<<1) + cr_off; // ×183 ≈ 128+32+16+4+2+1
    assign cb_x454 = (cb_off<<<8) + (cb_off<<<7) + (cb_off<<<6) + (cb_off<<<3) + (cb_off<<<1) + cb_off; // ×454 ≈ 256+128+64+8+2+1

    //=========================
    // 3. 求和寄存
    //=========================
    reg signed [16:0] red_tmp, green_tmp, blue_tmp;

    always @(posedge clk or posedge reset_p) begin
      if (reset_p) begin
        red_tmp   <= 17'sd0;
        green_tmp <= 17'sd0;
        blue_tmp  <= 17'sd0;
      end else if (ycbcr_valid) begin
        red_tmp   <= $signed({1'b0, y_val, 8'd0}) + cr_x359;              // R = Y<<8 + Cr*359
        green_tmp <= $signed({1'b0, y_val, 8'd0}) - (cb_x88 + cr_x183);   // G = Y<<8 - (Cb*88 + Cr*183)
        blue_tmp  <= $signed({1'b0, y_val, 8'd0}) + cb_x454;              // B = Y<<8 + Cb*454
      end else begin
        red_tmp   <= 17'sd0;
        green_tmp <= 17'sd0;
        blue_tmp  <= 17'sd0;
      end
    end

    //=========================
    // 4. 输出寄存 + 饱和保护
    //=========================
    wire signed [8:0] red_9b   = red_tmp[16:8];
    wire signed [8:0] green_9b = green_tmp[16:8];
    wire signed [8:0] blue_9b  = blue_tmp[16:8];

    wire [7:0] red_sat   = (red_9b < 0)   ? 8'd0   : (red_9b > 9'd255) ? 8'd255 : red_9b[7:0];
    wire [7:0] green_sat = (green_9b < 0) ? 8'd0   : (green_9b > 9'd255) ? 8'd255 : green_9b[7:0];
    wire [7:0] blue_sat  = (blue_9b < 0)  ? 8'd0   : (blue_9b > 9'd255) ? 8'd255 : blue_9b[7:0];

    always @(posedge clk or posedge reset_p) begin
      if (reset_p) begin
        red_8b_o   <= 8'd0;
        green_8b_o <= 8'd0;
        blue_8b_o  <= 8'd0;
        rgb_valid  <= 1'b0;
        rgb_hs     <= 1'b0;
        rgb_vs     <= 1'b0;
      end else begin
        red_8b_o   <= red_sat;
        green_8b_o <= green_sat;
        blue_8b_o  <= blue_sat;
        rgb_valid  <= ycbcr_valid;
        rgb_hs     <= ycbcr_hs;
        rgb_vs     <= ycbcr_vs;
      end
    end

endmodule
