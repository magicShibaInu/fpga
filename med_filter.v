//基于暗通道先验的图像去雾

//VIP 算法--中值滤波，消耗四个时钟周期
module VIP_Gray_Median_Filter #(
    parameter   [10:0]   IMG_HDISP = 11'd800 ,
    parameter   [10:0]   IMG_VDISP = 11'd600
)
(
    //global clk
    input           clk,
    input           rst_n,
    
    //Image data prepared to be processed
    input               per_frame_vsync ,
    input               per_frame_href  ,
    input               per_frame_clken ,
    input       [7:0]   per_img_Y       ,
    
    //Image data has been processed
    output              post_frame_vsync,
    output              post_frame_href ,
    output              post_frame_clken,
    output      [7:0]   post_img_Y
);
wire        matrix_frame_vsync;
wire        matrix_frame_href ;
wire        matrix_frame_clken;
wire [7:0]  matrix_p11  ;  //3x3窗口像素：p11-p33
wire [7:0]  matrix_p12  ;
wire [7:0]  matrix_p13  ;
wire [7:0]  matrix_p21  ;
wire [7:0]  matrix_p22  ;
wire [7:0]  matrix_p23  ;
wire [7:0]  matrix_p31  ;
wire [7:0]  matrix_p32  ;
wire [7:0]  matrix_p33  ;

//行排序结果：每行的min、mid、max
reg  [7:0]  r1_min, r1_mid, r1_max;
reg  [7:0]  r2_min, r2_mid, r2_max;
reg  [7:0]  r3_min, r3_mid, r3_max;

//中间列排序结果：用于取中值
reg  [7:0]  c2_min, c2_mid, c2_max;

//同步信号延迟（与数据延迟匹配）
reg  [1:0]  post0_frame_vsync ;
reg  [1:0]  post0_frame_href ;
reg  [1:0]  post0_frame_clken;
reg  [7:0]  post0_img_Y      ;

//3x3矩阵生成模块（复用，无需修改）
vip_matrix_generate_3x3_8bit u_vip_matrix_generate_3x3_8bit(
    .clk                 (clk),    
    .rst_n               (rst_n),
    .per_frame_vsync     (per_frame_vsync),
    .per_frame_href      (per_frame_href),
    .per_frame_clken     (per_frame_clken),
    .per_img_y           (per_img_Y),
    .matrix_frame_vsync  (matrix_frame_vsync),
    .matrix_frame_href   (matrix_frame_href),
    .matrix_frame_clken  (matrix_frame_clken),
    .matrix_p11          (matrix_p11),
    .matrix_p12          (matrix_p12),
    .matrix_p13          (matrix_p13),
    .matrix_p21          (matrix_p21),
    .matrix_p22          (matrix_p22),
    .matrix_p23          (matrix_p23),
    .matrix_p31          (matrix_p31),
    .matrix_p32          (matrix_p32),
    .matrix_p33          (matrix_p33)
);

//第一步：对3x3窗口的每行进行排序，得到每行的min、mid、max
//第一行排序（p11, p12, p13）
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        r1_min <= 8'd0;
        r1_mid <= 8'd0;
        r1_max <= 8'd0;
    end else begin
        if (matrix_p11 <= matrix_p12) begin  //先比较p11和p12
            if (matrix_p13 <= matrix_p11) begin  //p13 <= p11 <= p12
                r1_min <= matrix_p13;
                r1_mid <= matrix_p11;
                r1_max <= matrix_p12;
            end else if (matrix_p13 >= matrix_p12) begin  //p11 <= p12 <= p13
                r1_min <= matrix_p11;
                r1_mid <= matrix_p12;
                r1_max <= matrix_p13;
            end else begin  //p11 <= p13 <= p12
                r1_min <= matrix_p11;
                r1_mid <= matrix_p13;
                r1_max <= matrix_p12;
            end
        end else begin  //p12 < p11
            if (matrix_p13 <= matrix_p12) begin  //p13 <= p12 < p11
                r1_min <= matrix_p13;
                r1_mid <= matrix_p12;
                r1_max <= matrix_p11;
            end else if (matrix_p13 >= matrix_p11) begin  //p12 < p11 <= p13
                r1_min <= matrix_p12;
                r1_mid <= matrix_p11;
                r1_max <= matrix_p13;
            end else begin  //p12 < p13 < p11
                r1_min <= matrix_p12;
                r1_mid <= matrix_p13;
                r1_max <= matrix_p11;
            end
        end
    end
end

