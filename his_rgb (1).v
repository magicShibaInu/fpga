

module His_RGB_Top(
    input               clk,
    input               rst_n,

    // 输入图像信号
    input               per_img_vsync,
    input               per_img_href,
    input      [23:0]   per_img_rgb,     // {R,G,B}
    
    // 输出图像信号
    output              post_img_vsync,
    output              post_img_href,
    output     [23:0]   post_img_rgb     // {R,G,B}
);

    //------------------------------------------
    // 分离RGB通道
    //------------------------------------------
    wire [7:0] per_img_r = per_img_rgb[23:16];
    wire [7:0] per_img_g = per_img_rgb[15:8];
    wire [7:0] per_img_b = per_img_rgb[7:0];

    //------------------------------------------
    // R通道直方图均衡化
    //------------------------------------------
    wire [7:0] post_r;
    His_Top u_vh_r (
        .clk            (clk),
        .rst_n          (rst_n),
        .per_img_vsync  (per_img_vsync),
        .per_img_href   (per_img_href),
        .per_img_gray   (per_img_r),
        .post_img_vsync (post_img_vsync),
        .post_img_href  (post_img_href),
        .post_img_gray  (post_r)
    );

    //------------------------------------------
    // G通道直方图均衡化
    //------------------------------------------
    wire [7:0] post_g;
    His_Top u_vh_g (
        .clk            (clk),
        .rst_n          (rst_n),
        .per_img_vsync  (per_img_vsync),
        .per_img_href   (per_img_href),
        .per_img_gray   (per_img_g),
        .post_img_vsync (), // 同步信号只保留一份
        .post_img_href  (),
        .post_img_gray  (post_g)
    );

    //------------------------------------------
    // B通道直方图均衡化
    //------------------------------------------
    wire [7:0] post_b;
    His_Top u_vh_b (
        .clk            (clk),
        .rst_n          (rst_n),
        .per_img_vsync  (per_img_vsync),
        .per_img_href   (per_img_href),
        .per_img_gray   (per_img_b),
        .post_img_vsync (),
        .post_img_href  (),
        .post_img_gray  (post_b)
    );

    //------------------------------------------
    // 合并输出
    //------------------------------------------
    assign post_img_rgb = {post_r, post_g, post_b};

endmodule
