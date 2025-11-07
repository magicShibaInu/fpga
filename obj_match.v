`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// 模块名: obj_matcher_bus
// 功能: 多目标中心点匹配 + 速度检测 (Vivado 兼容版)
// 作者: ChatGPT (2025)
// 说明:
//  - 输入中心点为打包总线形式: curr_cx_bus = {obj7,obj6,...,obj0}
//  - 每帧在 vsync_posedge 时更新匹配和速度
//////////////////////////////////////////////////////////////////////////////////
module obj_matcher_bus #(
    parameter MAX_OBJS      = 8,
    parameter DIST_THRESH   = 50    // 匹配距离阈值（像素）
)(
    input                   clk,
    input                   rst_n,
    input                   vsync_posedge,   // 每帧触发信号
    input             [5:0]    SPEED_THRESH,       // 高速阈值（像素/帧
    input  [MAX_OBJS*15-1:0] curr_cx_bus,    // 打包的中心X坐标
    input  [MAX_OBJS*15-1:0] curr_cy_bus,    // 打包的中心Y坐标
    input  [MAX_OBJS-1:0]    curr_valid_bus, // 每个目标是否有效

    output reg [MAX_OBJS*16-1:0] speed_bus,  // 每个目标的速度
    output reg [MAX_OBJS-1:0]    fast_bus    // 高速目标标志
);

    //------------------------------------------------------------
    // 拆包信号
    //------------------------------------------------------------
    reg [14:0] curr_cx [0:MAX_OBJS-1];
    reg [14:0] curr_cy [0:MAX_OBJS-1];
    reg        curr_valid [0:MAX_OBJS-1];

    integer k;
    always @(*) begin
        for(k = 0; k < MAX_OBJS; k = k + 1) begin
            curr_cx[k] = curr_cx_bus[15*k +: 15];
            curr_cy[k] = curr_cy_bus[15*k +: 15];
            curr_valid[k] = curr_valid_bus[k];
        end
    end

    //------------------------------------------------------------
    // 上一帧存储
    //------------------------------------------------------------
    reg [14:0] prev_cx [0:MAX_OBJS-1];
    reg [14:0] prev_cy [0:MAX_OBJS-1];
    reg        prev_valid [0:MAX_OBJS-1];

    reg [15:0] speed [0:MAX_OBJS-1];
    reg        fast_obj [0:MAX_OBJS-1];

    //------------------------------------------------------------
    // 匹配与速度计算
    //------------------------------------------------------------
    integer i, j;
    reg [15:0] dist, min_dist;
    reg [3:0]  match_idx;
    reg matched [0:MAX_OBJS-1];

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            for(i=0;i<MAX_OBJS;i=i+1) begin
                prev_cx[i] <= 0;
                prev_cy[i] <= 0;
                prev_valid[i] <= 0;
                speed[i] <= 0;
                fast_obj[i] <= 0;
            end
        end
        else if(vsync_posedge) begin
            // 清空匹配标志
            for(i=0;i<MAX_OBJS;i=i+1)
                matched[i] <= 0;

            // 匹配
            for(j=0;j<MAX_OBJS;j=j+1) begin
                if(curr_valid[j]) begin
                    min_dist = 16'hFFFF;
                    match_idx = 4'hF;
                    for(i=0;i<MAX_OBJS;i=i+1) begin
                        if(prev_valid[i]) begin
                            dist = (curr_cx[j] > prev_cx[i]) ?
                                   (curr_cx[j] - prev_cx[i]) : (prev_cx[i] - curr_cx[j]);
                            dist = dist + ((curr_cy[j] > prev_cy[i]) ?
                                   (curr_cy[j] - prev_cy[i]) : (prev_cy[i] - curr_cy[j]));
                            if(dist < min_dist) begin
                                min_dist = dist;
                                match_idx = i;
                            end
                        end
                    end

                    // 匹配成功
                    if((match_idx != 4'hF) && (min_dist < DIST_THRESH)) begin
                        speed[match_idx] <= min_dist;
                        fast_obj[match_idx] <= (min_dist > SPEED_THRESH);
                        prev_cx[match_idx] <= curr_cx[j];
                        prev_cy[match_idx] <= curr_cy[j];
                        prev_valid[match_idx] <= 1;
                        matched[match_idx] <= 1;
                    end
                    // 未匹配到 -> 新目标
                    else begin
                        for(i=0;i<MAX_OBJS;i=i+1) begin
                            if(!matched[i] && !prev_valid[i]) begin
                                prev_cx[i] <= curr_cx[j];
                                prev_cy[i] <= curr_cy[j];
                                prev_valid[i] <= 1;
                                speed[i] <= 0;
                                fast_obj[i] <= 0;
                                matched[i] <= 1;
                                disable inner_loop;
                            end
                        end
                    end
                end
            end

            // 未匹配到的旧目标清除
            for(i=0;i<MAX_OBJS;i=i+1)
                if(!matched[i])
                    prev_valid[i] <= 0;
        end
    end

    //------------------------------------------------------------
    // 打包输出
    //------------------------------------------------------------
    always @(*) begin
        for(i=0;i<MAX_OBJS;i=i+1) begin
            speed_bus[16*i +: 16] = speed[i];
            fast_bus[i] = fast_obj[i];
        end
    end

endmodule
