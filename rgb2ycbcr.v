`timescale 1ns / 1ps
/////////////////////////////////////////////////////////////////////////////////



module rgb2ycber (
  input           clk,         // 时钟
  input           reset_p,     // 高电平复位
  input           rgb_valid,   // RGB输入有效
  input           rgb_hs,      // 行同步
  input           rgb_vs,      // 场同步
  input     [7:0] red_8b_i,    // R通道
  input     [7:0] green_8b_i,  // G通道
  input     [7:0] blue_8b_i,   // B通道

  output    [7:0] gray_8b_o,   // 灰度输出
  output    [7:0] cr_8b_o,
  output    [7:0] cb_8b_o,
  output reg      gray_valid,  // 输出有效
  output reg      gray_hs,     // 行同步
  output reg      gray_vs      // 场同步
);

    //=========================
    // 1. RGB加权组合
    //=========================
    wire [15:0] red_x77;
    wire [15:0] green_x150;
    wire [15:0] blue_x29;
    reg  [15:0] sum;
    reg  [15:0] sum1;
    reg  [15:0] sum2;        // 当前像素的加权和
    reg  [7:0]  gray_d;     // 输出寄存
    reg   [7:0] cr_d;
    reg   [7:0] cb_d;

    // 移位加法替代乘法
    assign red_x77    = (red_8b_i  << 6) + (red_8b_i  << 3) + (red_8b_i  << 2) + red_8b_i;
    assign green_x150 = (green_8b_i<< 7) + (green_8b_i<< 4) + (green_8b_i<< 2) + (green_8b_i<<1);
    assign blue_x29   = (blue_8b_i << 4) + (blue_8b_i << 3) + (blue_8b_i << 2) + blue_8b_i;
    assign red_x43 = (red_8b_i << 5) + (red_8b_i << 3) + (red_8b_i << 1) + red_8b_i; // ×43
    assign green_x85 = (green_8b_i << 6) + (green_8b_i << 4) + (green_8b_i << 2) + green_8b_i; // ×85
    assign blue_x128 = (blue_8b_i << 7); // ×128
    assign red_x128 = (red_8b_i << 7); // ×128
    assign green_x107 = (green_8b_i << 6) + (green_8b_i << 5) + (green_8b_i << 3) + (green_8b_i << 1) + green_8b_i; // ×107
    assign blue_x21 = (blue_8b_i << 4) + (blue_8b_i << 2) + blue_8b_i; // ×21

    
    //=========================
    // 2. 求和并寄存（第1拍）
    //=========================
    always@(posedge clk or posedge reset_p) begin
      if(reset_p)begin
        sum <= 16'd0;
        sum1 <= 16'd0;
        sum2 <= 16'd0;
      end
      else if(rgb_valid) begin
        sum <= red_x77 + green_x150 + blue_x29;
        sum1 <= -red_x43-green_x85+blue_x128;
        sum2 <= red_x128-green_x107-blue_x21;
      end
      else begin
        sum <= 16'd0;
        sum1 <= 16'd0;
        sum2 <= 16'd0;
      end
    end

    //=========================
    // 3. 输出灰度 + 对齐控制信号（第2拍）
    //=========================
    reg rgb_valid_d1, rgb_hs_d1, rgb_vs_d1;
    always@(posedge clk or posedge reset_p) begin
      if(reset_p) begin
        rgb_valid_d1 <= 1'b0;
        rgb_hs_d1    <= 1'b0;
        rgb_vs_d1    <= 1'b0;
        gray_d       <= 8'd0;
        cr_d         <= 8'd0;
        cb_d         <= 8'd0;
      end else begin
        rgb_valid_d1 <= rgb_valid;
        rgb_hs_d1    <= rgb_hs;
        rgb_vs_d1    <= rgb_vs;
        gray_d       <= sum[15:8];   // 灰度值输出寄存
        cr_d         <= sum1[15:8];
        cb_d         <= sum2[15:8];
      end
    end

    //=========================
    // 4. 最终输出
    //=========================
    assign gray_8b_o = gray_d;
    assign cb_8b_o   =cb_d +8'd128;
    assign cr_8b_o   =cr_d +8'd128;
    always@(posedge clk) begin
      gray_valid <= rgb_valid_d1;
      gray_hs    <= rgb_hs_d1;
      gray_vs    <= rgb_vs_d1;
    end

endmodule
