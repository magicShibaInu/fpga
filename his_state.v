module his_stat
(
    input  wire                 clk                 ,  // 时钟信号
    input  wire                 rst_n               ,  // 异步复位信号，低电平有效
    
    input  wire                 img_vsync           ,  // 图像场同步信号
    input  wire                 img_href            ,  // 图像行有效信号
    input  wire     [ 7:0]      img_gray            ,  // 输入图像灰度值(0~255)
    
    output reg      [ 7:0]      pixel_level         ,  // 输出像素灰度等级(0~255)
    output reg      [19:0]      pixel_level_acc_num ,  // 输出该灰度等级及以下的累计像素数量
    output reg                  pixel_level_valid     // 输出数据有效标志
);

//----------------------------------------------------------------------
// BRAM相关信号定义（双端口RAM，用于存储各灰度级的像素计数）
wire                            bram_porta_we;        // BRAM A口写使能（1:写，0:读）
wire            [ 7:0]          bram_porta_addr;      // BRAM A口地址
wire            [19:0]          bram_porta_rdata;     // BRAM A口读出数据
wire                            bram_portb_we;        // BRAM B口写使能（1:写，0:读）
wire            [ 7:0]          bram_portb_addr;      // BRAM B口地址
wire            [19:0]          bram_portb_wdata;     // BRAM B口写入数据
wire            [19:0]          bram_portb_rdata;     // BRAM B口读出数据

//----------------------------------------------------------------------
// 输入图像数据预处理：对灰度数据和有效信号进行同步延迟
reg             [7:0]           gray_data_d1;         // 灰度数据延迟1拍

always @(posedge clk)
begin
    gray_data_d1 <= img_gray;  // 对输入灰度值做1拍延迟，用于后续同步处理
end

reg                             gray_valid_d1;        // 灰度有效信号延迟1拍（与gray_data_d1同步）

always @(posedge clk or negedge rst_n)
begin
    if(!rst_n)
        gray_valid_d1 <= 1'b0;
    else
        gray_valid_d1 <= img_href;  // 行有效信号延迟1拍，与灰度数据同步
end

reg                             vsync_d1;             // 场同步信号延迟1拍

always @(posedge clk or negedge rst_n)
begin
    if(!rst_n)
        vsync_d1 <= 1'b0;
    else
        vsync_d1 <= img_vsync;  // 场同步信号延迟1拍，用于检测帧结束
end

wire                            frame_end_flag;       // 帧结束标志（场同步信号下降沿）
assign frame_end_flag = vsync_d1 & ~img_vsync;  // 场同步信号从高变低时，表示一帧结束

//----------------------------------------------------------------------
// 连续相同灰度像素计数：检测连续相同的灰度值并计数（用于优化计数效率）
reg             [7:0]           cont_gray_data;       // 连续灰度数据缓存

always @(posedge clk)
begin
    cont_gray_data <= gray_data_d1;  // 缓存当前灰度值，用于与下一拍比较
end

reg                             cont_gray_valid;      // 连续灰度计数有效标志

