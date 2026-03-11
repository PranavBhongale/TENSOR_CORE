`timescale 1ns/1ps
// ============================================================================
//  bias_tb.sv  —  Verilator 5.x compatible testbench for bias_top
//
//  Structure:
//    1. Parameters & signals
//    2. DUT instantiation
//    3. Clock
//    4. Helper tasks  (reset / send / wait)
//    5. Monitor       (always block — prints events)
//    6. Checkers      (always block — plain ff, no SVA ranges)
//    7. Stimulus      (initial block — all test phases)

//  Questa / ModelSim run:
//    vlog -sv bias_pkg.sv bias_buffer.sv bias_controller.sv \
//             bias_top.sv bias_tb.sv
//    vsim -c bias_tb -do "run -all"
// ============================================================================
/* verilator lint_off IMPORTSTAR */
import bias_pkg::*;
/* verilator lint_on IMPORTSTAR */
module bias_full_tb;

// ============================================================================
// 1.  PARAMETERS & SIGNALS
// ============================================================================

localparam int BIAS_WIDTH  = 32;
localparam int PE_COLS     = 8;
localparam int MAT_WORDS   = PE_COLS * PE_COLS;  // 64
localparam int TIMEOUT     = 300;                // cycles before $fatal

// DUT inputs
logic                          clk;
logic                          reset_n;
logic signed [BIAS_WIDTH-1:0]  bias_data;
logic                          bias_valid;
buffer_type_t                  bias_type;

// DUT outputs
logic signed [BIAS_WIDTH-1:0]  bias_out [PE_COLS];
logic                          streaming_valid;
logic                          streaming_start;
logic                          streaming_end;
logic                          bias_ready;
logic [1:0]                    buffer_select;

// Test result counters
int pass_cnt;
int fail_cnt;

// ============================================================================
// 2.  DUT
// ============================================================================

bias_top #(
    .BIAS_WIDTH (BIAS_WIDTH),
    .PE_COLS    (PE_COLS)
) dut (
    .clk            (clk),
    .reset_n        (reset_n),
    .bias_data      (bias_data),
    .bias_valid     (bias_valid),
    .bias_type      (bias_type),
    .bias_out       (bias_out),
    .streaming_valid(streaming_valid),
    .streaming_start(streaming_start),
    .streaming_end  (streaming_end),
    .bias_ready     (bias_ready),
    .buffer_select  (buffer_select)
);

// ============================================================================
// 3.  CLOCK  (10 ns / 100 MHz)
// ============================================================================

initial clk = 1'b0;
always  #5 clk = ~clk;

// VCD dump
initial begin
    $dumpfile("bias_tb.vcd");
    $dumpvars(0, bias_tb);
end

// ============================================================================
// 4.  HELPER TASKS
// ============================================================================

// --------------------------------------------------------------------------
// do_reset — hold reset low for <cycles> then release
// --------------------------------------------------------------------------
task automatic do_reset(input int cycles = 6);
    reset_n    = 1'b0;
    bias_valid = 1'b0;
    bias_data  = '0;
    repeat (cycles) @(posedge clk);
    @(negedge clk);          // drive on negedge to be clean vs posedge sample
    reset_n = 1'b1;
    @(posedge clk);
endtask

// --------------------------------------------------------------------------
// wait_ready — spin until bias_ready or $fatal on timeout
// --------------------------------------------------------------------------
task automatic wait_ready();
    int cnt = 0;
    while (!bias_ready) begin
        @(posedge clk);
        if (++cnt >= TIMEOUT)
            $fatal(1, "[TB] TIMEOUT: bias_ready never asserted");
    end
endtask

// --------------------------------------------------------------------------
// send_word — one valid word for exactly one cycle
// --------------------------------------------------------------------------
task automatic send_word(input logic signed [BIAS_WIDTH-1:0] d);
    @(negedge clk);
    bias_valid = 1'b1;
    bias_data  = d;
    @(posedge clk);
    @(negedge clk);
    bias_valid = 1'b0;
    bias_data  = '0;
endtask

// --------------------------------------------------------------------------
// wait_start — wait for streaming_start or $fatal on timeout
// --------------------------------------------------------------------------
task automatic wait_start();
    int cnt = 0;
    while (!streaming_start) begin
        @(posedge clk);
        if (++cnt >= TIMEOUT)
            $fatal(1, "[TB] TIMEOUT: streaming_start never asserted");
    end
endtask

// --------------------------------------------------------------------------
// wait_end — wait for streaming_end or $fatal on timeout
// --------------------------------------------------------------------------
task automatic wait_end();
    int cnt = 0;
    while (!streaming_end) begin
        @(posedge clk);
        if (++cnt >= TIMEOUT)
            $fatal(1, "[TB] TIMEOUT: streaming_end never asserted");
    end
    @(posedge clk);   // one clean gap before next transaction
endtask

// --------------------------------------------------------------------------
// check_outputs — compare bias_out[] against expected[], print PASS/FAIL
// --------------------------------------------------------------------------
task automatic check_outputs(
    input logic signed [BIAS_WIDTH-1:0] expected [PE_COLS],
    input string                        label
);
    int ok = 1;
    for (int c = 0; c < PE_COLS; c++) begin
        if (bias_out[c] !== expected[c]) begin
            $display("  [FAIL] %s  col[%0d]  exp=%0d  got=%0d",
                     label, c, $signed(expected[c]), $signed(bias_out[c]));
            ok = 0;
        end
    end
    if ((ok == 1)) begin
        $display("  [PASS] %s", label);
        pass_cnt++;
    end else begin
        fail_cnt++;
    end
endtask

// ============================================================================
// 5.  MONITOR  — event display (separate always block, always running)
// ============================================================================

always @(posedge clk) begin
    if (streaming_start)
        $display("[MON] %0t ns  STREAM_START  buf=%0d", $time/1000, buffer_select);
    if (streaming_end)
        $display("[MON] %0t ns  STREAM_END    buf=%0d", $time/1000, buffer_select);
    if (bias_ready && !reset_n)
        ;  // suppress ready messages during reset
end

// ============================================================================
// 6.  CHECKERS  — protocol rules, plain always_ff, no SVA range operators
// ============================================================================

logic        chk_in_burst;
int          chk_burst_len;
logic        rst_d;           // delayed reset for rose-equivalent

// Track reset edge
always_ff @(posedge clk)
    rst_d <= reset_n;

// Burst tracker + rule checkers
always_ff @(posedge clk) begin
    if (!reset_n) begin
        chk_in_burst  <= 1'b0;
        chk_burst_len <= 0;
    end else begin

        // Enter burst on start
        if (streaming_start) begin
            chk_in_burst  <= 1'b1;
            chk_burst_len <= 1;
        end

        // Count cycles inside burst
        if (chk_in_burst && !streaming_end)
            chk_burst_len <= chk_burst_len + 1;

        // Exit burst on end
        if (streaming_end) begin
            chk_in_burst  <= 1'b0;
            chk_burst_len <= 0;
        end

        // RULE 1: streaming_end must arrive within PE_COLS cycles
        if (chk_in_burst && !streaming_end && chk_burst_len > PE_COLS) begin
            $error("[CHK-1] %0t ns  streaming_end missing after %0d cycles",
                   $time/1000, PE_COLS);
            fail_cnt <= fail_cnt + 1;
        end

        // RULE 2: streaming_valid must stay high inside a burst
        if (chk_in_burst && !streaming_end && !streaming_valid) begin
            $error("[CHK-2] %0t ns  streaming_valid dropped mid-burst", $time/1000);
            fail_cnt <= fail_cnt + 1;
        end

        // RULE 3: bias_ready must NOT assert while streaming_valid is high
        if (streaming_valid && bias_ready) begin
            $error("[CHK-3] %0t ns  bias_ready high during streaming_valid", $time/1000);
            fail_cnt <= fail_cnt + 1;
        end

        // RULE 4: no streaming signals the cycle after reset deasserts
        if (reset_n && !rst_d) begin
            if (streaming_valid || streaming_start || streaming_end) begin
                $error("[CHK-4] %0t ns  streaming signal active after reset", $time/1000);
                fail_cnt <= fail_cnt + 1;
            end
        end

    end
end

// ============================================================================
// 7.  STIMULUS
// ============================================================================

logic signed [BIAS_WIDTH-1:0] row_data [PE_COLS];
logic signed [BIAS_WIDTH-1:0] mat_data [MAT_WORDS];
logic signed [BIAS_WIDTH-1:0] exp_row  [PE_COLS];

initial begin

    pass_cnt = 0;
    fail_cnt = 0;

    $display("====================================================");
    $display("  bias_top testbench  —  Verilator 5.x");
    $display("====================================================");

    // ========================================================================
    // PHASE 0  —  Reset
    // ========================================================================
    $display("\n--- PHASE 0 : Reset ---");
    do_reset(8);
    $display("    Reset done");

    // ========================================================================
    // PHASE 1  —  BUFFER_ROW  directed  (100 .. 107)
    // ========================================================================
    $display("\n--- PHASE 1 : BUFFER_VECTOR directed ---");
    bias_type = BUFFER_VECTOR;
    wait_ready();

    for (int i = 0; i < PE_COLS; i++) begin
        row_data[i] = 32'(100 + i);
        send_word(row_data[i]);
    end

    wait_start();
    @(posedge clk);                       // let outputs settle
    check_outputs(row_data, "P1 ROW 100-107");
    wait_end();

    // ========================================================================
    // PHASE 2  —  BUFFER_ROW  ping-pong  A→B→A
    // ========================================================================
    $display("\n--- PHASE 2 : BUFFER_ROW ping-pong ---");

    // Row B  (200..207)
    wait_ready();
    for (int i = 0; i < PE_COLS; i++) begin
        row_data[i] = 32'(200 + i);
        send_word(row_data[i]);
    end
    wait_start();
    @(posedge clk);
    check_outputs(row_data, "P2 ROW-B 200-207");
    wait_end();

    // Row A2  (300..307)
    wait_ready();
    for (int i = 0; i < PE_COLS; i++) begin
        row_data[i] = 32'(300 + i);
        send_word(row_data[i]);
    end
    wait_start();
    @(posedge clk);
    check_outputs(row_data, "P2 ROW-A 300-307");
    wait_end();

    // ========================================================================
    // PHASE 3  —  BUFFER_FULL  directed  (1000 .. 1063)
    // ========================================================================
    $display("\n--- PHASE 3 : BUFFER_FULL directed ---");
    do_reset(4);                          // clean switch to FULL mode
    bias_type = BUFFER_FULL;
    wait_ready();

    for (int i = 0; i < MAT_WORDS; i++) begin
        mat_data[i] = 32'(1000 + i);
        send_word(mat_data[i]);
    end

    // 8 rows stream out sequentially — check each one
    for (int r = 0; r < PE_COLS; r++) begin
        wait_start();
        @(posedge clk);
        for (int c = 0; c < PE_COLS; c++)
            exp_row[c] = mat_data[r * PE_COLS + c];
        check_outputs(exp_row, $sformatf("P3 MAT row%0d", r));
        wait_end();
    end

    // ========================================================================
    // PHASE 4  —  BUFFER_FULL  reload  (second tile: 2000 .. 2063)
    // ========================================================================
    $display("\n--- PHASE 4 : BUFFER_FULL reload ---");
    wait_ready();

    for (int i = 0; i < MAT_WORDS; i++) begin
        mat_data[i] = 32'(2000 + i);
        send_word(mat_data[i]);
    end

    for (int r = 0; r < PE_COLS; r++) begin
        wait_start();
        @(posedge clk);
        for (int c = 0; c < PE_COLS; c++)
            exp_row[c] = mat_data[r * PE_COLS + c];
        check_outputs(exp_row, $sformatf("P4 MAT2 row%0d", r));
        wait_end();
    end

    // ========================================================================
    // PHASE 5  —  Corner cases
    // ========================================================================
    $display("\n--- PHASE 5 : Corner cases ---");
    do_reset(4);
    bias_type = BUFFER_VECTOR;

    // 5a: all zeros
    wait_ready();
    for (int i = 0; i < PE_COLS; i++) begin
        row_data[i] = '0;
        send_word(row_data[i]);
    end
    wait_start(); @(posedge clk);
    check_outputs(row_data, "P5a zeros");
    wait_end();

    // 5b: max positive  (0x7FFF_FFFF)
    wait_ready();
    for (int i = 0; i < PE_COLS; i++) begin
        row_data[i] = 32'h7FFF_FFFF;
        send_word(row_data[i]);
    end
    wait_start(); @(posedge clk);
    check_outputs(row_data, "P5b max_pos");
    wait_end();

    // 5c: max negative  (0x8000_0000)
    wait_ready();
    for (int i = 0; i < PE_COLS; i++) begin
        row_data[i] = 32'h8000_0000;
        send_word(row_data[i]);
    end
    wait_start(); @(posedge clk);
    check_outputs(row_data, "P5c max_neg");
    wait_end();

    // 5d: alternating +/−
    wait_ready();
    for (int i = 0; i < PE_COLS; i++) begin
        row_data[i] = (i[0]) ? -$signed(32'(i+1)) : $signed(32'(i+1));
        send_word(row_data[i]);
    end
    wait_start(); @(posedge clk);
    check_outputs(row_data, "P5d alternating");
    wait_end();

    // ========================================================================
    // PHASE 6  —  Reset mid-stream
    // ========================================================================
    $display("\n--- PHASE 6 : Reset mid-stream ---");
    wait_ready();
    bias_type = BUFFER_VECTOR;

    // Send a few words then hard-reset
    @(negedge clk); bias_valid = 1'b1; bias_data = 32'd999;
    @(posedge clk);
    @(posedge clk);
    reset_n    = 1'b0;          // assert reset
    bias_valid = 1'b0;
    bias_data  = '0;
    repeat (4) @(posedge clk);
    reset_n = 1'b1;
    @(posedge clk);
    @(posedge clk);

    // CHK-4 fires automatically if outputs are not clean after reset
    if (!streaming_valid && !streaming_start && !streaming_end) begin
        $display("  [PASS] P6 reset mid-stream — outputs clean");
        pass_cnt++;
    end else begin
        $display("  [FAIL] P6 reset mid-stream — outputs not clean");
        fail_cnt++;
    end

    // ========================================================================
    // FINAL REPORT
    // ========================================================================
    repeat (10) @(posedge clk);

    $display("\n====================================================");
    $display("  RESULTS:  PASS=%0d  FAIL=%0d", pass_cnt, fail_cnt);
    if (fail_cnt == 0)
        $display("  >>> ALL TESTS PASSED <<<");
    else
        $display("  >>> %0d FAILURE(S) DETECTED <<<", fail_cnt);
    $display("====================================================\n");

    $finish;
end

endmodule