//第二行排序（p21, p22, p23）
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        r2_min <= 8'd0;
        r2_mid <= 8'd0;
        r2_max <= 8'd0;
    end else begin
        if (matrix_p21 <= matrix_p22) begin  //先比较p21和p22
            if (matrix_p23 <= matrix_p21) begin  //p23 <= p21 <= p22
                r2_min <= matrix_p23;
                r2_mid <= matrix_p21;
                r2_max <= matrix_p22;
            end else if (matrix_p23 >= matrix_p22) begin  //p21 <= p22 <= p23
                r2_min <= matrix_p21;
                r2_mid <= matrix_p22;
                r2_max <= matrix_p23;
            end else begin  //p21 <= p23 <= p22
                r2_min <= matrix_p21;
                r2_mid <= matrix_p23;
                r2_max <= matrix_p22;
            end
        end else begin  //p22 < p21
            if (matrix_p23 <= matrix_p22) begin  //p23 <= p22 < p21
                r2_min <= matrix_p23;
                r2_mid <= matrix_p22;
                r2_max <= matrix_p21;
            end else if (matrix_p23 >= matrix_p21) begin  //p22 < p21 <= p23
                r2_min <= matrix_p22;
                r2_mid <= matrix_p21;
                r2_max <= matrix_p23;
            end else begin  //p22 < p23 < p21
                r2_min <= matrix_p22;
                r2_mid <= matrix_p23;
                r2_max <= matrix_p21;
            end
        end
    end
end

//第三行排序（p31, p32, p33）
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        r3_min <= 8'd0;
        r3_mid <= 8'd0;
        r3_max <= 8'd0;
    end else begin
        if (matrix_p31 <= matrix_p32) begin  //先比较p31和p32
            if (matrix_p33 <= matrix_p31) begin  //p33 <= p31 <= p32
                r3_min <= matrix_p33;
                r3_mid <= matrix_p31;
                r3_max <= matrix_p32;
            end else if (matrix_p33 >= matrix_p32) begin  //p31 <= p32 <= p33
                r3_min <= matrix_p31;
                r3_mid <= matrix_p32;
                r3_max <= matrix_p33;
            end else begin  //p31 <= p33 <= p32
                r3_min <= matrix_p31;
                r3_mid <= matrix_p33;
                r3_max <= matrix_p32;
            end
        end else begin  //p32 < p31
            if (matrix_p33 <= matrix_p32) begin  //p33 <= p32 < p31
                r3_min <= matrix_p33;
                r3_mid <= matrix_p32;
                r3_max <= matrix_p31;
            end else if (matrix_p33 >= matrix_p31) begin  //p32 < p31 <= p33
                r3_min <= matrix_p32;
                r3_mid <= matrix_p31;
                r3_max <= matrix_p33;
            end else begin  //p32 < p33 < p31
                r3_min <= matrix_p32;
                r3_mid <= matrix_p33;
                r3_max <= matrix_p31;
            end
        end
    end
end

//第二步：对每行的中间值（r1_mid, r2_mid, r3_mid）组成的列排序，取中间值为中值
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        c2_min <= 8'd0;
        c2_mid <= 8'd0;
        c2_max <= 8'd0;
    end else begin
        if (r1_mid <= r2_mid) begin  //先比较r1_mid和r2_mid
            if (r3_mid <= r1_mid) begin  //r3_mid <= r1_mid <= r2_mid
                c2_min <= r3_mid;
                c2_mid <= r1_mid;
                c2_max <= r2_mid;
            end else if (r3_mid >= r2_mid) begin  //r1_mid <= r2_mid <= r3_mid
                c2_min <= r1_mid;
                c2_mid <= r2_mid;
                c2_max <= r3_mid;
            end else begin  //r1_mid <= r3_mid <= r2_mid
                c2_min <= r1_mid;
                c2_mid <= r3_mid;
                c2_max <= r2_mid;
            end
        end else begin  //r2_mid < r1_mid
            if (r3_mid <= r2_mid) begin  //r3_mid <= r2_mid < r1_mid
                c2_min <= r3_mid;
                c2_mid <= r2_mid;
                c2_max <= r1_mid;
            end else if (r3_mid >= r1_mid) begin  //r2_mid < r1_mid <= r3_mid
                c2_min <= r2_mid;
                c2_mid <= r1_mid;
                c2_max <= r3_mid;
            end else begin  //r2_mid < r3_mid < r1_mid
                c2_min <= r2_mid;
                c2_mid <= r3_mid;
                c2_max <= r1_mid;
            end
        end
    end
end

//中值结果赋值（c2_mid为3x3窗口的中值）
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        post0_img_Y <= 8'd0;
    end else begin
        post0_img_Y <= c2_mid;
    end
end

//同步信号延迟2拍（与数据路径延迟匹配）
always@(posedge clk) begin
    post0_frame_vsync <= {post0_frame_vsync[0], matrix_frame_vsync};
    post0_frame_href  <= {post0_frame_href[0], matrix_frame_href};
    post0_frame_clken <= {post0_frame_clken[0], matrix_frame_clken};
end

//输出赋值
assign post_img_Y       = post0_img_Y;
assign post_frame_vsync = post0_frame_vsync[1];
assign post_frame_href  = post0_frame_href[1];  
assign post_frame_clken = post0_frame_clken[1]; 
       
endmodule