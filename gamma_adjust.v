module gamma_adjust(
    input             clk,
    input             rst_n,
    input      [7:0]  i_rgb888,
    output reg [7:0]  o_rgb888
);

    reg [7:0] gamma_lut [0:255];

    initial begin
        $readmemh("gamma1_3.mem", gamma_lut);
    end

    always @(posedge clk) begin
        if(!rst_n)
            o_rgb888 <= 8'd0;
        else
            o_rgb888 <= gamma_lut[i_rgb888];
    end

endmodule
