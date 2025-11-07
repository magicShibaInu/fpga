module key_debounce(
    input  wire clk,        // 系统时钟，建议用 pixelclk
    input  wire rst_n,      // 复位，低有效
    input  wire key_in,     // 按键输入（低有效）
    output reg  key_fall    // 输出下降沿触发脉冲，高电平一个时钟周期
);

reg [15:0] cnt;
reg key_sync0, key_sync1;
reg key_state;

always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        key_sync0 <= 1'b1;
        key_sync1 <= 1'b1;
        key_state <= 1'b1;
        cnt <= 16'd0;
        key_fall <= 1'b0;
    end else begin
        // 同步按键到clk域
        key_sync0 <= key_in;
        key_sync1 <= key_sync0;

        // 消抖
        if(key_sync1 == key_state) begin
            cnt <= 16'd0;
            key_fall <= 1'b0;
        end else begin
            cnt <= cnt + 1'b1;
            if(cnt == 16'hffff) begin
                key_state <= key_sync1;
                key_fall <= (key_state == 1'b1 && key_sync1 == 1'b0) ? 1'b1 : 1'b0; // 检测下降沿
                cnt <= 16'd0;
            end else begin
                key_fall <= 1'b0;
            end
        end
    end
end

endmodule
