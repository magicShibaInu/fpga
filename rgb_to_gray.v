`timescale 1ns / 1ps

module vs_delta#(
    parameter IMG_WIDTH  = 15'd800,
    parameter IMG_HEIGHT = 15'd600,
    parameter IMG_TOTAL  = 32'd480000,
    parameter THRESH     = 8'd15,
    parameter BOX_W      = 3
)(
    input               clk,
    input               rst_n,
    input               per_frame_vsync,
    input               per_frame_href,
    input               per_frame_clken,
    input      [23:0]   per_img_24bit,

    output              post_frame_vsync,
    output              post_frame_href,
    output              post_frame_clken,
    output     [23:0]   post_frame_24bit
);

    //------------------------------------------------------------
    // 同步信号延迟，用于对齐数据
    //------------------------------------------------------------
    reg vs_d, href_d, clken_d;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            vs_d <= 0; href_d <= 0; clken_d <= 0;
        end else begin
            vs_d <= per_frame_vsync;
            href_d <= per_frame_href;
            clken_d <= per_frame_clken;
        end
    end

    wire vsync_posedge = per_frame_vsync & ~vs_d;

    //------------------------------------------------------------
    // 单口RAM（读优先）
    //------------------------------------------------------------
    reg [18:0] addr;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n)
            addr <= 0;
        else if(vsync_posedge)
            addr <= 0;
        else if(per_frame_clken)
            addr <= addr + 1;
    end

    wire [23:0] douta;
    vs_dly u_vs_dly(
        .clka(clk),
        .ena(per_frame_clken),
        .wea(per_frame_clken),
        .addra(addr),
        .dina(per_img_24bit),
        .douta(douta)
    );

    //------------------------------------------------------------
    // 延迟一拍对齐 douta
    //------------------------------------------------------------
    reg [23:0] douta_r;
    always @(posedge clk) douta_r <= douta;

    //------------------------------------------------------------
    // 坐标计数器
    //------------------------------------------------------------
    reg [14:0] x_cnt, y_cnt;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            x_cnt <= 0; y_cnt <= 0;
        end else if(per_frame_clken) begin
            if(x_cnt == IMG_WIDTH - 1) begin
                x_cnt <= 0;
                if(y_cnt == IMG_HEIGHT - 1)
                    y_cnt <= 0;
                else
                    y_cnt <= y_cnt + 1;
            end else
                x_cnt <= x_cnt + 1;
        end
    end

    //------------------------------------------------------------
    // 灰度转换（取高位避免除法）
    //------------------------------------------------------------
    wire [15:0] g1 = per_img_24bit[23:16]*30 + per_img_24bit[15:8]*59 + per_img_24bit[7:0]*11;
    wire [15:0] g2 = douta_r[23:16]*30 + douta_r[15:8]*59 + douta_r[7:0]*11;
    wire [7:0] gray_now = g1[15:8];
    wire [7:0] gray_old = g2[15:8];

    //------------------------------------------------------------
    // 帧差计算
    //------------------------------------------------------------
    wire [7:0] diff = (gray_now > gray_old) ? (gray_now - gray_old) : (gray_old - gray_now);
    wire motion_pixel = (diff > THRESH);

    //------------------------------------------------------------
    // 记录运动区域边界
    //------------------------------------------------------------
    reg [14:0] min_x, max_x, min_y, max_y;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            min_x <= IMG_WIDTH; max_x <= 0;
            min_y <= IMG_HEIGHT; max_y <= 0;
        end else if(vsync_posedge) begin
            min_x <= IMG_WIDTH; max_x <= 0;
            min_y <= IMG_HEIGHT; max_y <= 0;
        end else if(per_frame_clken && motion_pixel) begin
            if(x_cnt < min_x) min_x <= x_cnt;
            if(x_cnt > max_x) max_x <= x_cnt;
            if(y_cnt < min_y) min_y <= y_cnt;
            if(y_cnt > max_y) max_y <= y_cnt;
        end
    end

    //------------------------------------------------------------
    // 延迟一帧显示矩形
    //------------------------------------------------------------
    reg [14:0] min_x_d, max_x_d, min_y_d, max_y_d;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            min_x_d <= IMG_WIDTH; max_x_d <= 0;
            min_y_d <= IMG_HEIGHT; max_y_d <= 0;
        end else if(vsync_posedge) begin
            min_x_d <= min_x;
            max_x_d <= max_x;
            min_y_d <= min_y;
            max_y_d <= max_y;
        end
    end

    //------------------------------------------------------------
    // 判断是否绘制红框
    //------------------------------------------------------------
    wire draw_box = 
        ( (x_cnt >= min_x_d && x_cnt < min_x_d + BOX_W) ||
          (x_cnt <= max_x_d && x_cnt > max_x_d - BOX_W) ||
          (y_cnt >= min_y_d && y_cnt < min_y_d + BOX_W) ||
          (y_cnt <= max_y_d && y_cnt > max_y_d - BOX_W) ) &&
        (max_x_d > min_x_d) && (max_y_d > min_y_d);

    //------------------------------------------------------------
    // 输出图像
    //------------------------------------------------------------
    assign post_frame_24bit = draw_box ? 24'hFF0000 : per_img_24bit;
    assign post_frame_vsync = per_frame_vsync;
    assign post_frame_href  = per_frame_href;
    assign post_frame_clken = per_frame_clken;

endmodule
