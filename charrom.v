`timescale 1ns / 1ps
// 标准8x8数字字模ROM（行优先，正序显示，0~9）
module char_rom(
    input  [3:0]  char_code,  // 字符编码（0~9）
    input  [2:0]  row,        // 字符行号（0~7，对应字模的8行）
    output reg [7:0] char_data // 该行的8列像素（1=亮，0=灭）
);

// 字模数据：每个数字8行，每行8列（16进制表示，高位对应左列，低位对应右列）
always @(*) begin
    case(char_code)
        4'd0: case(row) // 数字0
            3'd0: char_data = 8'b00111100;
            3'd1: char_data = 8'b01000010;
            3'd2: char_data = 8'b01000010;
            3'd3: char_data = 8'b01000010;
            3'd4: char_data = 8'b01000010;
            3'd5: char_data = 8'b01000010;
            3'd6: char_data = 8'b01000010;
            3'd7: char_data = 8'b00111100;
        endcase
        4'd1: case(row) // 数字1
            3'd0: char_data = 8'b00011000;
            3'd1: char_data = 8'b00111000;
            3'd2: char_data = 8'b01011000;
            3'd3: char_data = 8'b00011000;
            3'd4: char_data = 8'b00011000;
            3'd5: char_data = 8'b00011000;
            3'd6: char_data = 8'b00011000;
            3'd7: char_data = 8'b01111110;
        endcase
        4'd2: case(row) // 数字2
            3'd0: char_data = 8'b00111100;
            3'd1: char_data = 8'b01000010;
            3'd2: char_data = 8'b00000010;
            3'd3: char_data = 8'b00000110;
            3'd4: char_data = 8'b00001100;
            3'd5: char_data = 8'b00011000;
            3'd6: char_data = 8'b01000000;
            3'd7: char_data = 8'b01111110;
        endcase
        4'd3: case(row) // 数字3
            3'd0: char_data = 8'b00111100;
            3'd1: char_data = 8'b01000010;
            3'd2: char_data = 8'b00000010;
            3'd3: char_data = 8'b00011100;
            3'd4: char_data = 8'b00000010;
            3'd5: char_data = 8'b01000010;
            3'd6: char_data = 8'b01000010;
            3'd7: char_data = 8'b00111100;
        endcase
        4'd4: case(row) // 数字4
            3'd0: char_data = 8'b00000110;
            3'd1: char_data = 8'b00001110;
            3'd2: char_data = 8'b00010110;
            3'd3: char_data = 8'b00100110;
            3'd4: char_data = 8'b01000110;
            3'd5: char_data = 8'b01111110;
            3'd6: char_data = 8'b00000110;
            3'd7: char_data = 8'b00000110;
        endcase
        4'd5: case(row) // 数字5
            3'd0: char_data = 8'b01111110;
            3'd1: char_data = 8'b01000000;
            3'd2: char_data = 8'b01000000;
            3'd3: char_data = 8'b01111100;
            3'd4: char_data = 8'b00000010;
            3'd5: char_data = 8'b01000010;
            3'd6: char_data = 8'b01000010;
            3'd7: char_data = 8'b00111100;
        endcase
        4'd6: case(row) // 数字6
            3'd0: char_data = 8'b00111100;
            3'd1: char_data = 8'b01000010;
            3'd2: char_data = 8'b01000000;
            3'd3: char_data = 8'b01111100;
            3'd4: char_data = 8'b01000010;
            3'd5: char_data = 8'b01000010;
            3'd6: char_data = 8'b01000010;
            3'd7: char_data = 8'b00111100;
        endcase
        4'd7: case(row) // 数字7
            3'd0: char_data = 8'b01111110;
            3'd1: char_data = 8'b00000010;
            3'd2: char_data = 8'b00000100;
            3'd3: char_data = 8'b00001000;
            3'd4: char_data = 8'b00010000;
            3'd5: char_data = 8'b00100000;
            3'd6: char_data = 8'b01000000;
            3'd7: char_data = 8'b01000000;
        endcase
        4'd8: case(row) // 数字8
            3'd0: char_data = 8'b00111100;
            3'd1: char_data = 8'b01000010;
            3'd2: char_data = 8'b01000010;
            3'd3: char_data = 8'b00111100;
            3'd4: char_data = 8'b01000010;
            3'd5: char_data = 8'b01000010;
            3'd6: char_data = 8'b01000010;
            3'd7: char_data = 8'b00111100;
        endcase
        4'd9: case(row) // 数字9
            3'd0: char_data = 8'b00111100;
            3'd1: char_data = 8'b01000010;
            3'd2: char_data = 8'b01000010;
            3'd3: char_data = 8'b00111110;
            3'd4: char_data = 8'b00000010;
            3'd5: char_data = 8'b00000010;
            3'd6: char_data = 8'b01000010;
            3'd7: char_data = 8'b00111100;
        endcase
        default: char_data = 8'b00000000; // 无效编码显示空白
    endcase
end

endmodule