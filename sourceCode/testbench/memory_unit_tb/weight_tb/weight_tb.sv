`timescale 1ns/1ps

module weight_tb;

localparam int WEIGHT_WIDTH = 8;
localparam int PE_COLS    = 8;
localparam int MAT_ROWS   = 8;

logic clk;
logic reset_n;

logic signed [WEIGHT_WIDTH-1:0] weight_data;
logic weight_valid;

logic signed [WEIGHT_WIDTH-1:0] weight_out [PE_COLS];

logic streaming_valid;
/* verilator lint_off UNUSEDSIGNAL */
logic streaming_start;
logic streaming_end;
/* verilator lint_on UNUSEDSIGNAL */
logic weight_ready;

// DUT

weight_top #(
    .WEIGHT_WIDTH(WEIGHT_WIDTH),
    .PE_COLS(PE_COLS)
) dut (
    // clock and negative edge trigger reset
    .clk(clk),
    .reset_n(reset_n),

    .weight_data(weight_data),
    .weight_valid(weight_valid),
    .weight_out(weight_out),
    .streaming_valid(streaming_valid),
    .streaming_start(streaming_start),
    .streaming_end(streaming_end),
    .weight_ready(weight_ready)
);

// CLOCK

initial clk = 0;
always #5 clk = ~clk;


// RESET


task automatic reset_dut();
begin
    reset_n    = 0;
    weight_valid = 0;
    weight_data  = 0;
    repeat(5) @(posedge clk);
    @(negedge clk);
    reset_n = 1;
    @(posedge clk);
end
endtask


// SEND FUNCTIONS


task automatic send_matrix(input int base);
begin
    @(posedge clk iff weight_ready);
    for (int i = 0; i < MAT_ROWS * PE_COLS; i++) begin
        @(posedge clk);
        weight_valid = 1;
        weight_data  = 8'(base + i);
    end
    @(posedge clk);
    weight_valid = 0;
    weight_data  = 0;
end
endtask

task automatic send_zero_matrix();
begin
    @(posedge clk iff weight_ready);
    for (int i = 0; i < MAT_ROWS * PE_COLS; i++) begin
        @(posedge clk);
        weight_valid = 1;
        weight_data  = 0;
    end
    @(posedge clk);
    weight_valid = 0;
    weight_data  = 0;
end
endtask


// MAIN


initial begin
    reset_dut();

    $display("\n=== TEST3 FULL MATRIX (base=1000) ===");
    send_matrix(1);
    send_zero_matrix();
    send_matrix(1);
    send_zero_matrix();
    #10;
    send_matrix(20);
    send_zero_matrix();
    send_matrix(30);
    send_matrix(100);


    repeat(20) @(posedge clk);

    $display("\nSIMULATION DONE");
    $finish;
end

// MONITOR — print output whenever streaming_valid is high

always @(posedge clk) begin
    if (streaming_valid) begin
        $write("OUT [t=%0t]: ", $time);
        for (int i = 0; i < PE_COLS; i++)
            $write("%0d ", weight_out[i]);
        $display("");
    end
end


// VCD


initial begin
    $dumpfile("weight_tb.vcd");
    $dumpvars(0, weight_tb);
end

endmodule
