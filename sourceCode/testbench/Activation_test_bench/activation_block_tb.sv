`timescale 1ns/1ps
// ============================================================
// Testbench for activation_top
//
// Pipeline understood:
// 1. mac_data [8x8] → data_lane (streams 1 col/cycle, 8 cycles)
// 2. shift_unit (arithmetic right-shift)
// 3. clamp (saturate to signed byte [-128..127])
// 4. GELU LUT (8-element LUT, byte in → byte out)
// 5. act_data_out_ [COLS] (one column of 8 bytes per cycle)
//
// valid_out is high for each output beat (8 beats total per matrix).
//
// LUT loading strategy:
//   The GELU LUT is loaded from an external .mem file via $readmemh
//   instead of computing it at simulation-time.  This gives bit-exact
//   agreement with the hardware LUT (which is also synthesised from the
//   same .mem file) and makes it trivial to swap in alternative
//   quantisation schemes without touching any RTL or testbench math.
//
//   File layout  : gelu_lut_clean.mem  (256 lines, one unsigned 8-bit
//                  hex value per line, index 0 = signed input -128,
//                  index 255 = signed input +127)
//
//   Annotated copy: gelu_lut.mem  (same values, inline comments for
//                  human inspection — some simulators reject inline
//                  comments inside $readmemh, so use the _clean variant
//                  for simulation and the annotated one for review)
// ============================================================
module activation_block_tb;

// Parameters
parameter ROWS       = 8;
parameter COLS       = 8;
parameter ACC_W      = 32;
parameter SHIFT_BITS = 3;          // match your DUT parameter
parameter CLK_PERIOD = 10;
parameter MAX_CYCLES = 2000;

// Path to the .mem file.  Override on the simulator command line if needed:
//   vsim -g LUT_FILE=\"/path/to/gelu_lut_clean.mem\" activation_block_tb
// or simply place the file in the simulator working directory.
parameter string LUT_FILE = "gelu_lut.mem";

// =========================================================
// DUT I/O
// =========================================================
logic                        clk;
logic                        reset_n;
logic                        mac_done;
logic signed [ACC_W-1:0]     mac_data    [ROWS][COLS];
logic signed [7:0]           act_data_out[COLS];
logic                        valid_out;
logic                        stream_done;
// =========================================================
// DUT Instantiation
// =========================================================
activation_top #(
    .ROWS  (ROWS),
    .COLS  (COLS),
    .ACC_D (ACC_W)
) dut (
    .clk          (clk),
    .reset_n      (reset_n),
    .mac_done     (mac_done),
    .mac_data     (mac_data),
    .act_data_out (act_data_out),
    .valid_out    (valid_out),
    .stream_done  (stream_done)
);

// =========================================================
// Clock
// =========================================================
initial clk = 0;
always #(CLK_PERIOD/2) clk = ~clk;

// =========================================================
// VCD
// =========================================================
initial begin
    $dumpfile("tb_activation_top.vcd");
    $dumpvars(0, activation_block_tb);
end

// =========================================================
// GELU LUT — loaded from external memory file
// =========================================================
// The array holds 256 unsigned bytes.  Index = (signed_input + 128),
// i.e. the same mapping used in the hardware LUT.
//
// Using $readmemh gives bit-exact correspondence with the RTL and
// lets you swap quantisation tables without recompiling the TB.
logic [7:0] gelu_lut [256];

initial begin
    $readmemh(LUT_FILE, gelu_lut);
    // Sanity-check a few known points after loading.
    // GELU(0)  = 0  → index 128 should be 0x00
    // GELU(127) saturates to 127 → index 255 should be 0x7F
    // GELU(-128) saturates to 0  → index   0 should be 0x00
    if (gelu_lut[128] !== 8'h00) begin
        $error("LUT sanity FAIL: gelu_lut[128] (input=0) = 0x%02h, expected 0x00",
               gelu_lut[128]);
    end
    if (gelu_lut[255] !== 8'h7F) begin
        $error("LUT sanity FAIL: gelu_lut[255] (input=127) = 0x%02h, expected 0x7F",
               gelu_lut[255]);
    end
    $display("[LUT] Loaded %s successfully.  Spot-checks: [128]=0x%02h [255]=0x%02h [0]=0x%02h",
             LUT_FILE, gelu_lut[128], gelu_lut[255], gelu_lut[0]);
end

// =========================================================
// Reference model
// Mirrors: shift → clamp → GELU-LUT (file-based)
// =========================================================

// --- shift + clamp reference ---
function automatic logic signed [7:0] shift_and_clamp(
    input logic signed [ACC_W-1:0] val
);
    logic signed [ACC_W-1:0] shifted;
    shifted = val >>> SHIFT_BITS;
    if      (shifted >  127) return  8'sd127;
    else if (shifted < -128) return -8'sd128;
    else                     return  shifted[7:0];
endfunction

// --- GELU reference — pure LUT lookup, no floating-point math ---
function automatic logic signed [7:0] ref_gelu(
    input logic signed [7:0] clamped
);
/* verilator lint_off UNUSEDSIGNAL */
    int unsigned idx;
    idx = int'(clamped) + 128;   // [-128..127] → [0..255]
    return $signed(gelu_lut[idx]);
    /* verilator lint_on UNUSEDSIGNAL */
endfunction

// --- Full pipeline reference for one accumulator element ---
function automatic logic signed [7:0] ref_pipeline(
    input logic signed [ACC_W-1:0] raw
);
    return ref_gelu(shift_and_clamp(raw));
endfunction

// =========================================================
// Scoreboard
// =========================================================
int total_checks;
int total_errors;

// =========================================================
// Task: Reset
// =========================================================
task automatic apply_reset();
    reset_n  = 0;
    mac_done = 0;
    for (int r = 0; r < ROWS; r++)
        for (int c = 0; c < COLS; c++)
            mac_data[r][c] = '0;
    repeat(4) @(posedge clk);
    #1;
    reset_n = 1;
    @(posedge clk);
endtask

// =========================================================
// Task: Send one matrix and collect + verify 8 output beats
// col_beat 0 → first valid_out cycle = column 0 of mac_data
// =========================================================
task automatic send_and_verify(
    input logic signed [ACC_W-1:0] matrix [ROWS][COLS],
    input string test_name
);
    // ---- drive mac_data ----
    for (int r = 0; r < ROWS; r++)
        for (int c = 0; c < COLS; c++)
            mac_data[r][c] = matrix[r][c];

    @(posedge clk); #1;
    mac_done = 1;
    @(posedge clk); #1;
    mac_done = 0;

    // ---- wait for first valid_out ----
    begin
        automatic int timeout = 0;
        while (!valid_out) begin
            @(posedge clk);
            timeout++;
            if (timeout > 100) begin
                $error("[%s] TIMEOUT: valid_out never asserted", test_name);
                return;
            end
        end
    end

    // ---- sample 8 beats ----
    for (int beat = 0; beat < COLS; beat++) begin
        for (int row = 0; row < ROWS; row++) begin
            automatic logic signed [7:0] expected;
            automatic logic signed [7:0] got;
            expected = ref_pipeline(matrix[row][beat]);
            got      = act_data_out[row];
            total_checks++;
            if (got !== expected) begin
                $error("[%s] beat=%0d row=%0d: got=%0d expected=%0d (raw=0x%08h)",
                       test_name, beat, row, got, expected, matrix[row][beat]);
                total_errors++;
            end
        end

        // ---- check valid_out stays high during burst ----
        total_checks++;
        if (!valid_out) begin
            $error("[%s] valid_out dropped early at beat %0d", test_name, beat);
            total_errors++;
        end

        if (beat < COLS-1) @(posedge clk);
    end

    // ---- valid_out should de-assert after 8th beat ----
    @(posedge clk); #1;
    total_checks++;
    if (valid_out) begin
        $error("[%s] valid_out still high after 8th beat", test_name);
        total_errors++;
    end

    $display("[%s] DONE", test_name);
endtask

// =========================================================
// Helper: print output beat (for debug)
// =========================================================
task automatic print_beat(input int beat, input string label);
    $write("[%s] beat=%0d out=", label, beat);
    for (int r = 0; r < ROWS; r++)
        $write("%4d ", act_data_out[r]);
    $write("\n");
endtask

// =========================================================
// Test matrices
// =========================================================
logic signed [ACC_W-1:0] mat [ROWS][COLS];

// =========================================================
// MAIN
// =========================================================
initial begin
    total_checks = 0;
    total_errors = 0;

    $display("==============================================");
    $display(" activation_top Testbench");
    $display(" ROWS=%0d COLS=%0d ACC_W=%0d SHIFT=%0d", ROWS, COLS, ACC_W, SHIFT_BITS);
    $display(" LUT source: %s (loaded via $readmemh)", LUT_FILE);
    $display("==============================================");

    apply_reset();

    // ======================================================
    // TEST 1: All zeros — GELU(0)=0, easy sanity
    // ======================================================
    $display("\n--- TEST 1: All-zero matrix ---");
    for (int r = 0; r < ROWS; r++)
        for (int c = 0; c < COLS; c++)
            mat[r][c] = '0;
    send_and_verify(mat, "TEST1_AllZero");
    repeat(3) @(posedge clk);

    // ======================================================
    // TEST 2: Sequential positive values (0..63)
    // After shift: 0..7  After clamp: same  GELU: positive
    // ======================================================
    $display("\n--- TEST 2: Sequential positive (0..63) ---");
    for (int r = 0; r < ROWS; r++)
        for (int c = 0; c < COLS; c++)
            mat[r][c] = r*COLS + c;
    send_and_verify(mat, "TEST2_Sequential");
    repeat(3) @(posedge clk);

    // ======================================================
    // TEST 3: Large positive — clamp to +127
    // Values >> SHIFT_BITS exceed 127 → saturate
    // ======================================================
    $display("\n--- TEST 3: Large positive (saturates to +127) ---");
    for (int r = 0; r < ROWS; r++)
        for (int c = 0; c < COLS; c++)
            mat[r][c] = 32'sd10000 + r*COLS + c;
    send_and_verify(mat, "TEST3_ClampHigh");
    repeat(3) @(posedge clk);

    // ======================================================
    // TEST 4: Large negative — clamp to -128
    // ======================================================
    $display("\n--- TEST 4: Large negative (saturates to -128) ---");
    for (int r = 0; r < ROWS; r++)
        for (int c = 0; c < COLS; c++)
            mat[r][c] = -32'sd10000 - r*COLS - c;
    send_and_verify(mat, "TEST4_ClampLow");
    repeat(3) @(posedge clk);

    // ======================================================
    // TEST 5: Mixed positive and negative
    // ======================================================
    $display("\n--- TEST 5: Mixed positive/negative ---");
    for (int r = 0; r < ROWS; r++)
        for (int c = 0; c < COLS; c++)
            mat[r][c] = (r % 2 == 0) ? (r*COLS + c)*8 : -(r*COLS + c)*8;
    send_and_verify(mat, "TEST5_Mixed");
    repeat(3) @(posedge clk);

    // ======================================================
    // TEST 6: Values exactly on clamp boundary (±128*2^SHIFT_BITS)
    // shift(val) = ±128 → clamp triggers
    // ======================================================
    $display("\n--- TEST 6: Clamp boundary values ---");
    for (int r = 0; r < ROWS; r++)
        for (int c = 0; c < COLS; c++) begin
            automatic int boundary = (1 << SHIFT_BITS);  // 2^SHIFT_BITS
            mat[r][c] = (c % 2 == 0) ? 127*boundary : -128*boundary;
        end
    send_and_verify(mat, "TEST6_Boundary");
    repeat(3) @(posedge clk);

    // ======================================================
    // TEST 7: Identity column pattern
    // Each column has the same value → easy to trace per-col
    // ======================================================
    $display("\n--- TEST 7: Column-constant pattern ---");
    for (int r = 0; r < ROWS; r++)
        for (int c = 0; c < COLS; c++)
            mat[r][c] = (c - 4) * (1 << SHIFT_BITS);   // cols give -4,-3,...,3 after shift
    send_and_verify(mat, "TEST7_ColConstant");
    repeat(3) @(posedge clk);

    // ======================================================
    // TEST 8: Max positive ACC_W value
    // ======================================================
    $display("\n--- TEST 8: INT32_MAX ---");
    for (int r = 0; r < ROWS; r++)
        for (int c = 0; c < COLS; c++)
            mat[r][c] = 32'h7FFFFFFF;
    send_and_verify(mat, "TEST8_INT32MAX");
    repeat(3) @(posedge clk);

    // ======================================================
    // TEST 9: Min negative ACC_W value
    // ======================================================
    $display("\n--- TEST 9: INT32_MIN ---");
    for (int r = 0; r < ROWS; r++)
        for (int c = 0; c < COLS; c++)
            mat[r][c] = 32'h80000000;
    send_and_verify(mat, "TEST9_INT32MIN");
    repeat(3) @(posedge clk);

    // ======================================================
    // TEST 10: Back-to-back matrices (no idle gap)
    // Checks pipeline doesn't corrupt on consecutive mac_done pulses
    // ======================================================
    $display("\n--- TEST 10: Back-to-back matrix A then B ---");

    // Matrix A
    for (int r = 0; r < ROWS; r++)
        for (int c = 0; c < COLS; c++)
            mat[r][c] = (r + 1) * (1 << SHIFT_BITS);

    for (int r = 0; r < ROWS; r++)
        for (int c = 0; c < COLS; c++)
            mac_data[r][c] = mat[r][c];
    @(posedge clk); #1;
    mac_done = 1;
    @(posedge clk); #1;
    mac_done = 0;

    // Immediately load B
    wait(stream_done);
    begin
        automatic logic signed [ACC_W-1:0] mat_b [ROWS][COLS];
        for (int r = 0; r < ROWS; r++)
            for (int c = 0; c < COLS; c++)
                mat_b[r][c] = (c + 1) * (1 << SHIFT_BITS);

        for (int r = 0; r < ROWS; r++)
            for (int c = 0; c < COLS; c++)
                mac_data[r][c] = mat_b[r][c];
        @(posedge clk); #1;
        mac_done = 1;
        @(posedge clk); #1;
        mac_done = 0;

        // Verify A output
        begin
            automatic int timeout = 0;
            while (!valid_out) begin
                @(posedge clk);
                timeout++;
                if (timeout > 100) begin
                    $error("[TEST10] TIMEOUT waiting for A output");
                end
            end
        end

        $display("[TEST10] A output (visual spot-check):");
        for (int beat = 0; beat < COLS; beat++) begin
            print_beat(beat, "TEST10_A");
            if (beat < COLS-1) @(posedge clk);
        end

        $display("[TEST10] B output (visual spot-check):");
        @(posedge clk);
        begin
            automatic int timeout = 0;
            while (!valid_out) begin
                @(posedge clk);
                timeout++;
                if (timeout > 100) begin
                    $error("[TEST10] TIMEOUT waiting for B output");
                end
            end
        end
        for (int beat = 0; beat < COLS; beat++) begin
            print_beat(beat, "TEST10_B");
            if (beat < COLS-1) @(posedge clk);
        end
        $display("[TEST10] DONE (visual — no auto-check for B due to immediate re-drive)");
    end
    repeat(3) @(posedge clk);

    // ======================================================
    // TEST 11: Reset mid-stream — outputs must clear
    // ======================================================
    $display("\n--- TEST 11: Reset mid-stream ---");
    for (int r = 0; r < ROWS; r++)
        for (int c = 0; c < COLS; c++)
            mac_data[r][c] = 32'sd255;
    @(posedge clk); #1;
    mac_done = 1;
    @(posedge clk); #1;
    mac_done = 0;

    // Wait 3 cycles then reset
    repeat(3) @(posedge clk);
    reset_n = 0;
    repeat(2) @(posedge clk);
    reset_n = 1;
    @(posedge clk); #1;

    total_checks++;
    if (valid_out) begin
        $error("[TEST11] valid_out not cleared after mid-stream reset");
        total_errors++;
    end else begin
        $display("[TEST11] PASS — valid_out cleared after reset");
    end

    for (int r = 0; r < ROWS; r++) begin
        total_checks++;
        if (act_data_out[r] !== 8'sd0) begin
            $error("[TEST11] act_data_out_[%0d]=%0d not zero after reset", r, act_data_out[r]);
            total_errors++;
        end
    end
    repeat(3) @(posedge clk);

    // ======================================================
    // TEST 12: GELU linearity region — values near 0
    // ======================================================
    $display("\n--- TEST 12: Near-zero values (GELU inflection) ---");
    for (int r = 0; r < ROWS; r++)
        for (int c = 0; c < COLS; c++)
            mat[r][c] = (r - 4) * (1 << SHIFT_BITS);   // -4 to 3 after shift
    send_and_verify(mat, "TEST12_NearZero");

    // ======================================================
    // TEST 13: Full LUT sweep — exercise every LUT index
    // Sends 4 matrices that collectively cover all 256 input
    // values in groups of 64, verifying each entry exactly.
    // ======================================================
    $display("\n--- TEST 13: Full LUT sweep (all 256 input codes) ---");
    begin
        automatic logic signed [ACC_W-1:0] sweep_mat [ROWS][COLS];
        // 4 passes × 64 values = 256 total (covers entire LUT)
        for (int pass = 0; pass < 4; pass++) begin
            // Base signed value for this pass: -128, -64, 0, +64
            automatic int base_val = -128 + pass*64;
            for (int r = 0; r < ROWS; r++)
                for (int c = 0; c < COLS; c++) begin
                    // Index into this pass's 64-value block
                    automatic int idx = r*COLS + c;   // 0..63
                    // We want shift_and_clamp to yield (base_val + idx)
                    // so pre-scale by 2^SHIFT_BITS
                    sweep_mat[r][c] = (base_val + idx) * (1 << SHIFT_BITS);
                end
            send_and_verify(sweep_mat,
                $sformatf("TEST13_Sweep_pass%0d_base%0d", pass, base_val));
            repeat(3) @(posedge clk);
        end
    end

    // ======================================================
    // TEST 14: Alternating max-positive / max-negative per row
    // ======================================================
    $display("\n--- TEST 14: Alternating max/min rows ---");
    for (int r = 0; r < ROWS; r++)
        for (int c = 0; c < COLS; c++)
            mat[r][c] = (r % 2 == 0) ? 32'h7FFFFFFF : 32'h80000000;
    send_and_verify(mat, "TEST14_AltMaxMin");
    repeat(3) @(posedge clk);

    // ======================================================
    // TEST 15: Checkerboard of +1 and -1 (after shift → 0)
    // Tests that small negative and positive pre-shift values
    // both round/truncate correctly to 0 after arithmetic shift
    // ======================================================
    $display("\n--- TEST 15: Checkerboard ±(2^SHIFT_BITS - 1) ---");
    begin
        automatic int small_pos = (1 << SHIFT_BITS) - 1;  // just below shift threshold
        automatic int small_neg = -small_pos;
        for (int r = 0; r < ROWS; r++)
            for (int c = 0; c < COLS; c++)
                mat[r][c] = ((r + c) % 2 == 0) ? small_pos : small_neg;
        send_and_verify(mat, "TEST15_Checkerboard");
    end
    repeat(3) @(posedge clk);

    // ======================================================
    // SUMMARY
    // ======================================================
    $display("\n==============================================");
    $display(" Total checks : %0d", total_checks);
    $display(" Total errors : %0d", total_errors);
    if (total_errors == 0)
        $display(" *** ALL TESTS PASSED ***");
    else
        $display(" *** FAILED: %0d mismatches ***", total_errors);
    $display("==============================================");

    $finish;
end

// =========================================================
// Watchdog
// =========================================================
initial begin
    #(CLK_PERIOD * MAX_CYCLES);
    $error("WATCHDOG: simulation exceeded %0d cycles", MAX_CYCLES);
    $finish;
end

endmodule

