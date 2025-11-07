module hisproc#
(parameter IMG_TOTAL = 480000) // 总像素数，例如 800*600)
(
    input  wire                 clk,
    input  wire                 rst_n,
    
    input  wire     [ 7:0]      pixel_level,         // 原像素灰度
    input  wire     [19:0]      pixel_level_acc_num, // 累积像素数(CDF)
    input  wire                 pixel_level_valid,
    output reg                  histEQ_start_flag,
    
    input  wire                 per_img_vsync,
    input  wire                 per_img_href,
    input  wire     [ 7:0]      per_img_gray,       // 输入图像灰度
    
    output wire                 post_img_vsync,
    output wire                 post_img_href,
    output wire     [ 7:0]      post_img_gray
);



//----------------------------------------------------------------------
//  BRAM 接口信号
wire                            bram_a_wenb;
wire            [ 7:0]          bram_a_addr;
wire            [19:0]          bram_a_wdata;
wire            [7:0]           bram_b_addr;
wire            [19:0]          bram_b_rdata;

assign bram_a_wenb  = pixel_level_valid;
assign bram_a_addr  = pixel_level;
assign bram_a_wdata = pixel_level_acc_num;
assign bram_b_addr  = per_img_gray;

//======================================================================
// 使用 Vivado Block Memory Generator (blk_mem_gen_2)
//======================================================================
blk_mem_gen_2 u_blk_mem_gen_2 (
    // ---------- Port A ----------
    .clka   (clk),                  // input wire clka
    .ena    (1'b1),                 // always enable
    .wea    (bram_a_wenb),          // write enable for port A
    .addra  (bram_a_addr),          // address A
    .dina   (bram_a_wdata),         // write data A
    .douta  (),                     // not used (we only write here)

    // ---------- Port B ----------
    .clkb   (clk),                  // same clock
    .enb    (1'b1),                 // always enable
    .web    (1'b0),                 // Port B is read-only
    .addrb  (bram_b_addr),          // address B
    .dinb   (20'b0),                // no write
    .doutb  (bram_b_rdata)          // read data
);

//----------------------------------------------------------------------
//  histEQ 开始标志
always @(posedge clk or negedge rst_n)
begin
    if(!rst_n)
        histEQ_start_flag <= 1'b0;
    else
        histEQ_start_flag <= (pixel_level_valid && (pixel_level == 8'd255));
end

//----------------------------------------------------------------------
//  LUT 归一化计算
// pixel_new = round(CumPixel / 总像素数 * 255)
reg [7:0] pixel_data;

always @(posedge clk)
begin
    // 这里做 CDF 归一化：CDF/IMG_TOTAL * 255
    pixel_data <= (bram_b_rdata * 255 + (IMG_TOTAL >> 1)) / IMG_TOTAL;
end

//----------------------------------------------------------------------
//  延迟同步输入信号
reg [2:0] per_img_vsync_r;
reg [2:0] per_img_href_r;

always @(posedge clk or negedge rst_n)
begin
    if(!rst_n)
    begin
        per_img_vsync_r <= 3'b0;
        per_img_href_r  <= 3'b0;
    end
    else
    begin
        per_img_vsync_r <= {per_img_vsync_r[1:0], per_img_vsync};
        per_img_href_r  <= {per_img_href_r[1:0], per_img_href};
    end
end

//----------------------------------------------------------------------
//  输出均衡化图像
assign post_img_vsync = per_img_vsync_r[2];
assign post_img_href  = per_img_href_r[2];
assign post_img_gray  = pixel_data;

endmodule
