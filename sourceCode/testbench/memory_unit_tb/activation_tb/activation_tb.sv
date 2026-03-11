`timescale 1ns/1ps

module activation_tb;

localparam int ACTIVATION_WIDTH = 8;
localparam int PE_COLS    = 8;
localparam int MAT_ROWS   = 8;

logic clk;
logic reset_n;

logic signed [ACTIVATION_WIDTH-1:0] activation_data;
logic activation_valid;

logic signed [ACTIVATION_WIDTH-1:0] activation_out [PE_COLS];

logic streaming_valid;
/* verilator lint_off UNUSEDSIGNAL */
logic streaming_start;
logic streaming_end;
/* verilator lint_on UNUSEDSIGNAL */
logic activation_ready;

// DUT

activation_top #(
    .ACTIVATION_WIDTH(ACTIVATION_WIDTH),
    .PE_COLS(PE_COLS)
) dut (
    // clock and negative edge trigger reset
    .clk(clk),
    .reset_n(reset_n),

    .activation_data(activation_data),
    .activation_valid(activation_valid),
    .activation_out(activation_out),
    .streaming_valid(streaming_valid),
    .streaming_start(streaming_start),
    .streaming_end(streaming_end),
    .activation_ready(activation_ready)
);

initial clk = 0;
always #5 clk = ~clk;


// RESET


task automatic reset_dut();
begin
    reset_n    = 0;
    activation_valid = 0;
    activation_data  = 0;
    repeat(5) @(posedge clk);
    @(negedge clk);
    reset_n = 1;
    @(posedge clk);
end
endtask


// SEND FUNCTIONS


task automatic send_matrix(input int base);
begin
    @(posedge clk iff activation_ready);
    for (int i = 0; i < MAT_ROWS * PE_COLS; i++) begin
        @(posedge clk);
        activation_valid = 1;
        activation_data  = 8'(base + i);
    end
    @(posedge clk);
    activation_valid = 0;
    activation_data  = 0;
end
endtask

task automatic send_zero_matrix();
begin
    @(posedge clk iff activation_ready);
    for (int i = 0; i < MAT_ROWS * PE_COLS; i++) begin
        @(posedge clk);
        activation_valid = 1;
        activation_data  = 0;
    end
    @(posedge clk);
    activation_valid = 0;
    activation_data  = 0;
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
            $write("%0d ", activation_out[i]);
        $display("");
    end
end


// VCD


initial begin
    $dumpfile("activation_tb.vcd");
    $dumpvars(0, activation_tb);
end

endmodule
