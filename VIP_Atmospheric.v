`timescale 1ns/1ns
module VIP_Atmospheric_Light #(
    parameter [9:0] IMG_HDISP = 10'd800,
    parameter [9:0] IMG_VDISP = 10'd600
)
(
    //global clock
    input          clk,
    input          rst_n,

    input          per_frame_vsync,
    input          per_frame_href,
    input          per_frame_clken,
    input  [7:0]   per_img_Dark,

    input  [7:0]   per_img_red,
    input  [7:0]   per_img_green,
    input  [7:0]   per_img_blue,

    output reg [7:0]   atmospheric_light,   //大气光强度
    output reg [9:0]   atmospheric_pos_x,   //大气光强度对应位置横坐标
    output reg [9:0]   atmospheric_pos_y    //大气光强度对应位置纵坐标
);

reg         per_frame_vsync_r;
reg         per_frame_href_r;
reg         per_frame_clken_r;

always@(posedge clk or negedge rst_n)
begin
    if(!rst_n)
        begin
            per_frame_vsync_r <= 1'b0;
            per_frame_href_r <= 1'b0;
            per_frame_clken_r <= 1'b0;
        end
    else
        begin
            per_frame_vsync_r <= per_frame_vsync;
            per_frame_href_r <= per_frame_href;
            per_frame_clken_r <= per_frame_clken;
        end
end

wire vsync_pos_flag; // 场同步信号上升沿
wire vsync_neg_flag; // 场同步信号下降沿
assign vsync_pos_flag = per_frame_vsync & (~per_frame_vsync_r);
assign vsync_neg_flag = (~per_frame_vsync) & per_frame_vsync_r;

// 对输入的像素进行“行/场”方向计数，得到其纵横坐标
reg [9:0]   x_cnt;
reg [9:0]   y_cnt;
always@(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        x_cnt <= 10'd0;
        y_cnt <= 10'd0;
    end
    else if(per_frame_vsync)begin
        x_cnt <= 10'd0;
        y_cnt <= 10'd0;
    end
    else if(per_frame_clken) begin
        if(x_cnt < IMG_HDISP - 10'd1) begin
            x_cnt <= x_cnt + 1'b1;
            y_cnt <= y_cnt;
        end
        else begin
            x_cnt <= 10'd0;
            y_cnt <= y_cnt + 1'b1;
        end
    end
end

// 遍历整个图片，求出暗通道最大亮度所在位置及其对应的彩色像素数据
reg [7:0] dark_max ;     // 寄存暗通道图像的最大值
reg [7:0] color_R ;      // 寄存相应的彩色通道（红）
reg [7:0] color_G ;      // 寄存相应的彩色通道（绿）
reg [7:0] color_B ;      // 寄存相应的彩色通道（蓝）

reg [9:0] atmos_x;       // 大气光强度所在位置的横坐标
reg [9:0] atmos_y;       // 大气光强度所在位置的纵坐标

always@(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        dark_max <= 8'd0;
        color_R <= 8'd0;
        color_G <= 8'd0;
        color_B <= 8'd0;

        atmos_x <= 10'd0;
        atmos_y <= 10'd0;
    end
    else begin
        // 一帧开始时初始化参数
        if(vsync_neg_flag)begin
            dark_max <= 8'd0;
            color_R <= 8'd0;
            color_G <= 8'd0;
            color_B <= 8'd0;

            atmos_x <= 10'd0;
            atmos_y <= 10'd0;
        end
        else if(per_frame_clken) begin
            // 遍历过程中更新暗通道最大值及对应彩色通道、位置
            if(per_img_Dark > dark_max) begin
                dark_max <= per_img_Dark;
                color_R <= per_img_red;
                color_G <= per_img_green;
                color_B <= per_img_blue;

                atmos_x <= x_cnt;
                atmos_y <= y_cnt;
            end
        end
    end
end

// 一帧结束后，计算彩色通道最大值并输出大气光相关结果
always@(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        atmospheric_light <= 8'd0;
        atmospheric_pos_x <= 10'd0;
        atmospheric_pos_y <= 10'd0;
    end
    else begin
        // 一帧结束时（场同步上升沿）输出最终结果
        if(vsync_pos_flag)begin
            atmospheric_pos_x <= atmos_x;
            atmospheric_pos_y <= atmos_y;

            // 取彩色通道（R/G/B）中的最大值作为大气光强度
            if((color_R > color_G) && (color_R > color_B))
                atmospheric_light <= color_R;
            else if((color_G > color_R) && (color_G > color_B))
                atmospheric_light <= color_G;
            else
                atmospheric_light <= color_B;
        end
    end
end

endmodule