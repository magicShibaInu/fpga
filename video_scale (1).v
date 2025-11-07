`timescale 1ns / 1ps

module video_scale_near_v1
(
    input               vout_clk,
    input               vin_clk,
    input               rst_n,
    input               frame_sync_n,       ///< 输入视频帧同步复位，低有效
    input   [23:0]      vin_dat,            ///< 输入视频数据
    input               vin_valid,          ///< 输入视频数据有效
    output  reg [23:0]  vout_dat,           ///< 输出视频数据
    output  reg         vout_valid,         ///< 输出视频数据有效

    input   [15:0]      vin_xres,           ///< 输入视频水平分辨率
    input   [15:0]      vin_yres,           ///< 输入视频垂直分辨率
    input   [15:0]      vout_xres,          ///< 输出视频水平分辨率
    input   [15:0]      vout_yres,          ///< 输出视频垂直分辨率
    output              vin_ready,          ///< 输入准备好
    input               vout_ready          ///< 输出准备好
);

    parameter   MAX_SCAN_INTERVAL    = 2;
    parameter   MAX_VIN_INTERVAL     = 2;

    reg [31:0]  scaler_height = 0;           ///< 垂直缩放系数，[31:16]高16位是整数，低16位是小数
    reg [31:0]  scaler_width  = 0;           ///< 水平缩放系数，[31:16]高16位是整数，低16位是小数
    reg [15:0]  scan_cnt_sx;                 ///< 水平扫描计数器
    reg [15:0]  scan_cnt_sy;                 ///< 垂直扫描计数器
    reg         scan_cnt_state;              ///< 水平扫描状态，1 正在扫描，0 结束扫描
    reg [31:0]  scan_sy;                     ///< 垂直扫描计数器，定浮点
    reg [15:0]  scan_sy_int;                 ///< scan_sy 的整数部分
    reg [31:0]  scan_sx;                     ///< 水平扫描计数器，定浮点
    reg [15:0]  scan_sx_int;                 ///< scan_sx 的整数部分
    reg [15:0]  scan_sx_int_dx;              ///< scan_sx_int 延时对齐
    reg [7:0]   scan_sx_int_dly;             ///< scan_sx_int 延时对齐中间寄存器
    reg         scan_cnt_state_dx;           ///< scan_cnt_state 延时对齐
    reg [7:0]   scan_cnt_state_dly;          ///< scan_cnt_state 延时对齐中间寄存器
    reg [23:0]  fifo_rd_dat;                 ///< FIFO 读数据
    reg         fifo_rd_en;                  ///< FIFO 读使能
    wire        fifo_rd_empty;               ///< FIFO 空状态
    wire        fifo_rd_valid;               ///< FIFO 读数据有效
    wire        fifo_full;                   ///< FIFO 满
    wire        fifo_wr_en;                  ///< FIFO 写使能

    reg [15:0]  line_buf_wr_addr;            ///< LINER_BUF 写地址
    reg [15:0]  line_buf_rd_addr;            ///< LINER_BUF 读地址
    reg         line_buf_wen;                ///< LINER_BUF 写使能
    reg [23:0]  line_buf_wr_dat;             ///< LINER_BUF 写数据
    reg [23:0]  line_buf_rd_dat;             ///< LINER_BUF 读数据

    reg [7:0]   line_buf_rd_interval = 0;    ///< LINER_BUF 读扫描间隙
    reg [7:0]   line_buf_wr_interval = 0;    ///< LINER_BUF 写扫描间隙
    reg [15:0]  vin_sx = 0;                  ///< 视频输入水平计数
    reg [15:0]  vin_sy = 0;                  ///< 视频输入垂直计数

    assign vin_ready = ~fifo_full;

    // 缩放系数计算
    always @(posedge frame_sync_n) begin
        scaler_height = ((vin_yres << 16)/vout_yres) + 1;
        scaler_width  = ((vin_xres << 16)/vout_xres) + 1;
    end

    // FIFO 控制
    assign fifo_wr_en   = vin_valid & ~fifo_full;
    assign fifo_rd_en   = (line_buf_wr_interval == 0) & (~fifo_rd_empty);    
    assign fifo_rd_valid= fifo_rd_en & (~fifo_rd_empty);

    fifo_generator_1 vin_fifo_u1 (
        .wr_clk     (vin_clk),
        .rd_clk     (vout_clk),
        .rst        (~frame_sync_n | ~rst_n),
        .din        (vin_dat),
        .wr_en      (fifo_wr_en),
        .rd_en      (fifo_rd_en),
        .dout       (fifo_rd_dat),
        .full       (fifo_full),
        .empty      (fifo_rd_empty),
        .wr_rst_busy(),
        .rd_rst_busy()
    );

    // 写扫描间隙 line_buf_wr_interval
    always @(posedge vout_clk) begin
        if(frame_sync_n == 0 || rst_n == 0)
            line_buf_wr_interval <= 0;
        else if(line_buf_wr_interval == 0 && fifo_rd_valid == 1 && vin_sx >= vin_xres-1)
            line_buf_wr_interval <= MAX_VIN_INTERVAL;
        else if(line_buf_wr_interval != 0 && line_buf_rd_interval != 0 && vin_sy < scan_sy_int)
            line_buf_wr_interval <= line_buf_wr_interval - 1;
        else if(line_buf_wr_interval < MAX_VIN_INTERVAL && line_buf_wr_interval != 0)
            line_buf_wr_interval <= line_buf_wr_interval - 1;
    end

    // 读扫描间隙 line_buf_rd_interval
    always @(posedge vout_clk) begin
        if(frame_sync_n == 0 || rst_n == 0)
            line_buf_rd_interval <= 0;
        else if(vout_ready && line_buf_wr_interval != 0 && scan_cnt_sx >= vout_xres-1 && scan_cnt_sy < vout_yres)
            line_buf_rd_interval <= MAX_SCAN_INTERVAL;
        else if(vout_ready && line_buf_rd_interval != 0 && vin_sy >= scan_sy_int)
            line_buf_rd_interval <= line_buf_rd_interval - 1;
        else if(vout_ready && line_buf_rd_interval < MAX_SCAN_INTERVAL && line_buf_rd_interval != 0)
            line_buf_rd_interval <= line_buf_rd_interval - 1;
    end

    // 写扫描地址计数
    always @(posedge vout_clk) begin
        if(frame_sync_n == 0 || rst_n == 0)
            vin_sx <= 0;
        else if(fifo_rd_valid == 1) begin
            if(vin_sx < vin_xres-1)
                vin_sx <= vin_sx + 1;
            else
                vin_sx <= 0;
        end
    end

    always @(posedge vout_clk) begin
        if(frame_sync_n == 0 || rst_n == 0)
            vin_sy <= 0;
        else if(line_buf_wr_interval == 1)
            vin_sy <= vin_sy + 1;
    end

    // 扫描地址计数器
    assign scan_sy_int = scan_sy[31:16];
    assign scan_sx_int = scan_sx[31:16];

    always @(posedge vout_clk) begin
        if(frame_sync_n == 0 || rst_n == 0) begin
            scan_cnt_state <= 0;
            scan_cnt_sx    <= 0;
            scan_cnt_sy    <= 0;
            scan_sx        <= 0;
            scan_sy        <= 0;
        end else if(vout_ready) begin
            if(line_buf_rd_interval == 0 && (scan_sx_int + scaler_width[31:15] + 2 < vin_sx || line_buf_wr_interval != 0) &&
               scan_cnt_sy < vout_yres && (scan_sy_int <= vin_sy || vin_sy >= vin_yres-1)) begin
                scan_cnt_state <= 1;
                if(scan_cnt_sx < vout_xres-1) begin
                    scan_cnt_sx <= scan_cnt_sx + 1;
                    scan_sx     <= scan_sx + scaler_width;
                end else begin
                    scan_cnt_sx <= 0;
                    scan_sx     <= 0;
                    scan_cnt_sy <= scan_cnt_sy + 1;
                    scan_sy     <= scan_sy + scaler_height;
                end
            end else
                scan_cnt_state <= 0;
        end
    end

    // 延迟对齐
    localparam SCAN_DLY = 0;
    assign scan_cnt_state_dx = scan_cnt_state_dly[SCAN_DLY];
    assign scan_sx_int_dx    = scan_sx_int_dly[SCAN_DLY+1];

    always @(posedge vout_clk) begin
        if(frame_sync_n == 0 || rst_n == 0) begin
            scan_sx_int_dly <= 0;
            scan_cnt_state_dly <= 0;
        end else if(vout_ready) begin
            scan_sx_int_dly <= {scan_sx_int_dly[6:0], scan_sx_int};
            scan_cnt_state_dly <= {scan_cnt_state_dly[6:0], scan_cnt_state};
        end
    end

    // 输出
    always @(posedge vout_clk) begin
        if(frame_sync_n == 0 || rst_n == 0) begin
            vout_valid <= 0;
            vout_dat   <= 0;
        end else if(vout_ready && scan_cnt_state_dx == 1) begin
            vout_valid <= 1;
            vout_dat   <= line_buf_rd_dat;
        end else if(vout_ready)
            vout_valid <= 0;
    end

    // LINER_BUF RAM
    reg [23:0] line_buf_ram[0:2048-1];

    always @(posedge vout_clk) begin
        if(line_buf_wen)
            line_buf_ram[line_buf_wr_addr] <= line_buf_wr_dat;
        if(vout_ready)
            line_buf_rd_dat <= line_buf_ram[line_buf_rd_addr];
    end

    always @(posedge vout_clk) begin
        line_buf_wen    <= fifo_rd_valid;
        line_buf_wr_addr<= vin_sx;
        line_buf_wr_dat <= fifo_rd_dat;
        if(vout_ready)
            line_buf_rd_addr <= scan_sx_int;
    end

endmodule
