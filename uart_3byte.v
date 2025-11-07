module uart_6byte_rx(
    input                clk,              // 50MHz时钟
    input                reset_n,          // 复位信号，低有效
    input        [2:0]   baud_set,         // 波特率设置（与发送端一致，9600对应0）
    input                uart_rx,          // 串口接收线
    
    output       [45:0]  data_46bit,       // 组合后的46位数据（适配新增3个数据后的总位宽）
    output               rx_6byte_done     // 6字节接收完成标志（原3字节改为6字节，满足46位存储）
);

// 中间信号定义
wire          [7:0]   byte_data;         // 单字节接收数据（单字节接收模块输出）
wire                  byte_done;         // 单字节接收完成标志（单字节接收模块输出）
reg           [7:0]   byte0, byte1, byte2, byte3, byte4, byte5; // 存储6个接收字节（原3个扩展为6个）
reg           [2:0]   byte_cnt;          // 接收字节计数器（0~5，原0~2扩展为6字节计数）
reg                   rx_6byte_done_reg; // 6字节完成标志寄存器（原3字节标志对应修改）
reg                   byte_done_prev;    // 单字节完成信号的前一拍（用于检测上升沿，避免重复计数）

// 1. 实例化单字节UART接收模块（保持不变，仅需增加后续字节存储和计数）
uart_byte_rx uart_byte_rx_inst(
    .clk(clk),
    .reset_n(reset_n),
    .baud_set(baud_set),
    .uart_rx(uart_rx),
    .data_byte(byte_data),
    .rx_done(byte_done)
);

// 2. 检测byte_done的上升沿（避免单字节完成信号持续高电平时重复计数）
always @(posedge clk or negedge reset_n) begin
    if(!reset_n)
        byte_done_prev <= 1'b0;
    else
        byte_done_prev <= byte_done; // 延迟1拍，用于捕捉上升沿
end
wire byte_done_posedge = byte_done & ~byte_done_prev; // 上升沿检测结果（仅在单字节刚完成时为1）

// 3. 字节计数与数据存储（原3字节扩展为6字节，对应存储byte0~byte5）
always @(posedge clk or negedge reset_n) begin
    if(!reset_n) begin
        byte_cnt <= 3'd0;          // 计数器复位为0
        byte0 <= 8'd0;             // 6个字节存储寄存器全部清零
        byte1 <= 8'd0;
        byte2 <= 8'd0;
        byte3 <= 8'd0;
        byte4 <= 8'd0;
        byte5 <= 8'd0;
    end else if(byte_done_posedge) begin // 仅在单字节刚接收完成时，更新计数和存储
        case(byte_cnt)
            3'd0: begin // 接收第1个字节（最高位字节，对应46位数据的47~40bit）
                byte0 <= byte_data;
                byte_cnt <= 3'd1;
            end
            3'd1: begin // 接收第2个字节（对应46位数据的39~32bit）
                byte1 <= byte_data;
                byte_cnt <= 3'd2;
            end
            3'd2: begin // 接收第3个字节（对应46位数据的31~24bit）
                byte2 <= byte_data;
                byte_cnt <= 3'd3;
            end
            3'd3: begin // 接收第4个字节（对应46位数据的23~16bit）
                byte3 <= byte_data;
                byte_cnt <= 3'd4;
            end
            3'd4: begin // 接收第5个字节（对应46位数据的15~8bit）
                byte4 <= byte_data;
                byte_cnt <= 3'd5;
            end
            3'd5: begin // 接收第6个字节（最低位字节，对应46位数据的7~0bit）
                byte5 <= byte_data;
                byte_cnt <= 3'd0; // 接收完6字节后，计数器复位，准备下一轮
            end
            default: byte_cnt <= 3'd0; // 异常情况复位计数
        endcase
    end
end

// 4. 6字节接收完成标志（仅在收到第6个字节时置位1个时钟周期，通知下游模块取数）
always @(posedge clk or negedge reset_n) begin
    if(!reset_n)
        rx_6byte_done_reg <= 1'b0;
    else
        // 仅当第6个字节（byte_cnt=5时）接收完成，才置位完成标志
        rx_6byte_done_reg <= (byte_done_posedge && byte_cnt == 3'd5);
end
assign rx_6byte_done = rx_6byte_done_reg;

// 5. 组合6字节为48位，取低46位作为最终输出（适配data_segment模块的46位数据结构）
// 数据打包规则（与发送端对应）：6字节 = [byte0(8bit) | byte1(8bit) | byte2(8bit) | byte3(8bit) | byte4(8bit) | byte5(8bit)]
// 48位数据中，低46位即为目标数据（高2位无效，因46位<48位）
wire [47:0] data_48bit = {byte0, byte1, byte2, byte3, byte4, byte5}; // 拼接6字节为48位
assign data_46bit = data_48bit[45:0]; // 取低46位，匹配新增数据后的总位宽

endmodule