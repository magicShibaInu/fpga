/////////////////////////////////////////////////////////////////////////////////
// Company       : 武汉芯路恒科技有限公司
//                 http://xiaomeige.taobao.com
// Web           : http://www.corecourse.cn
// 
// Create Date   : 2025/10/21
// Module Name   : disp_driver_dynamic
// Description   : 动态分辨率显示驱动模块（兼容原版 disp_driver）
// 
// 功能:
//   支持两种分辨率动态切换：
//     mode_sel = 0 → 800×600 @40MHz
//     mode_sel = 1 → 1280×720 @74.25MHz
//
// 说明:
//   保留原始芯路恒结构，内部根据 mode_sel 选择时序参数
/////////////////////////////////////////////////////////////////////////////////

module disp_driver #(
  parameter AHEAD_CLK_CNT = 0 //ahead N clock generate DataReq
)(
  input        ClkDisp,    // VGA/HDMI显示像素时钟
  input        Rst_n,      // 复位信号（低有效）
  input        mode_sel,   // 0=800×600，1=1280×720

  input  [23:0] Data,      // 输入像素数据
  output reg    DataReq,   // 像素数据请求信号

  output [11:0] H_Addr,    // 当前像素点横坐标
  output [11:0] V_Addr,    // 当前像素点纵坐标
  output reg    Disp_Sof,  // 一帧起始信号

  output reg    Disp_HS,   // 行同步信号
  output reg    Disp_VS,   // 场同步信号
  output reg [7:0] Disp_Red,    // 红色像素数据
  output reg [7:0] Disp_Green,  // 绿色像素数据
  output reg [7:0] Disp_Blue,   // 蓝色像素数据
  output reg    Disp_DE,        // 数据使能信号
  output        Disp_PCLK       // VGA/HDMI显示像素时钟（反相输出）
);

  //==============================
  // VGA 模式 (mode_sel = 0) 800×600
  //==============================
  localparam H_TOTAL_800   = 12'd1056;
  localparam H_SYNC_800    = 12'd128;
  localparam H_BACK_800    = 12'd88;
  localparam H_FRONT_800   = 12'd40;
  localparam V_TOTAL_800   = 12'd628;
  localparam V_SYNC_800    = 12'd4;
  localparam V_BACK_800    = 12'd23;
  localparam V_FRONT_800   = 12'd1;

  //==============================
  // 720P 模式 (mode_sel = 1) 1280×720
  //==============================
  localparam H_TOTAL_1280  = 12'd1650;
  localparam H_SYNC_1280   = 12'd40;
  localparam H_BACK_1280   = 12'd220;
  localparam H_FRONT_1280  = 12'd110;
  localparam V_TOTAL_1280  = 12'd750;
  localparam V_SYNC_1280   = 12'd5;
  localparam V_BACK_1280   = 12'd20;
  localparam V_FRONT_1280  = 12'd5;

  //==============================
  // 时序寄存器，根据 mode_sel 动态选择
  //==============================
  reg [11:0] H_Total_Time, H_Sync_Time, H_Back_Porch, H_Front_Porch;
  reg [11:0] V_Total_Time, V_Sync_Time, V_Back_Porch, V_Front_Porch;

  always @(*) begin
    if (mode_sel == 1'b0) begin
      H_Total_Time = H_TOTAL_800;
      H_Sync_Time  = H_SYNC_800;
      H_Back_Porch = H_BACK_800;
      H_Front_Porch= H_FRONT_800;

      V_Total_Time = V_TOTAL_800;
      V_Sync_Time  = V_SYNC_800;
      V_Back_Porch = V_BACK_800;
      V_Front_Porch= V_FRONT_800;
    end else begin
      H_Total_Time = H_TOTAL_1280;
      H_Sync_Time  = H_SYNC_1280;
      H_Back_Porch = H_BACK_1280;
      H_Front_Porch= H_FRONT_1280;

      V_Total_Time = V_TOTAL_1280;
      V_Sync_Time  = V_SYNC_1280;
      V_Back_Porch = V_BACK_1280;
      V_Front_Porch= V_FRONT_1280;
    end
  end

  //==============================
  // 内部信号定义
  //==============================
  reg [11:0] hcount_r;
  reg [11:0] vcount_r;
  wire       hcount_ov;
  wire       vcount_ov;
  reg        Disp_DE_pre;
  reg        Disp_VS_dly1;

  assign Disp_PCLK = ~ClkDisp;  // VGA/HDMI 均反相输出像素时钟

  wire [11:0] hdat_begin = H_Sync_Time + H_Back_Porch - 1'b1;
  wire [11:0] hdat_end   = H_Total_Time - H_Front_Porch - 1'b1;
  wire [11:0] vdat_begin = V_Sync_Time + V_Back_Porch - 1'b1;
  wire [11:0] vdat_end   = V_Total_Time - V_Front_Porch - 1'b1;

  assign H_Addr = Disp_DE ? (hcount_r - hdat_begin) : 12'd0;
  assign V_Addr = Disp_DE ? (vcount_r - vdat_begin) : 12'd0;

  //==============================
  // 行扫描
  //==============================
  assign hcount_ov = (hcount_r >= H_Total_Time - 1);

  always @(posedge ClkDisp or negedge Rst_n)
    if(!Rst_n)
      hcount_r <= 0;
    else if(hcount_ov)
      hcount_r <= 0;
    else
      hcount_r <= hcount_r + 1'b1;

  //==============================
  // 场扫描
  //==============================
  assign vcount_ov = (vcount_r >= V_Total_Time - 1);

  always @(posedge ClkDisp or negedge Rst_n)
    if(!Rst_n)
      vcount_r <= 0;
    else if(hcount_ov) begin
      if(vcount_ov)
        vcount_r <= 0;
      else
        vcount_r <= vcount_r + 1'd1;
    end

  //==============================
  // DE & DataReq
  //==============================
  always @(posedge ClkDisp)
    Disp_DE_pre <= ((hcount_r >= hdat_begin)&&(hcount_r < hdat_end)) &&
                   ((vcount_r >= vdat_begin)&&(vcount_r < vdat_end));

  always @(posedge ClkDisp)
    DataReq <= ((hcount_r >= hdat_begin - AHEAD_CLK_CNT)&&(hcount_r < hdat_end - AHEAD_CLK_CNT)) &&
               ((vcount_r >= vdat_begin)&&(vcount_r < vdat_end));

  //==============================
  // 同步信号输出
  //==============================
  always @(posedge ClkDisp) begin
    Disp_HS <= (hcount_r > H_Sync_Time - 1);
    Disp_VS <= (vcount_r > V_Sync_Time - 1);
    {Disp_Red, Disp_Green, Disp_Blue} <= (Disp_DE_pre) ? Data : 24'd0;
    Disp_DE <= Disp_DE_pre;
  end

  //==============================
  // 一帧起始信号
  //==============================
  always @(posedge ClkDisp) begin
    Disp_VS_dly1 <= Disp_VS;
    Disp_Sof <= (!Disp_VS_dly1 && Disp_VS);
  end

endmodule