always @(posedge clk or negedge rst_n)
begin
    if(!rst_n)
        cont_gray_valid <= 1'b0;
    else
    begin
        if(gray_valid_d1 == 1'b1)  // 行有效期间处理
        begin
            if(cont_gray_valid == 1'b0)
                cont_gray_valid <= 1'b1;  // 初始化为有效
            else
            begin
                // 若当前灰度与上一拍相同，则暂时无效（累计计数后再更新）；否则保持有效
                if(cont_gray_data == gray_data_d1)
                    cont_gray_valid <= 1'b0;
                else
                    cont_gray_valid <= 1'b1;
            end
        end
        else
            cont_gray_valid <= 1'b0;  // 行无效时，计数无效
    end
end

reg             [1:0]           cont_gray_cnt;        // 连续相同灰度像素的计数（1或2，优化连续像素处理）

always @(posedge clk or negedge rst_n)
begin
    if(!rst_n)
        cont_gray_cnt <= 2'd1;
    else
    begin
        // 行有效且连续灰度有效时，若当前与上一拍灰度相同，计数为2（累计2个），否则为1
        if((gray_valid_d1 == 1'b1)&&(cont_gray_valid == 1'b1)&&(cont_gray_data == gray_data_d1))
            cont_gray_cnt <= 2'd2;
        else
            cont_gray_cnt <= 2'd1;
    end
end

reg                             frame_end_flag_d1;    // 帧结束标志延迟1拍

always @(posedge clk or negedge rst_n)
begin
    if(!rst_n)
        frame_end_flag_d1 <= 1'b0;
    else
        frame_end_flag_d1 <= frame_end_flag;  // 帧结束标志延迟1拍，用于同步流水线
end

//----------------------------------------------------------------------
// 流水线第一级（c1）：灰度数据和控制信号延迟同步
reg             [7:0]           gray_data_c1;         // c1级灰度数据

always @(posedge clk)
begin
    gray_data_c1 <= gray_data_d1;  // 灰度数据传入c1级
end

reg                             frame_end_flag_c1;    // c1级帧结束标志
reg                             cont_gray_valid_c1;   // c1级连续灰度有效标志

always @(posedge clk or negedge rst_n)
begin
    if(!rst_n)
    begin
        frame_end_flag_c1       <= 1'b0;
        cont_gray_valid_c1      <= 1'b0;
    end
    else
    begin
        frame_end_flag_c1       <= frame_end_flag_d1;  // 帧结束标志传入c1级
        cont_gray_valid_c1      <= cont_gray_valid;     // 连续灰度有效标志传入c1级
    end
end

//----------------------------------------------------------------------
// 流水线第二级（c2）：延迟3拍，用于BRAM读写同步
reg             [7:0]           gray_data_c2;         // c2级灰度数据

always @(posedge clk)
begin
    gray_data_c2 <= gray_data_c1;  // 灰度数据传入c2级
end

reg                             frame_end_flag_d1_c2; // 帧结束标志延迟1拍（c2级内部）
reg                             frame_end_flag_d2_c2; // 帧结束标志延迟2拍（c2级内部）
reg                             frame_end_flag_c2;    // c2级帧结束标志（总延迟3拍）

always @(posedge clk or negedge rst_n)
begin
    if(!rst_n)
    begin
        frame_end_flag_d1_c2 <= 1'b0;
        frame_end_flag_d2_c2 <= 1'b0;
        frame_end_flag_c2    <= 1'b0;
    end
    else
    begin
        frame_end_flag_d1_c2 <= frame_end_flag_c1;    // 延迟1拍
        frame_end_flag_d2_c2 <= frame_end_flag_d1_c2;  // 延迟2拍
        frame_end_flag_c2    <= frame_end_flag_d2_c2;  // 延迟3拍，用于触发BRAM读操作
    end
end

//----------------------------------------------------------------------
// 流水线第三级（c3）：BRAM读写控制逻辑（帧结束后读取所有灰度级数据）
reg                             bram_rw_flag_c3;      // c3级BRAM读写标志（1:读，0:写）
reg             [8:0]           bram_rw_cnt;          // BRAM读写地址计数器（0~256）

always @(posedge clk or negedge rst_n)
begin
    if(!rst_n)
        bram_rw_flag_c3 <= 1'b0;
    else
    begin
        if(frame_end_flag_c2 == 1'b1)               // 帧结束时，开始读取BRAM
            bram_rw_flag_c3 <= 1'b1;
        else if(bram_rw_cnt == 9'h100)              // 读完256个灰度级后，结束读取
            bram_rw_flag_c3 <= 1'b0;
        else
            bram_rw_flag_c3 <= bram_rw_flag_c3;     // 保持当前状态
    end
end

reg             [8:0]           bram_rw_cnt_d1;       // 地址计数器延迟1拍

always @(posedge clk)
begin
    bram_rw_cnt_d1 <= bram_rw_cnt;  // 计数器延迟1拍，用于组合逻辑计数
end

always @(*)
begin
    if(bram_rw_flag_c3 == 1'b1)      // 读取阶段，计数器递增（0~255）
        bram_rw_cnt <= bram_rw_cnt_d1 + 1'b1;
    else
        bram_rw_cnt <= 9'b0;         // 非读取阶段，计数器清零
end

wire            [7:0]           bram_addr_c3;         // c3级BRAM地址
assign bram_addr_c3 = bram_rw_cnt - 1'b1;  // 地址为计数器值减1（0~255）

//----------------------------------------------------------------------
// 流水线第四级（c4）：BRAM地址和控制信号延迟同步
reg                             bram_rw_flag_c4;      // c4级BRAM读写标志

always @(posedge clk or negedge rst_n)
begin
    if(!rst_n)
        bram_rw_flag_c4 <= 1'b0;
    else
        bram_rw_flag_c4 <= bram_rw_flag_c3;  // 读写标志传入c4级
end

reg             [7:0]           bram_addr_c4;         // c4级BRAM地址

always @(posedge clk)
begin
    bram_addr_c4 <= bram_addr_c3;  // 地址传入c4级
end

//----------------------------------------------------------------------
// 流水线第五级（c5）：读取BRAM数据，获取各灰度级的像素数量
reg             [7:0]           pixel_level_c5;       // c5级像素灰度等级

always @(posedge clk)
begin
    pixel_level_c5 <= bram_addr_c4;  // 地址即灰度等级（0~255）
end

reg             [19:0]          pixel_level_num_c5;   // c5级该灰度级的像素数量

always @(posedge clk)
begin
    if(bram_rw_flag_c4 == 1'b1)       // 读取阶段，从BRAM B口获取当前灰度级的计数
        pixel_level_num_c5 <= bram_portb_rdata;
    else
        pixel_level_num_c5 <= 20'b0;  // 非读取阶段，计数清零
end

reg                             pixel_level_valid_c5; // c5级输出有效标志

always @(posedge clk or negedge rst_n)
begin
    if(!rst_n)
        pixel_level_valid_c5 <= 1'b0;
    else
        pixel_level_valid_c5 <= bram_rw_flag_c4;  // 读写标志即数据有效标志
end

//----------------------------------------------------------------------
// 流水线第六级（c6）：计算灰度级累计数量（当前及以下所有等级的像素和）
reg             [7:0]           pixel_level_c6;       // c6级像素灰度等级

always @(posedge clk)
begin
    pixel_level_c6 <= pixel_level_c5;  // 灰度等级传入c6级
end

reg             [19:0]          pixel_level_acc_num_c6; // c6级累计像素数量

always @(posedge clk)
begin
    if(pixel_level_valid_c5 == 1'b1)  // 数据有效时计算累计
    begin
        if(pixel_level_c5 == 8'b0)    // 灰度级0时，累计值为自身计数
            pixel_level_acc_num_c6 <= pixel_level_num_c5;
        else                          // 非0级时，累计值为上一级累计+当前计数
            pixel_level_acc_num_c6 <= pixel_level_acc_num_c6 + pixel_level_num_c5;
    end
    else
        pixel_level_acc_num_c6 <= pixel_level_acc_num_c6;  // 数据无效时保持
end

reg                             pixel_level_valid_c6; // c6级输出有效标志

always @(posedge clk or negedge rst_n)
begin
    if(!rst_n)
        pixel_level_valid_c6 <= 1'b0;
    else
        pixel_level_valid_c6 <= pixel_level_valid_c5;  // 有效标志传入c6级
end

//----------------------------------------------------------------------
// 输出信号赋值：将流水线最后一级数据输出
always @(posedge clk)
begin
    pixel_level         <= pixel_level_c6;         // 输出灰度等级
    pixel_level_acc_num <= pixel_level_acc_num_c6; // 输出累计像素数量
end

always @(posedge clk or negedge rst_n)
begin
    if(!rst_n)
        pixel_level_valid <= 1'b0;
    else
        pixel_level_valid <= pixel_level_valid_c6; // 输出有效标志
end

//----------------------------------------------------------------------
// BRAM接口信号赋值：双端口RAM控制逻辑
// A口：读取阶段用于读数据（实际未写入，dina恒为0）
// B口：图像输入阶段用于累加计数，读取阶段用于输出数据
assign bram_porta_we  = bram_rw_flag_c4;                           // A口写使能（读取阶段有效）
assign bram_porta_addr = (bram_rw_flag_c4 == 1'b1) ? bram_addr_c4 : cont_gray_data; // A口地址（读阶段用c4地址，写阶段用连续灰度数据）
assign bram_portb_we  = cont_gray_valid_c1;                        // B口写使能（连续灰度有效时写）
assign bram_portb_addr = (bram_rw_flag_c3 == 1'b1) ? bram_addr_c3 : gray_data_c2;  // B口地址（读阶段用c3地址，写阶段用c2级灰度数据）
assign bram_portb_wdata = bram_porta_rdata + cont_gray_cnt;         // B口写入数据（当前计数+连续像素数）

//----------------------------------------------------------------------
// 双端口BRAM例化：用于存储各灰度级（0~255）的像素数量
// 端口A：读操作（配合端口B完成累加）
// 端口B：写操作（累加计数）和读操作（输出计数结果）
blk_mem_gen_2 u_blk_mem_gen_2 (
    // ---------- 端口A ----------
    .clka   (clk),                  // 时钟信号
    .ena    (1'b1),                 // 始终使能
    .wea    (bram_porta_we),        // 写使能（A口）
    .addra  (bram_porta_addr),      // 地址（A口）
    .dina   (20'b0),                // 写入数据（A口，未使用，恒为0）
    .douta  (bram_porta_rdata),     // 读出数据（A口）

    // ---------- 端口B ----------
    .clkb   (clk),                  // 时钟信号（与A口同频同相）
    .enb    (1'b1),                 // 始终使能
    .web    (bram_portb_we),        // 写使能（B口）
    .addrb  (bram_portb_addr),      // 地址（B口）
    .dinb   (bram_portb_wdata),     // 写入数据（B口）
    .doutb  (bram_portb_rdata)      // 读出数据（B口）
);

endmodule    