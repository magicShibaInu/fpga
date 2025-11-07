module blob_detection #(
    parameter IMG_WIDTH    = 800,
    parameter IMG_HEIGHT   = 600,
    parameter LABEL_BITS   = 4,
    parameter MAX_OBJ      = 10
)(
    input                       clk,
    input                       rst_n,
    input                       din,                // 输入二值像素（1表示前景）
    input                       din_valid,          // 输入有效
    input                       hsync,              // 行同步
    input                       vsync,              // 场同步
    output reg [LABEL_BITS-1:0] pixel_label,        // 输出像素标签（0表示背景）
    output reg                  label_valid         // 标签有效
);

    // 声明循环变量（解决VRFC 10-2019错误）
    integer i;

    reg [LABEL_BITS-1:0] current_label;              // 当前可用标签
    reg [LABEL_BITS-1:0] label_map [0:MAX_OBJ-1];    // 标签映射表（处理等价标签）
    reg [LABEL_BITS-1:0] row_buffer [0:IMG_WIDTH-1]; // 上一行标签缓存

    reg hsync_d, vsync_d;
    wire hsync_posedge = hsync & ~hsync_d;
    wire vsync_posedge = vsync & ~vsync_d;

    // 同步信号延迟
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            hsync_d <= 0;
            vsync_d <= 0;
        end else begin
            hsync_d <= hsync;
            vsync_d <= vsync;
        end
    end

    // 行计数器（用于行缓存索引）
    reg [14:0] col_cnt;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) col_cnt <= 0;
        else if(vsync_posedge) col_cnt <= 0;
        else if(din_valid && hsync) col_cnt <= (col_cnt == IMG_WIDTH-1) ? 0 : col_cnt + 1;
    end

    // 第一遍扫描：标记当前像素与左/上像素的连通性
    reg [LABEL_BITS-1:0] left_label, up_label;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            current_label <= 1;  // 标签从1开始（0为背景）
            pixel_label <= 0;
            label_valid <= 0;
            left_label <= 0;
            up_label <= 0;
            for(i=0; i<MAX_OBJ; i=i+1) label_map[i] <= i;  // 循环变量i已声明
            for(i=0; i<IMG_WIDTH; i=i+1) row_buffer[i] <= 0;  // 循环变量i已声明
        end else if(vsync_posedge) begin  // 帧开始重置
            current_label <= 1;
            pixel_label <= 0;
            label_valid <= 0;
            left_label <= 0;
            up_label <= 0;
            for(i=0; i<MAX_OBJ; i=i+1) label_map[i] <= i;  // 循环变量i已声明
            for(i=0; i<IMG_WIDTH; i=i+1) row_buffer[i] <= 0;  // 循环变量i已声明
        end else if(din_valid && hsync) begin  // 有效像素
            label_valid <= 1'b1;
            if(din == 1'b0) begin  // 背景像素
                pixel_label <= 0;
                left_label <= 0;
                up_label <= 0;
            end else begin  // 前景像素
                // 左像素标签（当前行左侧）
                left_label <= (col_cnt == 0) ? 0 : pixel_label;
                // 上像素标签（上一行同一列）
                up_label <= row_buffer[col_cnt];

                // 情况1：左和上都无标签 -> 分配新标签
                if(left_label == 0 && up_label == 0) begin
                    if(current_label < MAX_OBJ) begin
                        pixel_label <= current_label;
                        current_label <= current_label + 1;
                    end else pixel_label <= 0;  // 超过最大目标数，不标记
                end
                // 情况2：只有左有标签 -> 继承左标签
                else if(left_label != 0 && up_label == 0) begin
                    pixel_label <= left_label;
                end
                // 情况3：只有上有标签 -> 继承上标签
                else if(left_label == 0 && up_label != 0) begin
                    pixel_label <= up_label;
                end
                // 情况4：左和上都有标签 -> 取最小标签（处理等价）
                else begin
                    pixel_label <= (left_label < up_label) ? left_label : up_label;
                    // 更新标签映射（小标签作为大标签的父标签）
                    if(left_label < up_label) begin
                        label_map[up_label] <= left_label;
                    end else begin
                        label_map[left_label] <= up_label;
                    end
                end

                // 更新行缓存（存储当前行标签，供下一行参考）
                row_buffer[col_cnt] <= pixel_label;
            end
        end else begin
            label_valid <= 1'b0;
            pixel_label <= 0;
        end
    end

    // 第二遍扫描：合并等价标签（取最小根标签）
    reg [LABEL_BITS-1:0] pixel_label_raw;
    reg label_valid_raw;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            pixel_label_raw <= 0;
            label_valid_raw <= 0;
        end else begin
            pixel_label_raw <= pixel_label;
            label_valid_raw <= label_valid;
        end
    end

    // 递归查找根标签
    function [LABEL_BITS-1:0] find_root;
        input [LABEL_BITS-1:0] label;
        begin
            if(label == 0) find_root = 0;
            else if(label_map[label] == label) find_root = label;
            else find_root = find_root(label_map[label]);
        end
    endfunction

    // 输出最终标签（根标签）
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            pixel_label <= 0;
            label_valid <= 0;
        end else begin
            label_valid <= label_valid_raw;
            pixel_label <= find_root(pixel_label_raw);  // 合并等价标签
        end
    end

endmodule
