module gelu_lut (
    input  logic              clk,
    input  logic signed [7:0] addr_1,
    output logic signed [7:0] dout_1
);

    logic [7:0] rom [256];
        /* verilator lint_off UNUSEDSIGNAL */
    logic [8:0] index_ext;
    logic [7:0] index;

    assign index_ext = addr_1 + 9'sd128;
    assign index     = index_ext[7:0];
    /* verilator lint_on UNUSEDSIGNAL */

    initial begin
        $readmemh("gelu_lut.mem", rom);
    end

    always_ff @(posedge clk) begin
        dout_1 <= rom[index];
    end

endmodule
