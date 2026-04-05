`timescale 1ns/1ps

module bias_medium;

localparam int BIAS_WIDTH = 32;
localparam int PE_COLS    = 8;
localparam int MAT_ROWS   = 8;

// SIGNALS

logic clk;
logic reset_n;

logic signed [BIAS_WIDTH-1:0] bias_data;
logic bias_valid;
bias_pkg::buffer_type_t bias_type;

logic signed [BIAS_WIDTH-1:0] bias_out [PE_COLS];

logic streaming_valid;
/* verilator lint_off UNUSEDSIGNAL */
logic streaming_start;
logic streaming_end;
/* verilator lint_on UNUSEDSIGNAL */
logic bias_ready;
logic bias_ready_full_matrix;


// DUT


bias_top #(
    .BIAS_WIDTH(BIAS_WIDTH),
    .PE_COLS(PE_COLS)
) dut (
    .clk(clk),
    .reset_n(reset_n),
    .bias_data(bias_data),
    .bias_valid(bias_valid),
    .bias_type(bias_type),
    .bias_out(bias_out),
    .streaming_valid(streaming_valid),
    .streaming_start(streaming_start),
    .streaming_end(streaming_end),
    .bias_ready(bias_ready),
    .bias_ready_full_matrix(bias_ready_full_matrix)
);

/////////////////////////////////////////////////////////////
// CLOCK
/////////////////////////////////////////////////////////////

initial clk = 0;
always #5 clk = ~clk;

/////////////////////////////////////////////////////////////
// RESET
/////////////////////////////////////////////////////////////

task automatic reset_dut();
begin
    reset_n    = 0;
    bias_valid = 0;
    bias_data  = 0;
    bias_type  = bias_pkg::BUFFER_VECTOR;
    repeat(5) @(posedge clk);
    @(negedge clk);
    reset_n = 1;
    @(posedge clk);
end
endtask


task automatic send_vector(input int base);
begin
    // wait for ready on posedge, then drive on negedge
    @(posedge clk iff bias_ready);
    bias_type = bias_pkg::BUFFER_VECTOR;
    for (int i = 0; i < PE_COLS; i++) begin
        @(posedge clk);
        bias_valid = 1;
        bias_data  = base + i;
    end
    @(posedge clk);
    bias_valid = 0;
    bias_data  = 0;
end
endtask


task automatic send_scalar(input int val);
begin
    @(posedge clk iff bias_ready);
    bias_type = bias_pkg::BUFFER_SCALLER;
    @(posedge clk);
    bias_valid = 1;
    bias_data  = val;
    @(posedge clk);
    bias_valid = 0;
    bias_data  = 0;
end
endtask


task automatic send_matrix(input int base);
begin
    @(posedge clk iff bias_ready_full_matrix);
    bias_type = bias_pkg::BUFFER_FULL;
    for (int i = 0; i < MAT_ROWS * PE_COLS; i++) begin
        @(posedge clk);
        bias_valid = 1;
        bias_data  = base + i;
    end
    @(posedge clk);
    bias_valid = 0;
    bias_data  = 0;
end
endtask

/////////////////////////////////////////////////////////////
// MAIN
/////////////////////////////////////////////////////////////

initial begin
    reset_dut();

    // TEST 1 - VECTOR
    $display("\n=== TEST1 VECTOR (base=100) ===");
    send_vector(100);

    // TEST 2 - SCALAR
    $display("\n=== TEST2 SCALAR (val=55) ===");
    send_scalar(55);

    // TEST 3 - FULL MATRIX
    $display("\n=== TEST3 FULL MATRIX (base=1000) ===");
    send_matrix(1000);


    $display("\n=== TEST2 SCALAR (val=55) ===");
    send_scalar(2);
    send_scalar(0);


    send_vector(10000);

    send_matrix(1);

    send_vector(10000);

    send_matrix(1);


    // $display("\n=== TEST1 VECTOR (base=100) ===");
    // send_vector(1);
    // wait enough time for last output to flush
    repeat(20) @(posedge clk);

    $display("\nSIMULATION DONE");
    $finish;
end


// MONITOR — print output whenever streaming_valid is high

always @(posedge clk) begin
    if (streaming_valid) begin
        $write("OUT [t=%0t]: ", $time);
        for (int i = 0; i < PE_COLS; i++)
            $write("%0d ", bias_out[i]);
        $display("");
    end
end

/////////////////////////////////////////////////////////////
// VCD
/////////////////////////////////////////////////////////////

initial begin
    $dumpfile("bias_tb.vcd");
    $dumpvars(0, bias_medium);
end

endmodule
