
// Create Date   : 2025/10/15
// Module Name   : morph_dilate
// Description   : 3x3 膨胀（Dilation）运算模块，用于二值图像形态学处理
/////////////////////////////////////////////////////////////////////////////////

module morph_dilate #(
  parameter DATA_WIDTH = 1   // 输入为二值图像 (1bit)
)(
  input                      clk,    // pixel clk
  input                      reset_p,
  input     [DATA_WIDTH-1:0] data_in,
  input                      data_in_valid,
  input                      data_in_hs,
  input                      data_in_vs,

  output reg [DATA_WIDTH-1:0] data_out,
  output reg                  data_out_valid,
  output reg                  data_out_hs,
  output reg                  data_out_vs
);

//--------------------------------------
// 三行缓存 (复用 shift_register_2taps)
//--------------------------------------
wire [DATA_WIDTH-1:0] line0_data;
wire [DATA_WIDTH-1:0] line1_data;
wire [DATA_WIDTH-1:0] line2_data;

shift_register_2taps #(
  .DATA_WIDTH(DATA_WIDTH)
) shift_register_2taps_inst (
  .clk           (clk),
  .shiftin       (data_in),
  .shiftin_valid (data_in_valid),
  .shiftout      (),
  .taps0x        (line0_data),
  .taps1x        (line1_data)
);

assign line2_data = data_in;

//--------------------------------------
// 构建 3x3 窗口
//--------------------------------------
reg [DATA_WIDTH-1:0] row0_col0, row0_col1, row0_col2;
reg [DATA_WIDTH-1:0] row1_col0, row1_col1, row1_col2;
reg [DATA_WIDTH-1:0] row2_col0, row2_col1, row2_col2;

always @(posedge clk or posedge reset_p) begin
  if(reset_p) begin
    {row0_col0, row0_col1, row0_col2,
     row1_col0, row1_col1, row1_col2,
     row2_col0, row2_col1, row2_col2} <= 0;
  end else if(data_in_valid) begin
    // shift left per pixel
    row0_col2 <= line0_data;
    row0_col1 <= row0_col2;
    row0_col0 <= row0_col1;

    row1_col2 <= line1_data;
    row1_col1 <= row1_col2;
    row1_col0 <= row1_col1;

    row2_col2 <= line2_data;
    row2_col1 <= row2_col2;
    row2_col0 <= row2_col1;
  end
end

//--------------------------------------
// 信号延时对齐
//--------------------------------------
reg data_in_valid_d1, data_in_valid_d2;
reg data_in_hs_d1, data_in_hs_d2;
reg data_in_vs_d1, data_in_vs_d2;

always @(posedge clk) begin
  data_in_valid_d1 <= data_in_valid;
  data_in_valid_d2 <= data_in_valid_d1;

  data_in_hs_d1 <= data_in_hs;
  data_in_hs_d2 <= data_in_hs_d1;

  data_in_vs_d1 <= data_in_vs;
  data_in_vs_d2 <= data_in_vs_d1;
end

//--------------------------------------
// 膨胀操作：3x3 任意为1则输出1
//--------------------------------------
always @(posedge clk or posedge reset_p) begin
  if(reset_p)
    data_out <= 0;
  else if(data_in_valid_d2)
    data_out <= row0_col0 | row0_col1 | row0_col2 |
                row1_col0 | row1_col1 | row1_col2 |
                row2_col0 | row2_col1 | row2_col2;
end

always @(posedge clk) begin
  data_out_valid <= data_in_valid_d2;
  data_out_hs    <= data_in_hs_d2;
  data_out_vs    <= data_in_vs_d2;
end

endmodule
