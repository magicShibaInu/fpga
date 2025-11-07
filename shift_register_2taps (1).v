
module shift_register_2taps
#(
  parameter DATA_WIDTH = 8
)
(
  input                   clk,
  input  [DATA_WIDTH-1:0] shiftin,
  input                   shiftin_valid,

  output [DATA_WIDTH-1:0] shiftout,
  output [DATA_WIDTH-1:0] taps1x,
  output [DATA_WIDTH-1:0] taps0x
);

assign shiftout = taps0x;

c_shift_ram_0 shift_reg_ram_inst1 (
  .D   (shiftin       ),// input wire [7 : 0] D
  .CLK (clk           ),// input wire CLK
  .CE  (shiftin_valid ),// input wire CE
  .Q   (taps1x        ) // output wire [7 : 0] Q
);

c_shift_ram_0 shift_reg_ram_inst2 (
  .D  (taps1x        ),// input wire [7 : 0] D
  .CLK(clk           ),// input wire CLK
  .CE (shiftin_valid ),// input wire CE
  .Q  (taps0x        ) // output wire [7 : 0] Q
);

endmodule
