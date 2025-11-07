module data_segment (
    input  wire                        clk,        // 系统时钟
    input  wire                        rst_n,      // 复位信号（低有效）
    input  wire                        rx_done,    // 接收完成标志（来自uart_rx）
    input  wire [45:0]                 rx_data,    // 接收的原始数据（新增3个数据后，总位宽46位）
    output reg                         en,         // 使能信号（1位，保持不变）
    output reg  [3:0]                  state_sel,  // 状态选择信号（4位，保持不变）
    output reg  [7:0]                  data1,      // 第一个数据（8位，保持不变）
    output reg  [7:0]                  data2,      // 第二个数据（8位，保持不变）
    output reg  [5:0]                  data3,      // 新增：第三个数据（6位）
    output reg  [6:0]                  data4,      // 新增：第四个数据（7位）
    output reg  [11:0]                 data5,      // 新增：第五个数据（12位）
    output reg                         seg_done    // 分段完成标志（保持不变）
);

// 数据分段位宽定义（更新总位宽，新增3个数据的位宽参数）
localparam EN_WIDTH      = 1;     // 使能信号位宽（不变）
localparam STATE_WIDTH   = 4;     // 状态选择位宽（不变）
localparam DATA1_WIDTH   = 8;     // 第一个数据位宽（不变）
localparam DATA2_WIDTH   = 8;     // 第二个数据位宽（不变）
localparam DATA3_WIDTH   = 6;     // 新增：第三个数据位宽
localparam DATA4_WIDTH   = 7;     // 新增：第四个数据位宽
localparam DATA5_WIDTH   = 12;    // 新增：第五个数据位宽
localparam DATA_WIDTH    = EN_WIDTH + STATE_WIDTH + DATA1_WIDTH + DATA2_WIDTH + DATA3_WIDTH + DATA4_WIDTH + DATA5_WIDTH; // 总位宽：1+4+8+8+6+7+12=46

// 数据分段逻辑（按“高位到低位”顺序拆分46位数据，新增3个数据的截取逻辑）
// 数据结构定义：[en(1位) | state_sel(4位) | data1(8位) | data2(8位) | data3(6位) | data4(7位) | data5(12位)]
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        // 复位时所有输出清零（包含新增的3个数据）
        en        <= 1'b0;
        state_sel <= 4'b0000;
        data1     <= 8'b0000_0000;
        data2     <= 8'b0000_0000;
        data3     <= 6'b00_0000;
        data4     <= 7'b000_0000;
        data5     <= 12'b0000_0000_0000;
        seg_done  <= 1'b0;
    end else begin
        seg_done <= 1'b0;  // 默认拉低完成标志，避免持续有效
        if (rx_done) begin  // 仅在接收完成时执行数据拆分
            // 1. 截取使能信号（最高1位：45bit）
            en        <= rx_data[DATA_WIDTH-1 : DATA_WIDTH-EN_WIDTH];
            // 2. 截取状态选择信号（接下来4位：44~41bit）
            state_sel <= rx_data[DATA_WIDTH-EN_WIDTH-1 : DATA_WIDTH-EN_WIDTH-STATE_WIDTH];
            // 3. 截取第一个数据（接下来8位：40~33bit）
            data1     <= rx_data[DATA_WIDTH-EN_WIDTH-STATE_WIDTH-1 : DATA_WIDTH-EN_WIDTH-STATE_WIDTH-DATA1_WIDTH];
            // 4. 截取第二个数据（接下来8位：32~25bit）
            data2     <= rx_data[DATA_WIDTH-EN_WIDTH-STATE_WIDTH-DATA1_WIDTH-1 : DATA_WIDTH-EN_WIDTH-STATE_WIDTH-DATA1_WIDTH-DATA2_WIDTH];
            // 5. 新增：截取第三个数据（接下来6位：24~19bit）
            data3     <= rx_data[DATA_WIDTH-EN_WIDTH-STATE_WIDTH-DATA1_WIDTH-DATA2_WIDTH-1 : DATA_WIDTH-EN_WIDTH-STATE_WIDTH-DATA1_WIDTH-DATA2_WIDTH-DATA3_WIDTH];
            // 6. 新增：截取第四个数据（接下来7位：18~12bit）
            data4     <= rx_data[DATA_WIDTH-EN_WIDTH-STATE_WIDTH-DATA1_WIDTH-DATA2_WIDTH-DATA3_WIDTH-1 : DATA_WIDTH-EN_WIDTH-STATE_WIDTH-DATA1_WIDTH-DATA2_WIDTH-DATA3_WIDTH-DATA4_WIDTH];
            // 7. 新增：截取第五个数据（最低12位：11~0bit）
            data5     <= rx_data[DATA5_WIDTH-1 : 0];
            
            seg_done  <= 1'b1;  // 置位分段完成标志，通知下游模块取数
        end
    end
end

endmodule