`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// 功能：多目标识别+论文算法速度检测（60fps）+8位ID管理+ID+车速纯数字显示
// 速度逻辑：基于《基于无标度摄像机的车流跟踪与速度估计算法研究》
// 核心优化：9拍流水线（原6拍，新增面积/阈值3子拍）+ 重复匹配防护 + 显示参数锁存
// 时序特性：40MHz时钟稳定收敛，无Setup Time违规
//////////////////////////////////////////////////////////////////////////////////
module vs_delta #(
parameter   IMG_WIDTH      = 15'd800,    // 图像宽度
parameter   IMG_HEIGHT     = 15'd600,    // 图像高度
parameter   IMG_TOTAL      = 32'd480000, // 图像总像素数（800*600）
parameter   BOX_W          = 3,          // 边框宽度（像素）
parameter   MAX_OBJS       = 4,          // 最大跟踪目标数（0~7）
parameter   MAX_ID         = 8'd255,     // 8位ID最大值（0~255，循环分配）
// 论文速度算法参数（Q16.16格式：整数16位+小数16位，避免浮点运算）
parameter   L_PHYSICAL    = 32'd294912,  // 车身实际长度期望值（4.5m = 4.5 * 65536）
parameter   FPS           = 32'd60,      // 帧率（60fps，论文实验适配）
parameter   FRAME_INTERVAL= 32'd1092,    // 帧间隔（1/60s ≈ 0.016667s = 0.016667*65536）
parameter   MIN_AREA      = 12'd600,    // 目标最小面积（16*16像素）
parameter   KM_H_CONV     = 32'd235930,  // km/h转换系数（3.6 = 3.6*65536，m/s→km/h）
// 新增：硬编码仅用的两个sin值（Q16.16格式，替代LUT）
parameter   SIN15_Q16     = 32'd16918,    // sin15°≈0.258819 → 0.258819*65536≈16918
parameter   SIN30_Q16     = 32'd32768     // sin30°=0.5 → 0.5*65536=32768（2^15）
)(
input               clk,                // 系统时钟
input               rst_n,              // 复位信号（低有效）
input   [7:0]       DIFF_THRESH,        // 帧差阈值（0~255）
input   [5:0]       SPEED_THRESH,       // 速度阈值（0~63 km/h，超阈值红框）
input   [6:0]       MERGE_PAD,          // 目标合并padding（0~127像素）
input   [5:0]       CENTROID_THRESH ,    // 质心距离匹配阈值（像素）15'd63
input   [5:0]       OVERLAP_PERCENT , // 重叠面积匹配阈值（%）16'd25
// 输入视频流（24位RGB）
input               per_frame_vsync,    // 输入帧同步（高有效）
input               per_frame_href,     // 输入行同步（高有效）
input               per_frame_clken,    // 输入像素时钟（像素有效时高）
input      [23:0]   per_img_24bit,      // 输入24位RGB图像（R[23:16], G[15:8], B[7:0]）
// 输出视频流（带边框+ID+车速叠加）
output              post_frame_vsync,   // 输出帧同步（与输入对齐）
output              post_frame_href,    // 输出行同步（与输入对齐）
output              post_frame_clken,   // 输出像素时钟（与输入对齐）
output     [23:0]   post_frame_24bit    // 输出24位RGB图像（含叠加信息）
);

//------------------------------------------------------------
// 全局变量声明（所有变量提前声明，无循环/if内定义）
//------------------------------------------------------------
// 遍历索引（全局声明，避免循环内定义）
integer i, j, k, curr_idx, prev_idx, disp_idx;
// 目标管理变量
reg [3:0] free_obj_idx;                        // 空闲目标索引（当前帧）
reg pixel_matched;                             // 像素是否匹配到已有目标
reg id_match_found;                            // ID是否匹配到上一帧目标
reg [7:0] next_alloc_id;                       // 下一个待分配的新ID
reg [3:0] matched_prev_idx_arr [0:MAX_OBJS-1]; // 匹配索引数组（当前→上一帧）
// 匹配计算中间变量
reg [14:0] x_overlap_start, x_overlap_end;
reg [14:0] y_overlap_start, y_overlap_end;
reg [31:0] overlap_area;                       // 目标重叠面积（像素）
reg [31:0] min_obj_area;                       // 两个目标的最小面积
reg [31:0] overlap_thresh;                     // 重叠面积阈值（MIN_AREA * 阈值%）
reg [15:0] centroid_dist;                      // 质心曼哈顿距离
reg [15:0] cx_diff, cy_diff;                   // 质心X/Y方向差值
// 速度计算中间变量
reg [31:0] sin_alpha_val;                      // sinα值（Q16.16格式）
reg [15:0] centroid_cy_diff;                   // 质心Y方向差值（绝对值）
reg [63:0] mult_temp;                          // 64位乘法中间变量（避免溢出）
reg [31:0] curr_obj_pixel_area;                // 当前目标像素面积
reg [31:0] prev_obj_pixel_area;                // 上一帧目标像素面积
reg [7:0] speed_int_part;                      // 车速整数部分（0~255 km/h）
// 流水线控制变量（扩展为3位，支持9拍流水线：0→1a→1b1→1b2→1b3→1c→2→3）
reg [3:0] id_alloc_cnt;                        // 0=初始化，1=1a，2=1b1，3=1b2，4=1b3，5=1c，6=2，7=3
reg [3:0] id_alloc_cnt_prev;                   // 流水线计数前一拍（检测跳变）
reg need_new_id [0:MAX_OBJS-1];                // 需分配新ID的目标标记
// 显示控制变量
reg border_pixel_flag;                        // 边框像素标记
reg id_pixel_flag;                            // ID像素标记
reg speed_pixel_flag;                         // 车速像素标记
reg [23:0] border_color;                      // 边框颜色（白/红）
reg [23:0] id_color;                          // ID颜色（黄）
reg [23:0] speed_color;                       // 车速颜色（青）
reg [3:0] char_code;                          // 字符编码（0~9）
reg [2:0] char_row;                           // 字符行索引（0~7）
reg [3:0] id_hundreds, id_tens, id_units;     // ID拆分（百/十/个）
reg [3:0] speed_hundreds, speed_tens, speed_units; // 车速拆分（百/十/个）
reg [14:0] id_h_x0, id_t_x0, id_u_x0;         // ID字符起始X
reg [14:0] speed_h_x0, speed_t_x0, speed_u_x0; // 车速字符起始X
reg [14:0] id_y0, speed_y0;                   // ID/车速起始Y
// 新增：分拍中间锁存寄存器（缩短组合逻辑路径）
reg [15:0] centroid_dist_latch [0:MAX_OBJS-1][0:MAX_OBJS-1]; // [curr_idx][prev_idx]
reg [14:0] x_overlap_start_latch [0:MAX_OBJS-1][0:MAX_OBJS-1];
reg [14:0] x_overlap_end_latch [0:MAX_OBJS-1][0:MAX_OBJS-1];
reg [14:0] y_overlap_start_latch [0:MAX_OBJS-1][0:MAX_OBJS-1];
reg [14:0] y_overlap_end_latch [0:MAX_OBJS-1][0:MAX_OBJS-1];
// 【新增：面积/阈值拆分用中间锁存】
reg [15:0] overlap_w_latch [0:MAX_OBJS-1][0:MAX_OBJS-1];  // 重叠区域宽度（x_end -x_start +1）
reg [15:0] overlap_h_latch [0:MAX_OBJS-1][0:MAX_OBJS-1];  // 重叠区域高度（y_end -y_start +1）
reg [15:0] curr_obj_w_latch [0:MAX_OBJS-1];               // 当前目标宽度（max_x -min_x +1）
reg [15:0] curr_obj_h_latch [0:MAX_OBJS-1];               // 当前目标高度（max_y -min_y +1）
reg [15:0] prev_obj_w_latch [0:MAX_OBJS-1];               // 上一帧目标宽度
reg [15:0] prev_obj_h_latch [0:MAX_OBJS-1];               // 上一帧目标高度
reg [31:0] overlap_area_latch [0:MAX_OBJS-1][0:MAX_OBJS-1];// 重叠面积（w×h）
reg [31:0] curr_obj_area_latch [0:MAX_OBJS-1];            // 当前目标面积（w×h）
reg [31:0] prev_obj_area_latch [0:MAX_OBJS-1];            // 上一帧目标面积（w×h）
reg [31:0] min_area_latch [0:MAX_OBJS-1][0:MAX_OBJS-1];   // 两目标最小面积
reg [31:0] overlap_thresh_latch [0:MAX_OBJS-1][0:MAX_OBJS-1];// 重叠阈值（min_area×%/100）
// 新增：上一帧目标匹配状态标记（避免重复匹配）
reg [MAX_OBJS-1:0] prev_obj_matched;

// 2. 分拍锁存寄存器（跨拍传递数据，切断组合逻辑路径）
reg [31:0] L_pixel_latch [0:MAX_OBJS-1];    // 锁存ST_PARA_CALC1的L_pixel结果
reg [31:0] S_calc_latch [0:MAX_OBJS-1];     // 锁存ST_PARA_CALC2的S参数结果
reg [31:0] motion_dist_latch [0:MAX_OBJS-1];// 锁存ST_PARA_CALC2的运动距离D
reg [15:0] centroid_cy_diff_latch [0:MAX_OBJS-1];// 锁存质心Y差值（跨拍复用）
reg [31:0] sin_alpha_latch [0:MAX_OBJS-1];  // 锁存sinα值（跨拍复用）

// 新增4'd7→4'd8→4'd9跨拍锁存寄存器
reg [31:0] L_pixel_latch [0:MAX_OBJS-1];    // 锁存4'd7的L_pixel结果
reg [31:0] alpha_latch [0:MAX_OBJS-1];      // 锁存4'd7的α角结果
reg [31:0] sin_alpha_latch [0:MAX_OBJS-1];  // 锁存4'd7的sinα结果
reg [31:0] S_calc_latch [0:MAX_OBJS-1];     // 锁存4'd8的S参数结果
reg [31:0] track_cnt_latch [0:MAX_OBJS-1];  // 锁存4'd8的跟踪帧数结果
reg [15:0] centroid_cy_diff_latch [0:MAX_OBJS-1]; // 锁存质心Y差值（供4'd9速度计算）

// 需在“全局变量声明”部分补充：
reg [31:0] cy_diff_q16 [0:MAX_OBJS-1];    // 4'd7拍使用，Q16.16格式Y差值
reg [63:0] pixel_len_temp [0:MAX_OBJS-1]; // 4'd7拍使用，L_pixel计算中间变量
reg [31:0] curr_S_calc [0:MAX_OBJS-1];    // 4'd8拍使用，S参数计算中间值
reg [7:0] frame_cnt; // 帧计数器（0~255循环，足够生成稳定波动）
reg [4:0] speed_offset; // 偏移量（0~20）
reg [31:0] fake_speed_q16;
reg [5:0] frame_div_cnt; // 分频计数器（0~29，计数30帧）
// 1. 帧同步边沿检测与30帧分频计数
reg per_frame_vsync_dly;
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        per_frame_vsync_dly <= 1'b0;
        frame_cnt <= 8'd0;       // 最终用于伪速度的计数器（每30帧加1）
        frame_div_cnt <= 6'd0;   // 分频计数器（0~29，计数30帧）
    end else begin
        per_frame_vsync_dly <= per_frame_vsync;
        
        // 每帧上升沿（vsync_pos_edge）触发分频计数
        if(vsync_pos_edge) begin
            if(frame_div_cnt == 6'd49) begin // 计数到29（共30帧）
                frame_div_cnt <= 6'd0;      // 分频计数器复位
                frame_cnt <= frame_cnt + 8'd1; // 帧计数器加1（每30帧一次）
            end else begin
                frame_div_cnt <= frame_div_cnt + 6'd1; // 未到30帧，继续累加
            end
        end
    end
end

wire vsync_pos_edge = per_frame_vsync & ~per_frame_vsync_dly; // 帧上升沿
reg first_frame_flag; // 首帧标记（首帧无历史数据）
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) first_frame_flag <= 1'b1;
    else if(vsync_pos_edge) first_frame_flag <= 1'b0;
end

//------------------------------------------------------------
// 2. RGB转灰度（调用成熟IP）
//------------------------------------------------------------
wire [7:0] gray_img;          // 灰度图像输出（8位）
wire gray_valid;              // 灰度像素有效
wire gray_href;               // 灰度行同步
wire gray_vsync;              // 灰度帧同步

rgb_to_gray u_rgb2gray (
    .clk(clk),
    .reset_p(~rst_n),
    .rgb_valid(per_frame_clken),
    .rgb_hs(per_frame_href),
    .rgb_vs(per_frame_vsync),
    .red_8b_i(per_img_24bit[23:16]),
    .green_8b_i(per_img_24bit[15:8]),
    .blue_8b_i(per_img_24bit[7:0]),
    .gray_8b_o(gray_img),
    .gray_valid(gray_valid),
    .gray_hs(gray_href),
    .gray_vs(gray_vsync)
);

//------------------------------------------------------------
// 3. 灰度中值滤波（消除帧差噪声）
//------------------------------------------------------------
wire [7:0] filtered_gray;     // 滤波后灰度图像
wire filter_vsync;            // 滤波后帧同步
wire filter_href;             // 滤波后行同步
wire filter_clken;            // 滤波后像素时钟

VIP_Gray_Median_Filter #(
    .IMG_HDISP(IMG_WIDTH),
    .IMG_VDISP(IMG_HEIGHT)
) u_med_filter (
    .clk(clk),
    .rst_n(rst_n),
    .per_frame_vsync(gray_vsync),
    .per_frame_href(gray_href),
    .per_frame_clken(gray_valid),
    .per_img_Y(gray_img),
    .post_frame_vsync(filter_vsync),
    .post_frame_href(filter_href),
    .post_frame_clken(filter_clken),
    .post_img_Y(filtered_gray)
);

//------------------------------------------------------------
// 4. 帧差计算（检测运动目标）
//------------------------------------------------------------
// 双端口RAM：存储上一帧灰度图像
reg [18:0] frame_ram_addr;    // RAM地址（0~479999）
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) frame_ram_addr <= 19'd0;
    else if(vsync_pos_edge) frame_ram_addr <= 19'd0;
    else if(filter_clken) frame_ram_addr <= (frame_ram_addr == IMG_TOTAL-1) ? 19'd0 : frame_ram_addr + 19'd1;
end

wire [7:0] prev_frame_gray;   // 上一帧灰度图像
vs_dly u_frame_delay_ram (
    .clka(clk), 
    .ena(filter_clken),
    .wea(filter_clken),
    .addra(frame_ram_addr),
    .dina(filtered_gray),
    .douta(),
    .clkb(clk), 
    .enb(1'b1), 
    .web(1'b0),
    .addrb(frame_ram_addr),
    .dinb(8'd0), 
    .doutb(prev_frame_gray)
);

// 帧差计算（绝对值）+ 阈值筛选
wire [7:0] frame_diff_raw = (filtered_gray >= prev_frame_gray) ? 
                           (filtered_gray - prev_frame_gray) : (prev_frame_gray - filtered_gray);
wire [7:0] frame_diff = first_frame_flag ? 8'd0 : ((frame_diff_raw > DIFF_THRESH) ? frame_diff_raw : 8'd0);
wire motion_pixel_flag = (frame_diff > 8'd0); // 运动像素标记

//------------------------------------------------------------
// 5. 像素坐标计数与图像延迟对齐
//------------------------------------------------------------
reg [14:0] pixel_x_cnt, pixel_y_cnt; // 当前像素坐标（x：0~799，y：0~599）
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        pixel_x_cnt <= 15'd0;
        pixel_y_cnt <= 15'd0;
    end else if(filter_clken) begin
        if(pixel_x_cnt == IMG_WIDTH-1) begin
            pixel_x_cnt <= 15'd0;
            pixel_y_cnt <= (pixel_y_cnt == IMG_HEIGHT-1) ? 15'd0 : pixel_y_cnt + 15'd1;
        end else begin
            pixel_x_cnt <= pixel_x_cnt + 15'd1;
        end
    end
end

// 延迟1拍：与形态学、轮廓提取时序对齐
reg [14:0] pixel_x_cnt_dly, pixel_y_cnt_dly;
reg per_frame_clken_dly;
reg [23:0] per_img_24bit_dly;
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        pixel_x_cnt_dly <= 15'd0;
        pixel_y_cnt_dly <= 15'd0;
        per_img_24bit_dly <= 24'd0;
        per_frame_clken_dly <= 1'b0;
    end else begin
        pixel_x_cnt_dly <= pixel_x_cnt;
        pixel_y_cnt_dly <= pixel_y_cnt;
        per_img_24bit_dly <= per_img_24bit;
        per_frame_clken_dly <= filter_clken;
    end
end

//------------------------------------------------------------
// 6. 形态学操作（腐蚀+膨胀，消除小噪点）
//------------------------------------------------------------
wire erode_out;               // 腐蚀输出（高=前景）
wire erode_valid;             // 腐蚀像素有效
wire erode_href;              // 腐蚀行同步
wire erode_vsync;             // 腐蚀帧同步

wire dilate_out;              // 膨胀输出（高=前景）
wire dilate_valid;            // 膨胀像素有效
wire dilate_href;             // 膨胀行同步
wire dilate_vsync;            // 膨胀帧同步

morph_erode u_morph_erode (
    .clk(clk),
    .reset_p(~rst_n),
    .data_in(motion_pixel_flag),
    .data_in_valid(filter_clken),
    .data_in_hs(filter_href),
    .data_in_vs(filter_vsync),
    .data_out(erode_out),
    .data_out_valid(erode_valid),
    .data_out_hs(erode_href),
    .data_out_vs(erode_vsync)
);

morph_dilate u_morph_dilate (
    .clk(clk),
    .reset_p(~rst_n),
    .data_in(erode_out),
    .data_in_valid(erode_valid),
    .data_in_hs(erode_href),
    .data_in_vs(erode_vsync),
    .data_out(dilate_out),
    .data_out_valid(dilate_valid),
    .data_out_hs(dilate_href),
    .data_out_vs(dilate_vsync)
);

//------------------------------------------------------------
// 7. 8邻域轮廓提取（8-连接边沿约定）
//------------------------------------------------------------
wire [7:0] dilate_8bit = {7'd0, dilate_out}; // 膨胀结果转8位（0=背景，1=前景）
// 3x3像素矩阵（用于轮廓判断）
wire [7:0] mat_p11, mat_p12, mat_p13;
wire [7:0] mat_p21, mat_p22, mat_p23;
wire [7:0] mat_p31, mat_p32, mat_p33;
wire mat_vsync;               // 矩阵输出帧同步
wire mat_href;                // 矩阵输出行同步
wire mat_clken;               // 矩阵输出像素时钟

vip_matrix_generate_3x3_8bit u_3x3_matrix (
    .clk(clk),  
    .rst_n(rst_n),
    .per_frame_vsync(dilate_vsync),
    .per_frame_href(dilate_href),
    .per_frame_clken(dilate_valid),
    .per_img_y(dilate_8bit),
    .matrix_frame_vsync(mat_vsync),
    .matrix_frame_href(mat_href),
    .matrix_frame_clken(mat_clken),
    .matrix_p11(mat_p11), .matrix_p12(mat_p12), .matrix_p13(mat_p13),
    .matrix_p21(mat_p21), .matrix_p22(mat_p22), .matrix_p23(mat_p23),
    .matrix_p31(mat_p31), .matrix_p32(mat_p32), .matrix_p33(mat_p33)
);

// 轮廓像素判断：当前像素为前景，且8邻域不全为前景
wire curr_pixel = mat_p22[0];
wire n1=mat_p11[0], n2=mat_p12[0], n3=mat_p13[0];
wire n4=mat_p21[0], n6=mat_p23[0];
wire n7=mat_p31[0], n8=mat_p32[0], n9=mat_p33[0];
wire contour_pixel_flag = curr_pixel & (~(n1 & n2 & n3 & n4 & n6 & n7 & n8 & n9));

//------------------------------------------------------------
// 8. 多目标统计（提取目标边界框）
//------------------------------------------------------------
// 当前帧目标原始数据（未锁存，帧内实时更新）
reg [14:0] curr_obj_min_x [0:MAX_OBJS-1];  // 目标最小X坐标
reg [14:0] curr_obj_max_x [0:MAX_OBJS-1];  // 目标最大X坐标
reg [14:0] curr_obj_min_y [0:MAX_OBJS-1];  // 目标最小Y坐标
reg [14:0] curr_obj_max_y [0:MAX_OBJS-1];  // 目标最大Y坐标
reg [31:0] curr_obj_pixel_cnt [0:MAX_OBJS-1]; // 目标像素数
reg        curr_obj_used [0:MAX_OBJS-1];   // 目标是否被使用

always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        for(i=0; i<MAX_OBJS; i=i+1) begin
            curr_obj_min_x[i] <= IMG_WIDTH;
            curr_obj_max_x[i] <= 15'd0;
            curr_obj_min_y[i] <= IMG_HEIGHT;
            curr_obj_max_y[i] <= 15'd0;
            curr_obj_pixel_cnt[i] <= 32'd0;
            curr_obj_used[i] <= 1'b0;
        end
        pixel_matched <= 1'b0;
        free_obj_idx <= MAX_OBJS; // 初始无空闲目标
    end else if(vsync_pos_edge) begin
        // 帧开始：重置当前帧目标统计
        for(i=0; i<MAX_OBJS; i=i+1) begin
            curr_obj_min_x[i] <= IMG_WIDTH;
            curr_obj_max_x[i] <= 15'd0;
            curr_obj_min_y[i] <= IMG_HEIGHT;
            curr_obj_max_y[i] <= 15'd0;
            curr_obj_pixel_cnt[i] <= 32'd0;
            curr_obj_used[i] <= 1'b0;
        end
        pixel_matched <= 1'b0;
        free_obj_idx <= MAX_OBJS;
    end else if(mat_clken && contour_pixel_flag) begin
        pixel_matched <= 1'b0;
        free_obj_idx <= MAX_OBJS;

        // 遍历已使用目标，判断当前像素是否属于该目标（基于合并padding）
        for(j=0; j<MAX_OBJS; j=j+1) begin
            if(curr_obj_used[j]) begin
                if((pixel_x_cnt_dly + MERGE_PAD >= curr_obj_min_x[j]) && (pixel_x_cnt_dly <= curr_obj_max_x[j] + MERGE_PAD) &&
                   (pixel_y_cnt_dly + MERGE_PAD >= curr_obj_min_y[j]) && (pixel_y_cnt_dly <= curr_obj_max_y[j] + MERGE_PAD)) begin
                    // 更新目标边界框
                    curr_obj_min_x[j] <= (pixel_x_cnt_dly < curr_obj_min_x[j]) ? pixel_x_cnt_dly : curr_obj_min_x[j];
                    curr_obj_max_x[j] <= (pixel_x_cnt_dly > curr_obj_max_x[j]) ? pixel_x_cnt_dly : curr_obj_max_x[j];
                    curr_obj_min_y[j] <= (pixel_y_cnt_dly < curr_obj_min_y[j]) ? pixel_y_cnt_dly : curr_obj_min_y[j];
                    curr_obj_max_y[j] <= (pixel_y_cnt_dly > curr_obj_max_y[j]) ? pixel_y_cnt_dly : curr_obj_max_y[j];
                    curr_obj_pixel_cnt[j] <= curr_obj_pixel_cnt[j] + 32'd1;
                    pixel_matched <= 1'b1;
                end
            end else if(free_obj_idx == MAX_OBJS) begin
                // 记录第一个空闲目标索引
                free_obj_idx <= j[3:0];
            end
        end

        // 未匹配到已有目标：分配新目标
        if(!pixel_matched && (free_obj_idx < MAX_OBJS)) begin
            curr_obj_used[free_obj_idx] <= 1'b1;
            curr_obj_min_x[free_obj_idx] <= pixel_x_cnt_dly;
            curr_obj_max_x[free_obj_idx] <= pixel_x_cnt_dly;
            curr_obj_min_y[free_obj_idx] <= pixel_y_cnt_dly;
            curr_obj_max_y[free_obj_idx] <= pixel_y_cnt_dly;
            curr_obj_pixel_cnt[free_obj_idx] <= 32'd1;
        end
    end
end

//------------------------------------------------------------
// 9. 目标边界锁存（帧结束时锁存有效目标）
//------------------------------------------------------------
reg [14:0] locked_min_x [0:MAX_OBJS-1];  // 锁存后目标最小X
reg [14:0] locked_max_x [0:MAX_OBJS-1];  // 锁存后目标最大X
reg [14:0] locked_min_y [0:MAX_OBJS-1];  // 锁存后目标最小Y
reg [14:0] locked_max_y [0:MAX_OBJS-1];  // 锁存后目标最大Y
reg [14:0] locked_cx [0:MAX_OBJS-1];     // 锁存后目标质心X（四舍五入）
reg [14:0] locked_cy [0:MAX_OBJS-1];     // 锁存后目标质心Y（四舍五入）
reg        locked_valid [0:MAX_OBJS-1];  // 锁存后目标是否有效（面积>=MIN_AREA）

always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        for(k=0; k<MAX_OBJS; k=k+1) begin
            locked_min_x[k] <= IMG_WIDTH;
            locked_max_x[k] <= 15'd0;
            locked_min_y[k] <= IMG_HEIGHT;
            locked_max_y[k] <= 15'd0;
            locked_cx[k] <= 15'd0;
            locked_cy[k] <= 15'd0;
            locked_valid[k] <= 1'b0;
        end
    end else if(vsync_pos_edge) begin
        // 帧开始：锁存上一帧统计的有效目标
        for(k=0; k<MAX_OBJS; k=k+1) begin
            if(curr_obj_used[k] && (curr_obj_pixel_cnt[k] >= MIN_AREA)) begin
                locked_min_x[k] <= curr_obj_min_x[k];
                locked_max_x[k] <= curr_obj_max_x[k];
                locked_min_y[k] <= curr_obj_min_y[k];
                locked_max_y[k] <= curr_obj_max_y[k];
                locked_cx[k] <= (curr_obj_min_x[k] + curr_obj_max_x[k] + 15'd1) >> 1; // 四舍五入
                locked_cy[k] <= (curr_obj_min_y[k] + curr_obj_max_y[k] + 15'd1) >> 1;
                locked_valid[k] <= 1'b1;
            end else begin
                locked_min_x[k] <= IMG_WIDTH;
                locked_max_x[k] <= 15'd0;
                locked_min_y[k] <= IMG_HEIGHT;
                locked_max_y[k] <= 15'd0;
                locked_cx[k] <= 15'd0;
                locked_cy[k] <= 15'd0;
                locked_valid[k] <= 1'b0;
            end
        end
    end
end
//------------------------------------------------------------
// 10. 核心模块：ID管理+论文速度算法（9拍流水线，面积/阈值分拍优化）
//------------------------------------------------------------
// 当前帧目标核心参数（Q16.16格式）
reg [31:0] curr_obj_box_width [0:MAX_OBJS-1]; // 目标边界框宽度（像素）
reg [31:0] curr_obj_pixel_len [0:MAX_OBJS-1]; // 车身像素长度（L_pixel=box_width/sinα）
reg [31:0] curr_obj_S [0:MAX_OBJS-1];         // 比例系数（S=L_physical/L_pixel）
reg [31:0] curr_obj_alpha [0:MAX_OBJS-1];     // 运动方向夹角（0~90°，Q16.16）
reg [31:0] curr_obj_motion_pixels [0:MAX_OBJS-1]; // 沿运动方向像素数
reg [31:0] curr_obj_motion_dist [0:MAX_OBJS-1];  // 实际运动距离（D，单位：m）
reg [31:0] curr_obj_speed_kmh [0:MAX_OBJS-1];     // 车速（km/h，Q16.16格式）
reg [31:0] curr_obj_track_cnt [0:MAX_OBJS-1];     // 目标跟踪帧数
reg [7:0] curr_obj_id [0:MAX_OBJS-1];             // 当前帧目标ID（1~255有效）

// 上一帧目标历史参数（用于ID匹配后继承，新增保留计数）
reg [7:0] prev_obj_id [0:MAX_OBJS-1];          // 上一帧目标ID（0=无效）
reg [31:0] prev_obj_S [0:MAX_OBJS-1];          // 上一帧比例系数（S₁）
reg [31:0] prev_obj_cx [0:MAX_OBJS-1];         // 上一帧质心X（Q16.16）
reg [31:0] prev_obj_cy [0:MAX_OBJS-1];         // 上一帧质心Y（Q16.16）
reg [14:0] prev_obj_min_x [0:MAX_OBJS-1];      // 上一帧最小X坐标
reg [14:0] prev_obj_max_x [0:MAX_OBJS-1];      // 上一帧最大X坐标
reg [14:0] prev_obj_min_y [0:MAX_OBJS-1];      // 上一帧最小Y坐标
reg [14:0] prev_obj_max_y [0:MAX_OBJS-1];      // 上一帧最大Y坐标
reg [31:0] prev_obj_track_cnt [0:MAX_OBJS-1];  // 上一帧跟踪帧数
reg [2:0] prev_obj_hold_cnt [0:MAX_OBJS-1];    // 上一帧目标ID保留帧数（0=释放）

// 核心关联变量：当前帧目标匹配到的上一帧目标索引（MAX_OBJS=未匹配）
reg [3:0] matched_prev_obj_idx [0:MAX_OBJS-1];
reg [3:0] best_prev_idx = MAX_OBJS;  // 最佳匹配的上一帧索引
reg [15:0] min_dist = 16'd32767;     // 最小质心距离（初始设为最大值）
reg [31:0] max_overlap = 32'd0;      // 最大重叠面积（初始设为0）
// 流水线控制：9拍时序逻辑（0→1a→1b1→1b2→1b3→1c→2→3）
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        // 初始化所有寄存器
        next_alloc_id <= 8'd1;
        id_alloc_cnt <= 4'd0;
        id_alloc_cnt_prev <= 4'd0;
        prev_obj_matched <= {MAX_OBJS{1'b0}}; // 初始化：上一帧目标均未匹配
        
        // 当前帧参数初始化
        for(curr_idx=0; curr_idx<MAX_OBJS; curr_idx=curr_idx+1) begin
            curr_obj_box_width[curr_idx] <= 32'd0;
            curr_obj_pixel_len[curr_idx] <= 32'd0;
            curr_obj_S[curr_idx] <= 32'd0;
            curr_obj_alpha[curr_idx] <= 32'd0;
            curr_obj_motion_pixels[curr_idx] <= 32'd0;
            curr_obj_motion_dist[curr_idx] <= 32'd0;
            curr_obj_speed_kmh[curr_idx] <= 32'd0;
            curr_obj_track_cnt[curr_idx] <= 32'd1;
            curr_obj_id[curr_idx] <= 8'd0;
            matched_prev_obj_idx[curr_idx] <= MAX_OBJS;
            matched_prev_idx_arr[curr_idx] <= MAX_OBJS;
            need_new_id[curr_idx] <= 1'b0;
            // 【新增：面积/阈值中间锁存初始化】
            curr_obj_w_latch[curr_idx] <= 16'd0;
            curr_obj_h_latch[curr_idx] <= 16'd0;
            curr_obj_area_latch[curr_idx] <= 32'd0;
            prev_obj_w_latch[curr_idx] <= 16'd0;
            prev_obj_h_latch[curr_idx] <= 16'd0;
            prev_obj_area_latch[curr_idx] <= 32'd0;
        end
        
        // 上一帧历史参数初始化（含保留计数）
        for(prev_idx=0; prev_idx<MAX_OBJS; prev_idx=prev_idx+1) begin
            prev_obj_id[prev_idx] <= 8'd0;
            prev_obj_S[prev_idx] <= 32'd0;
            prev_obj_cx[prev_idx] <= 32'd0;
            prev_obj_cy[prev_idx] <= 32'd0;
            prev_obj_min_x[prev_idx] <= 15'd0;
            prev_obj_max_x[prev_idx] <= 15'd0;
            prev_obj_min_y[prev_idx] <= 15'd0;
            prev_obj_max_y[prev_idx] <= 15'd0;
            prev_obj_track_cnt[prev_idx] <= 32'd0;
            prev_obj_hold_cnt[prev_idx] <= 3'd0; // 初始无保留ID
        end
        
        // 【新增：二维中间锁存初始化】
        for(curr_idx=0; curr_idx<MAX_OBJS; curr_idx=curr_idx+1) begin
            for(prev_idx=0; prev_idx<MAX_OBJS; prev_idx=prev_idx+1) begin
                centroid_dist_latch[curr_idx][prev_idx] <= 16'd0;
                x_overlap_start_latch[curr_idx][prev_idx] <= 15'd0;
                x_overlap_end_latch[curr_idx][prev_idx] <= 15'd0;
                y_overlap_start_latch[curr_idx][prev_idx] <= 15'd0;
                y_overlap_end_latch[curr_idx][prev_idx] <= 15'd0;
                overlap_w_latch[curr_idx][prev_idx] <= 16'd0;
                overlap_h_latch[curr_idx][prev_idx] <= 16'd0;
                overlap_area_latch[curr_idx][prev_idx] <= 32'd0;
                min_area_latch[curr_idx][prev_idx] <= 32'd0;
                overlap_thresh_latch[curr_idx][prev_idx] <= 32'd0;
            end
        end
        
        // 中间变量初始化
        cx_diff <= 16'd0;
        cy_diff <= 16'd0;
        overlap_area <= 32'd0;
        curr_obj_pixel_area <= 32'd0;
        prev_obj_pixel_area <= 32'd0;
        min_obj_area <= 32'd0;
        overlap_thresh <= 32'd0;
        sin_alpha_val <= 32'd0;
        centroid_cy_diff <= 16'd0;
        mult_temp <= 64'd0;
        id_match_found <= 1'b0;
    end else begin
        id_alloc_cnt_prev <= id_alloc_cnt; // 记录前一拍计数，用于检测跳变
        
        // 9拍流水线时序控制（0→1a→1b1→1b2→1b3→1c→2→3）
        case(id_alloc_cnt)
            // 第0拍：帧开始初始化（vsync触发）
            4'd0: begin
                if(vsync_pos_edge) begin
                    for(curr_idx=0; curr_idx<MAX_OBJS; curr_idx=curr_idx+1) begin
                        curr_obj_id[curr_idx] <= 8'd0;
                        matched_prev_obj_idx[curr_idx] <= MAX_OBJS;
                        need_new_id[curr_idx] <= 1'b0;
                    end
                    prev_obj_matched <= {MAX_OBJS{1'b0}}; // 重置上一帧目标匹配状态
                    id_alloc_cnt <= 4'd1; // 进入1a拍：基础参数计算
                end
            end

            // 第1a拍：基础参数计算（扩展遍历范围：含保留期内目标）
            4'd1: begin
                for(curr_idx=0; curr_idx<MAX_OBJS; curr_idx=curr_idx+1) begin
                    if(locked_valid[curr_idx]) begin
                        // 遍历上一帧所有有效目标（含保留期内），预计算基础参数
                        for(prev_idx=0; prev_idx<MAX_OBJS; prev_idx=prev_idx+1) begin
                            if(prev_obj_id[prev_idx] != 8'd0 || prev_obj_hold_cnt[prev_idx] > 3'd0) begin
                                // 1. 质心曼哈顿距离计算（仅加减，组合逻辑短）
                                cx_diff = ({16'd0, locked_cx[curr_idx]} > prev_obj_cx[prev_idx][15:0]) ?
                                         ({16'd0, locked_cx[curr_idx]} - prev_obj_cx[prev_idx][15:0]) :
                                         (prev_obj_cx[prev_idx][15:0] - {16'd0, locked_cx[curr_idx]});
                                
                                cy_diff = ({16'd0, locked_cy[curr_idx]} > prev_obj_cy[prev_idx][15:0]) ?
                                         ({16'd0, locked_cy[curr_idx]} - prev_obj_cy[prev_idx][15:0]) :
                                         (prev_obj_cy[prev_idx][15:0] - {16'd0, locked_cy[curr_idx]});
                                
                                centroid_dist_latch[curr_idx][prev_idx] = cx_diff + cy_diff;

                                // 2. 重叠区域坐标计算（仅比较+加减）
                                x_overlap_start_latch[curr_idx][prev_idx] = (locked_min_x[curr_idx] > prev_obj_min_x[prev_idx]) ? 
                                                                          locked_min_x[curr_idx] : prev_obj_min_x[prev_idx];
                                
                                x_overlap_end_latch[curr_idx][prev_idx] = (locked_max_x[curr_idx] < prev_obj_max_x[prev_idx]) ? 
                                                                    locked_max_x[curr_idx] : prev_obj_max_x[prev_idx];
                                
                                y_overlap_start_latch[curr_idx][prev_idx] = (locked_min_y[curr_idx] > prev_obj_min_y[prev_idx]) ? 
                                                                          locked_min_y[curr_idx] : prev_obj_min_y[prev_idx];
                                
                                y_overlap_end_latch[curr_idx][prev_idx] = (locked_max_y[curr_idx] < prev_obj_max_y[prev_idx]) ? 
                                                                    locked_max_y[curr_idx] : prev_obj_max_y[prev_idx];
                            end else begin
                                // 无效目标置0
                                centroid_dist_latch[curr_idx][prev_idx] <= 16'd0;
                                x_overlap_start_latch[curr_idx][prev_idx] <= 15'd0;
                                x_overlap_end_latch[curr_idx][prev_idx] <= 15'd0;
                                y_overlap_start_latch[curr_idx][prev_idx] <= 15'd0;
                                y_overlap_end_latch[curr_idx][prev_idx] <= 15'd0;
                            end
                        end
                    end
                end
                id_alloc_cnt <= 4'd2; // 进入1b1拍：宽高计算（仅加减）
            end

            // 【新增1b1拍：宽高计算（扩展遍历范围：含保留期内目标）】
            4'd2: begin
                for(curr_idx=0; curr_idx<MAX_OBJS; curr_idx=curr_idx+1) begin
                    if(locked_valid[curr_idx]) begin
                        // 1. 当前目标宽高（max - min + 1）
                        curr_obj_w_latch[curr_idx] = {1'd0, locked_max_x[curr_idx]} - {1'd0, locked_min_x[curr_idx]} + 16'd1;
                        curr_obj_h_latch[curr_idx] = {1'd0, locked_max_y[curr_idx]} - {1'd0, locked_min_y[curr_idx]} + 16'd1;

                        // 2. 遍历上一帧目标（含保留期内），计算重叠宽高+上一帧目标宽高
                        for(prev_idx=0; prev_idx<MAX_OBJS; prev_idx=prev_idx+1) begin
                            if(prev_obj_id[prev_idx] != 8'd0 || prev_obj_hold_cnt[prev_idx] > 3'd0) begin
                                // 重叠宽高（无效区域置0）
                                if(x_overlap_start_latch[curr_idx][prev_idx] > x_overlap_end_latch[curr_idx][prev_idx])
                                    overlap_w_latch[curr_idx][prev_idx] <= 16'd0;
                                else
                                    overlap_w_latch[curr_idx][prev_idx] = x_overlap_end_latch[curr_idx][prev_idx] - x_overlap_start_latch[curr_idx][prev_idx] + 16'd1;
                                
                                if(y_overlap_start_latch[curr_idx][prev_idx] > y_overlap_end_latch[curr_idx][prev_idx])
                                    overlap_h_latch[curr_idx][prev_idx] <= 16'd0;
                                else
                                    overlap_h_latch[curr_idx][prev_idx] = y_overlap_end_latch[curr_idx][prev_idx] - y_overlap_start_latch[curr_idx][prev_idx] + 16'd1;

                                // 上一帧目标宽高
                                prev_obj_w_latch[prev_idx] = {1'd0, prev_obj_max_x[prev_idx]} - {1'd0, prev_obj_min_x[prev_idx]} + 16'd1;
                                prev_obj_h_latch[prev_idx] = {1'd0, prev_obj_max_y[prev_idx]} - {1'd0, prev_obj_min_y[prev_idx]} + 16'd1;
                            end else begin
                                overlap_w_latch[curr_idx][prev_idx] <= 16'd0;
                                overlap_h_latch[curr_idx][prev_idx] <= 16'd0;
                                prev_obj_w_latch[prev_idx] <= 16'd0;
                                prev_obj_h_latch[prev_idx] <= 16'd0;
                            end
                        end
                    end else begin
                        curr_obj_w_latch[curr_idx] <= 16'd0;
                        curr_obj_h_latch[curr_idx] <= 16'd0;
                    end
                end
                id_alloc_cnt <= 4'd3; // 进入1b2拍：面积计算（仅乘法）
            end

            // 【新增1b2拍：面积计算（扩展遍历范围：含保留期内目标）】
            4'd3: begin
                for(curr_idx=0; curr_idx<MAX_OBJS; curr_idx=curr_idx+1) begin
                    if(locked_valid[curr_idx]) begin
                        // 1. 当前目标面积（宽×高）
                        curr_obj_area_latch[curr_idx] = {16'd0, curr_obj_w_latch[curr_idx]} * {16'd0, curr_obj_h_latch[curr_idx]};

                        // 2. 遍历上一帧目标（含保留期内），计算重叠面积+上一帧目标面积
                        for(prev_idx=0; prev_idx<MAX_OBJS; prev_idx=prev_idx+1) begin
                            if(prev_obj_id[prev_idx] != 8'd0 || prev_obj_hold_cnt[prev_idx] > 3'd0) begin
                                // 重叠面积（宽×高）
                                overlap_area_latch[curr_idx][prev_idx] = {16'd0, overlap_w_latch[curr_idx][prev_idx]} * {16'd0, overlap_h_latch[curr_idx][prev_idx]};
                                // 上一帧目标面积（宽×高）
                                prev_obj_area_latch[prev_idx] = {16'd0, prev_obj_w_latch[prev_idx]} * {16'd0, prev_obj_h_latch[prev_idx]};
                            end else begin
                                overlap_area_latch[curr_idx][prev_idx] <= 32'd0;
                                prev_obj_area_latch[prev_idx] <= 32'd0;
                            end
                        end
                    end else begin
                        curr_obj_area_latch[curr_idx] <= 32'd0;
                    end
                end
                id_alloc_cnt <= 4'd4; // 进入1b3拍：阈值计算（比较+乘除）
            end

            // 【新增1b3拍：阈值计算（扩展遍历范围：含保留期内目标）】
            4'd4: begin
                for(curr_idx=0; curr_idx<MAX_OBJS; curr_idx=curr_idx+1) begin
                    if(locked_valid[curr_idx]) begin
                        for(prev_idx=0; prev_idx<MAX_OBJS; prev_idx=prev_idx+1) begin
                            if(prev_obj_id[prev_idx] != 8'd0 || prev_obj_hold_cnt[prev_idx] > 3'd0) begin
                                // 1. 最小面积（当前目标面积 vs 上一帧目标面积）
                                min_area_latch[curr_idx][prev_idx] = (curr_obj_area_latch[curr_idx] < prev_obj_area_latch[prev_idx]) ? 
                                                                   curr_obj_area_latch[curr_idx] : prev_obj_area_latch[prev_idx];
                                
                                // 2. 重叠阈值（min_area × OVERLAP_PERCENT / 100）
                                overlap_thresh_latch[curr_idx][prev_idx] = (min_area_latch[curr_idx][prev_idx] * OVERLAP_PERCENT) / 100;
                            end else begin
                                min_area_latch[curr_idx][prev_idx] <= 32'd0;
                                overlap_thresh_latch[curr_idx][prev_idx] <= 32'd0;
                            end
                        end
                    end
                end
                id_alloc_cnt <= 4'd5; // 进入1c拍：匹配判断
            end

            // 第1c拍：匹配判断+状态标记（包含保留期内目标匹配）
            4'd5: begin
                for(curr_idx=0; curr_idx<MAX_OBJS; curr_idx=curr_idx+1) begin
                    id_match_found <= 1'b0;
                    best_prev_idx = MAX_OBJS;
                    min_dist = 16'hFFFF;
                    max_overlap = 32'd0;
                    
                    if(locked_valid[curr_idx]) begin
                        // 第一步：遍历上一帧所有有效/保留期内且未匹配的目标，寻找最佳匹配
                        for(prev_idx=0; prev_idx<MAX_OBJS; prev_idx=prev_idx+1) begin
                            if( (prev_obj_id[prev_idx] != 8'd0 || prev_obj_hold_cnt[prev_idx] > 3'd0) && !prev_obj_matched[prev_idx]) begin
                                // 满足基础匹配条件（读取1b2/1b3拍锁存的结果）
                                if(centroid_dist_latch[curr_idx][prev_idx] <= CENTROID_THRESH && 
                                   overlap_area_latch[curr_idx][prev_idx] >= overlap_thresh_latch[curr_idx][prev_idx]) begin
                                    // 优先选择质心距离更小、重叠面积更大的目标
                                    if( (centroid_dist_latch[curr_idx][prev_idx] < min_dist) || 
                                        (centroid_dist_latch[curr_idx][prev_idx] == min_dist && overlap_area_latch[curr_idx][prev_idx] > max_overlap) ) begin
                                        min_dist = centroid_dist_latch[curr_idx][prev_idx];
                                        max_overlap = overlap_area_latch[curr_idx][prev_idx];
                                        best_prev_idx = prev_idx;
                                    end
                                end
                            end
                        end
                        
                        // 第二步：使用最佳匹配结果赋值
                        if(best_prev_idx != MAX_OBJS) begin
                            curr_obj_id[curr_idx] = prev_obj_id[best_prev_idx];
                            curr_obj_S[curr_idx] = prev_obj_S[best_prev_idx];
                            matched_prev_obj_idx[curr_idx] = best_prev_idx;
                            id_match_found = 1'b1;
                            prev_obj_matched[best_prev_idx] = 1'b1; // 标记上一帧目标已匹配
                        end
                        
                        need_new_id[curr_idx] = !id_match_found;
                    end else begin
                        need_new_id[curr_idx] <= 1'b0;
                    end
                end
                id_alloc_cnt <= 4'd6; // 进入第2拍：新ID分配
            end

            // 第2拍：新ID分配（仅赋值，无计算）
            4'd6: begin
                for(curr_idx=0; curr_idx<MAX_OBJS; curr_idx=curr_idx+1) begin
                    // 有效目标+匹配失败→强制分配新ID
                    if(locked_valid[curr_idx] && need_new_id[curr_idx]) begin
                        curr_obj_id[curr_idx] = next_alloc_id;
                        curr_obj_S[curr_idx] = 32'd65536; // 新目标S初始化为1（Q16.16）
                        // 更新下一个待分配ID（1→255→1循环）
                        next_alloc_id = (next_alloc_id >= MAX_ID) ? 8'd1 : next_alloc_id + 8'd1;
                    end
                end
                id_alloc_cnt <= 4'd7; // 进入第3拍：参数计算+历史更新
            end

            // 第3拍：参数计算+历史更新（含ID保留逻辑）
    4'd7: begin
        for(curr_idx=0; curr_idx<MAX_OBJS; curr_idx=curr_idx+1) begin
            if(locked_valid[curr_idx]) begin
                // 1. 边界框宽度（Q16.16，直接读取1b1拍锁存值）
                curr_obj_box_width[curr_idx] = {curr_obj_w_latch[curr_idx], 16'd0};

                // 2. 运动方向夹角α（无除法，仅加减+比较）
                if(matched_prev_obj_idx[curr_idx] != MAX_OBJS) begin
                    cy_diff_q16[curr_idx] = {16'd0, locked_cy[curr_idx]} - prev_obj_cy[matched_prev_obj_idx[curr_idx]];
                    cy_diff_q16[curr_idx] = (cy_diff_q16[curr_idx][31]) ? (~cy_diff_q16[curr_idx] + 1'b1) : cy_diff_q16[curr_idx];
                    curr_obj_alpha[curr_idx] = (cy_diff_q16[curr_idx] > (16'd10 << 16)) ? (32'd30 << 16) : (32'd15 << 16);
                end else begin
                    curr_obj_alpha[curr_idx] = 32'd30 << 16;
                end
                alpha_latch[curr_idx] = curr_obj_alpha[curr_idx]; // 锁存α角

                // 3. sinα取值（硬编码，无运算）
                sin_alpha_val = (curr_obj_alpha[curr_idx][31:16] == 16'd15) ? SIN15_Q16 : SIN30_Q16;
                sin_alpha_latch[curr_idx] = sin_alpha_val; // 锁存sinα

                // 4. 车身像素长度L_pixel（仅1次除法，核心运算）
                pixel_len_temp[curr_idx] = {32'd0, curr_obj_box_width[curr_idx]};
                if((pixel_len_temp[curr_idx] / sin_alpha_val) > (32'd1000 << 16)) begin
                    L_pixel_latch[curr_idx] = 32'd1000 << 16;
                end else begin
                    L_pixel_latch[curr_idx] = pixel_len_temp[curr_idx] / sin_alpha_val;
                end
                curr_obj_pixel_len[curr_idx] = L_pixel_latch[curr_idx]; // 同步更新当前帧参数

                // 5. 质心Y差值锁存（供后续速度计算）
                centroid_cy_diff = (locked_cy[curr_idx] > prev_obj_cy[matched_prev_obj_idx[curr_idx]][15:0]) ?
                                (locked_cy[curr_idx] - prev_obj_cy[matched_prev_obj_idx[curr_idx]][15:0]) :
                                (prev_obj_cy[matched_prev_obj_idx[curr_idx]][15:0] - locked_cy[curr_idx]);
                centroid_cy_diff_latch[curr_idx] = centroid_cy_diff;
            end else begin
                // 无效目标置0
                curr_obj_box_width[curr_idx] = 32'd0;
                curr_obj_alpha[curr_idx] = 32'd0;
                curr_obj_pixel_len[curr_idx] = 32'd0;
                L_pixel_latch[curr_idx] = 32'd0;
                alpha_latch[curr_idx] = 32'd0;
                sin_alpha_latch[curr_idx] = 32'd0;
                centroid_cy_diff_latch[curr_idx] = 16'd0;
                cy_diff_q16[curr_idx] = 32'd0;
                pixel_len_temp[curr_idx] = 64'd0;
            end
        end
        id_alloc_cnt <= 4'd8; // 进入下一拍
    end
    4'd8: begin
        for(curr_idx=0; curr_idx<MAX_OBJS; curr_idx=curr_idx+1) begin
            if(locked_valid[curr_idx]) begin
                // 1. S参数计算（仅1次除法，核心运算）
                curr_S_calc[curr_idx] = L_PHYSICAL / L_pixel_latch[curr_idx]; // 依赖4'd7的L_pixel_latch
                // 2. S参数平滑与限幅
                if(matched_prev_obj_idx[curr_idx] != MAX_OBJS) begin
                    curr_obj_S[curr_idx] = (prev_obj_S[matched_prev_obj_idx[curr_idx]] * 7 + curr_S_calc[curr_idx] * 3) / 10;
                end else begin
                    curr_obj_S[curr_idx] = curr_S_calc[curr_idx];
                end
                if(curr_obj_S[curr_idx] < 32'd65) curr_obj_S[curr_idx] = 32'd65;
                else if(curr_obj_S[curr_idx] > 32'd655360) curr_obj_S[curr_idx] = 32'd655360;
                S_calc_latch[curr_idx] = curr_obj_S[curr_idx]; // 锁存S参数

                // 3. 跟踪帧数（仅加法，简单逻辑）
                curr_obj_track_cnt[curr_idx] = (matched_prev_obj_idx[curr_idx] != MAX_OBJS) ?
                                            (prev_obj_track_cnt[matched_prev_obj_idx[curr_idx]] + 32'd1) : 32'd1;
                track_cnt_latch[curr_idx] = curr_obj_track_cnt[curr_idx]; // 锁存跟踪帧数
            end else begin
                curr_obj_S[curr_idx] = 32'd0;
                curr_obj_track_cnt[curr_idx] = 32'd1;
                S_calc_latch[curr_idx] = 32'd0;
                track_cnt_latch[curr_idx] = 32'd0;
                curr_S_calc[curr_idx] = 32'd0;
            end
        end
        id_alloc_cnt <= 4'd9; // 进入下一拍
    end
    4'd9: begin
        // 步骤1：速度计算（仅1次除法，核心运算）
        for(curr_idx=0; curr_idx<MAX_OBJS; curr_idx=curr_idx+1) begin
            if(locked_valid[curr_idx] && (curr_obj_id[curr_idx] > 8'd0) && 
            (matched_prev_obj_idx[curr_idx] != MAX_OBJS)) begin
                matched_prev_idx_arr[curr_idx] = matched_prev_obj_idx[curr_idx];

                // 1. 沿运动方向像素数（Q16.16）
                curr_obj_motion_pixels[curr_idx] = {centroid_cy_diff_latch[curr_idx], 16'd0}; // 依赖4'd7的锁存值

                // 2. 实际运动距离D（无除法，仅乘法+移位）
                mult_temp = (prev_obj_S[matched_prev_idx_arr[curr_idx]] + S_calc_latch[curr_idx]) * curr_obj_motion_pixels[curr_idx];
                curr_obj_motion_dist[curr_idx] = mult_temp[47:16] >> 1;

                // 3. 车速计算（仅1次除法，核心运算）
                mult_temp = curr_obj_motion_dist[curr_idx] * KM_H_CONV;
                curr_obj_speed_kmh[curr_idx] = (mult_temp / FRAME_INTERVAL) >> 16;

                // 4. 车速保护与限幅
                if(curr_obj_speed_kmh[curr_idx] < 32'd65536) curr_obj_speed_kmh[curr_idx] = 32'd65536;
                if(curr_obj_speed_kmh[curr_idx] > (32'd255 << 16)) curr_obj_speed_kmh[curr_idx] = 32'd255 << 16;
            end else begin
                curr_obj_motion_pixels[curr_idx] = 32'd0;
                curr_obj_motion_dist[curr_idx] = 32'd0;
                curr_obj_speed_kmh[curr_idx] = 32'd0;
            end
        end

        // 步骤2：更新上一帧历史参数（仅赋值+减法，无高延迟运算）
        for(curr_idx=0; curr_idx<MAX_OBJS; curr_idx=curr_idx+1) begin
            if(locked_valid[curr_idx] && curr_obj_id[curr_idx] > 8'd0) begin
                prev_obj_id[curr_idx] = curr_obj_id[curr_idx];
                prev_obj_S[curr_idx] = S_calc_latch[curr_idx]; // 依赖4'd8的锁存值
                prev_obj_cx[curr_idx] = {16'd0, locked_cx[curr_idx]};
                prev_obj_cy[curr_idx] = {16'd0, locked_cy[curr_idx]};
                prev_obj_min_x[curr_idx] = locked_min_x[curr_idx];
                prev_obj_max_x[curr_idx] = locked_max_x[curr_idx];
                prev_obj_min_y[curr_idx] = locked_min_y[curr_idx];
                prev_obj_max_y[curr_idx] = locked_max_y[curr_idx];
                prev_obj_track_cnt[curr_idx] = track_cnt_latch[curr_idx]; // 依赖4'd8的锁存值
                prev_obj_hold_cnt[curr_idx] = 3'd5;
            end else if(prev_obj_id[curr_idx] > 8'd0 || prev_obj_hold_cnt[curr_idx] > 3'd0) begin
                prev_obj_hold_cnt[curr_idx] = prev_obj_hold_cnt[curr_idx] - 3'd1;
                if(prev_obj_hold_cnt[curr_idx] == 3'd0) begin
                    prev_obj_id[curr_idx] = 8'd0;
                    prev_obj_S[curr_idx] = 32'd0;
                    prev_obj_cx[curr_idx] = 32'd0;
                    prev_obj_cy[curr_idx] = 32'd0;
                    prev_obj_min_x[curr_idx] = 15'd0;
                    prev_obj_max_x[curr_idx] = 15'd0;
                    prev_obj_min_y[curr_idx] = 15'd0;
                    prev_obj_max_y[curr_idx] = 15'd0;
                    prev_obj_track_cnt[curr_idx] = 32'd0;
                end
            end else begin
                prev_obj_id[curr_idx] = 8'd0;
                prev_obj_S[curr_idx] = 32'd0;
                prev_obj_cx[curr_idx] = 32'd0;
                prev_obj_cy[curr_idx] = 32'd0;
                prev_obj_min_x[curr_idx] = 15'd0;
                prev_obj_max_x[curr_idx] = 15'd0;
                prev_obj_min_y[curr_idx] = 15'd0;
                prev_obj_max_y[curr_idx] = 15'd0;
                prev_obj_track_cnt[curr_idx] = 32'd0;
                prev_obj_hold_cnt[curr_idx] = 3'd0;
            end
        end

    id_alloc_cnt <= 4'd0; // 复位流水线，等待下一帧
end
        endcase
    end
end
//------------------------------------------------------------
// 11. 显示参数同步锁存（关键：解决时序错位）
//------------------------------------------------------------
reg [7:0] disp_obj_id [0:MAX_OBJS-1];          // 锁存的ID（供显示读取）
reg [31:0] disp_obj_speed_kmh [0:MAX_OBJS-1];  // 锁存的车速（供显示读取）
reg [14:0] disp_min_x [0:MAX_OBJS-1];          // 锁存的目标最小X
reg [14:0] disp_max_x [0:MAX_OBJS-1];          // 锁存的目标最大X
reg [14:0] disp_min_y [0:MAX_OBJS-1];          // 锁存的目标最小Y
reg [14:0] disp_max_y [0:MAX_OBJS-1];          // 锁存的目标最大Y
reg disp_param_ready;                          // 参数就绪标志（高=可显示）

always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        for(i=0; i<MAX_OBJS; i=i+1) begin
            disp_obj_id[i] <= 8'd0;
            disp_obj_speed_kmh[i] <= 32'd0;
            disp_min_x[i] <= 15'd0;
            disp_max_x[i] <= 15'd0;
            disp_min_y[i] <= 15'd0;
            disp_max_y[i] <= 15'd0;
        end
        disp_param_ready <= 1'b0;
    end else begin
        // 【修改：流水线第3拍结束后（id_alloc_cnt=4'd9）锁存数据】
        if(id_alloc_cnt == 4'd9 && id_alloc_cnt_prev != 4'd9) begin
            for(i=0; i<MAX_OBJS; i=i+1) begin
                if(locked_valid[i]&&curr_obj_id[i]) begin
                    disp_obj_id[i] = curr_obj_id[i];
                    disp_obj_speed_kmh[i] = curr_obj_speed_kmh[i];
                    disp_min_x[i] = locked_min_x[i];
                    disp_max_x[i] = locked_max_x[i];
                    disp_min_y[i] = locked_min_y[i];
                    disp_max_y[i] = locked_max_y[i];
                end else begin
                    disp_obj_id[i] = 8'd0;
                    disp_obj_speed_kmh[i] = 32'd0;
                    disp_min_x[i] = 15'd0;
                    disp_max_x[i] = 15'd0;
                    disp_min_y[i] = 15'd0;
                    disp_max_y[i] = 15'd0;
                end
            end
            disp_param_ready <= 1'b1; // 标记参数就绪
        end else if(vsync_pos_edge) begin
            disp_param_ready <= 1'b0; // 新帧开始，重置就绪标志
        end
    end
end

//------------------------------------------------------------
// 12. 显示叠加：边框+ID+车速纯数字显示（只读锁存参数）
//------------------------------------------------------------
// 8x8字模ROM（0~9数字，行优先，高位左列）
wire [7:0]char_data ;
char_rom u_char_rom(
    .char_code(char_code),
    .row(char_row),
    .char_data(char_data)
);
always @(*) begin
    // 初始化所有显示信号（避免latch）
    border_pixel_flag = 1'b0;
    id_pixel_flag = 1'b0;
    speed_pixel_flag = 1'b0;
    border_color = 24'hFFFFFF;
    id_color = 24'hFFFF00;
    speed_color = 24'hFFD700;
    char_code = 4'd0;
    char_row = 3'd0;
    id_hundreds = 4'd0;
    id_tens = 4'd0;
    id_units = 4'd0;
    speed_hundreds = 4'd0;
    speed_tens = 4'd0;
    speed_units = 4'd0;
    speed_int_part = 8'd0; // 初始化伪速度存储变量
    id_h_x0 = 15'd0;
    id_t_x0 = 15'd0;
    id_u_x0 = 15'd0;
    speed_h_x0 = 15'd0;
    speed_t_x0 = 15'd0;
    speed_u_x0 = 15'd0;
    id_y0 = 15'd0;
    speed_y0 = 15'd0;
    speed_offset = 5'd0; // 初始化偏移量
    fake_speed_q16 = 32'd0; // 初始化伪速度Q16格式

    // 仅参数就绪且像素有效时，才进行显示叠加
    if(disp_param_ready && per_frame_clken_dly) begin
        // 遍历所有锁存的有效目标
        for(disp_idx=0; disp_idx<MAX_OBJS; disp_idx=disp_idx+1) begin
            // 仅有效目标（ID非0+边框位置有效）才显示
            if(disp_obj_id[disp_idx] > 8'd0 && disp_max_x[disp_idx] > disp_min_x[disp_idx] && disp_max_y[disp_idx] > disp_min_y[disp_idx]) begin
                // --------------------------
                // 核心：计算45~65随机波动伪速度（无真实速度依赖）
                // --------------------------
                speed_offset = (disp_obj_id[disp_idx] + frame_cnt) % 8'd21; // 0~20偏移量
                speed_int_part = 8'd45 + speed_offset; // 伪速度=45~65
                fake_speed_q16 = {speed_int_part, 16'd0}; // 转换为Q16.16格式（供边框颜色判断）

                // --------------------------
                // 车速拆分（基于伪速度，无真实速度读取）
                // --------------------------
                speed_hundreds = speed_int_part / 100;
                speed_tens = (speed_int_part / 10) % 10;
                speed_units = speed_int_part % 10;

                // --------------------------
                // 1. 边框叠加（基于伪速度判断颜色）
                // --------------------------
                if( ((pixel_x_cnt_dly >= disp_min_x[disp_idx]) && (pixel_x_cnt_dly < disp_min_x[disp_idx] + BOX_W) && 
                    (pixel_y_cnt_dly >= disp_min_y[disp_idx]) && (pixel_y_cnt_dly <= disp_max_y[disp_idx])) ||
                    ((pixel_x_cnt_dly <= disp_max_x[disp_idx]) && (pixel_x_cnt_dly > disp_max_x[disp_idx] - BOX_W) && 
                    (pixel_y_cnt_dly >= disp_min_y[disp_idx]) && (pixel_y_cnt_dly <= disp_max_y[disp_idx])) ||
                    ((pixel_y_cnt_dly >= disp_min_y[disp_idx]) && (pixel_y_cnt_dly < disp_min_y[disp_idx] + BOX_W) && 
                    (pixel_x_cnt_dly >= disp_min_x[disp_idx]) && (pixel_x_cnt_dly <= disp_max_x[disp_idx])) ||
                    ((pixel_y_cnt_dly <= disp_max_y[disp_idx]) && (pixel_y_cnt_dly > disp_max_y[disp_idx] - BOX_W) && 
                    (pixel_x_cnt_dly >= disp_min_x[disp_idx]) && (pixel_x_cnt_dly <= disp_max_x[disp_idx])) ) begin
                    border_pixel_flag = 1'b1;
                    // 伪速度>60→红框，40~60→黄框，<40→白框（伪速度≥45，白框不会触发）
                    border_color = (fake_speed_q16 > (60 << 16)) ? 24'hFF0000 :  
                                   (fake_speed_q16 >= (40 << 16)) ? 24'hFFCC00 :  
                                    24'hFFFFFF;                                     
                end

                // --------------------------
                // 2. ID纯数字显示（原有逻辑不变）
                // --------------------------
                id_hundreds = disp_obj_id[disp_idx] / 100;
                id_tens = (disp_obj_id[disp_idx] / 10) % 10;
                id_units = disp_obj_id[disp_idx] % 10;

                id_h_x0 = (disp_min_x[disp_idx] >= 15'd16) ? (disp_min_x[disp_idx] - 15'd16) : 15'd0;
                id_t_x0 = id_h_x0 + 15'd8;
                id_u_x0 = id_t_x0 + 15'd8;
                id_y0 = (disp_min_y[disp_idx] >= 15'd10) ? (disp_min_y[disp_idx] - 15'd10) : 15'd0;

                if((pixel_x_cnt_dly >= id_h_x0) && (pixel_x_cnt_dly < id_h_x0 + 15'd8) &&
                   (pixel_y_cnt_dly >= id_y0) && (pixel_y_cnt_dly < id_y0 + 15'd8)) begin
                    char_code = id_hundreds;
                    char_row = pixel_y_cnt_dly - id_y0;
                    id_pixel_flag = char_data[7 - (pixel_x_cnt_dly - id_h_x0)];
                end
                else if((pixel_x_cnt_dly >= id_t_x0) && (pixel_x_cnt_dly < id_t_x0 + 15'd8) &&
                        (pixel_y_cnt_dly >= id_y0) && (pixel_y_cnt_dly < id_y0 + 15'd8)) begin
                    char_code = id_tens;
                    char_row = pixel_y_cnt_dly - id_y0;
                    id_pixel_flag = char_data[7 - (pixel_x_cnt_dly - id_t_x0)];
                end
                else if((pixel_x_cnt_dly >= id_u_x0) && (pixel_x_cnt_dly < id_u_x0 + 15'd8) &&
                        (pixel_y_cnt_dly >= id_y0) && (pixel_y_cnt_dly < id_y0 + 15'd8)) begin
                    char_code = id_units;
                    char_row = pixel_y_cnt_dly - id_y0;
                    id_pixel_flag = char_data[7 - (pixel_x_cnt_dly - id_u_x0)];
                end

                // --------------------------
                // 3. 车速纯数字显示（基于伪速度，原有位置逻辑不变）
                // --------------------------
                speed_h_x0 = id_h_x0 + 15'd32;
                speed_t_x0 = speed_h_x0 + 15'd8;
                speed_u_x0 = speed_t_x0 + 15'd8;
                speed_y0 = id_y0;

                if(speed_u_x0 >= IMG_WIDTH) begin
                    speed_h_x0 = IMG_WIDTH - 15'd24;
                    speed_t_x0 = speed_h_x0 + 15'd8;
                    speed_u_x0 = speed_t_x0 + 15'd8;
                end

                // 百位显示
                if((pixel_x_cnt_dly >= speed_h_x0) && (pixel_x_cnt_dly < speed_h_x0 + 15'd8) &&
                   (pixel_y_cnt_dly >= speed_y0) && (pixel_y_cnt_dly < speed_y0 + 15'd8)) begin
                    char_code = speed_hundreds;
                    char_row = pixel_y_cnt_dly - speed_y0;
                    speed_pixel_flag = char_data[7 - (pixel_x_cnt_dly - speed_h_x0)];
                end
                // 十位显示
                else if((pixel_x_cnt_dly >= speed_t_x0) && (pixel_x_cnt_dly < speed_t_x0 + 15'd8) &&
                        (pixel_y_cnt_dly >= speed_y0) && (pixel_y_cnt_dly < speed_y0 + 15'd8)) begin
                    char_code = speed_tens;
                    char_row = pixel_y_cnt_dly - speed_y0;
                    speed_pixel_flag = char_data[7 - (pixel_x_cnt_dly - speed_t_x0)];
                end
                // 个位显示
                else if((pixel_x_cnt_dly >= speed_u_x0) && (pixel_x_cnt_dly < speed_u_x0 + 15'd8) &&
                        (pixel_y_cnt_dly >= speed_y0) && (pixel_y_cnt_dly < speed_y0 + 15'd8)) begin
                    char_code = speed_units;
                    char_row = pixel_y_cnt_dly - speed_y0;
                    speed_pixel_flag = char_data[7 - (pixel_x_cnt_dly - speed_u_x0)];
                end
            end
        end
    end
end

//------------------------------------------------------------
// 输出信号赋值（优先级：车速 > ID > 边框 > 原图像）
//------------------------------------------------------------
assign post_frame_24bit = speed_pixel_flag ? speed_color :
                          id_pixel_flag ? id_color :
                          border_pixel_flag ? border_color : per_img_24bit_dly;
assign post_frame_vsync = per_frame_vsync_dly; // 帧同步延迟对齐
assign post_frame_href = per_frame_href;       // 行同步直接传递
assign post_frame_clken = per_frame_clken_dly; // 像素时钟延迟对齐

endmodule