`timescale 1ns/1ps

module bias_tb_simple;

localparam int BIAS_WIDTH = 32;
localparam int PE_COLS    = 8;

logic clk;
logic reset_n;

logic signed [BIAS_WIDTH-1:0] bias_data;
logic bias_valid;
bias_pkg :: buffer_type_t bias_type;

logic signed [BIAS_WIDTH-1:0] bias_out [PE_COLS];

logic streaming_valid;
logic streaming_start;
logic streaming_end;
/* verilator lint_off UNUSEDSIGNAL */
logic bias_ready;
/* verilator lint_on UNUSEDSIGNAL */
logic [1:0] buffer_select;

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
    .buffer_select(buffer_select)
);

// CLOCK

initial clk = 0;
always #5 clk = ~clk;

// RESET

initial begin
    reset_n = 0;
    bias_valid = 0;
    bias_data = 0;
    bias_type = BUFFER_VECTOR;

    #50;
    reset_n = 1;
end



// STIMULUS


initial begin

    @(posedge reset_n);

    // send 8 bias values
    for(int i=0;i<8;i++) begin
        @(posedge clk);
        bias_valid = 1;
        bias_data = 100 + i;
    end

    @(posedge clk);
    bias_valid = 0;

    #200;
    $finish;

end



// MONITOR


always @(posedge clk) begin
    if(streaming_start)
        $display("START t=%0t buffer=%0d",$time,buffer_select);

    if(streaming_valid) begin
        $write("bias_out = ");
        for(int i=0;i<PE_COLS;i++)
            $write("%0d ",bias_out[i]);
        $display("");
    end

    if(streaming_end)
        $display("END t=%0t",$time);
end



// WAVEFORM


initial begin
    $dumpfile("bias_tb.vcd");
    $dumpvars(0,bias_tb_simple);
end

endmodule
