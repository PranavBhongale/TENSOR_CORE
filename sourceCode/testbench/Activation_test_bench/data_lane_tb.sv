`timescale 1ns/1ps
// this tb is from clouad
module data_lane_tb;

    // =========================================================
    // Parameters
    // =========================================================
    parameter ROWS  = 8;
    parameter COLS  = 8;
    parameter ACC_W = 32;

    parameter CLK_PERIOD = 10; // 10 ns → 100 MHz

    // =========================================================
    // DUT Signals
    // =========================================================
    logic clk;
    logic reset_n;

    logic signed [ACC_W-1:0] mac_data [ROWS][COLS];
    logic mac_done;

    logic signed [ACC_W-1:0] data_out [ROWS];
    logic valid_out;
    logic stream_done;

    // =========================================================
    // DUT Instantiation
    // =========================================================
    data_lane #(
        .ROWS  (ROWS),
        .COLS  (COLS),
        .ACC_W (ACC_W)
    ) dut (
        .clk        (clk),
        .reset_n    (reset_n),
        .mac_data   (mac_data),
        .mac_done   (mac_done),
        .data_out   (data_out),
        .valid_out  (valid_out),
        .stream_done(stream_done)
    );

    // =========================================================
    // Clock Generation
    // =========================================================
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // =========================================================
    // VCD Dump
    // =========================================================
    initial begin
        $dumpfile("data_lane.vcd");
        $dumpvars(0, data_lane_tb);
    end

    // =========================================================
    // Capture received data
    // =========================================================
    // We expect COLS beats of ROWS-wide data → total ROWS*COLS values
    logic signed [ACC_W-1:0] received [COLS][ROWS]; // [col_beat][row]
   // int beat_count;

    // =========================================================
    // Task: Apply Reset
    // =========================================================
    task automatic apply_reset();
        reset_n  = 0;
        mac_done = 0;
        for (int r = 0; r < ROWS; r++)
            for (int c = 0; c < COLS; c++)
                mac_data[r][c] = '0;
        repeat(2) @(posedge clk);
        #1;
        reset_n = 1;
        @(posedge clk);
    endtask

    // =========================================================
    // Task: Drive MAC data and pulse mac_done
    // =========================================================
    task automatic  drive_mac_result(input logic signed [ACC_W-1:0] matrix [ROWS][COLS]);
        // Load matrix
        for (int r = 0; r < ROWS; r++)
            for (int c = 0; c < COLS; c++)
                mac_data[r][c] = matrix[r][c];

        // Assert mac_done for 1 cycle
        @(posedge clk); #1;
        mac_done = 1;
        @(posedge clk); #1;
        mac_done = 0;
    endtask

    // =========================================================
    // Task: Collect stream output and verify
    // =========================================================
    task automatic collect_and_verify(
        input logic signed [ACC_W-1:0] expected [ROWS][COLS],
        input string test_name
    );
        automatic int    beats_seen   = 0;
        automatic int    errors       = 0;
        automatic int    timeout_cnt  = 0;
        automatic int    max_wait     = (ROWS + COLS + 10) * 2; // generous timeout

        // Wait for first valid_out
        while (!valid_out && timeout_cnt < max_wait) begin
            @(posedge clk);
            timeout_cnt++;
        end

        if (timeout_cnt == max_wait) begin
            $error("[%s] TIMEOUT waiting for valid_out", test_name);
            return;
        end

        // Capture all beats while valid_out is high
        while (valid_out) begin
            // Sample on posedge
            if (beats_seen < COLS) begin
                for (int r = 0; r < ROWS; r++)
                    received[beats_seen][r] = data_out[r];
            end
            beats_seen++;
            @(posedge clk);
        end

        $display("[%s] Received %0d beats", test_name, beats_seen);

        // --------------------------------------------------
        // Verify beat count
        // --------------------------------------------------
        if (beats_seen !== COLS)
            $error("[%s] Beat count mismatch: got %0d, expected %0d",
                   test_name, beats_seen, COLS);

        // --------------------------------------------------
        // Verify data
        // Data_lane streams column-by-column:
        //   beat 0 → column 0 of all rows
        //   beat 1 → column 1 of all rows, etc.
        // Adjust if your DUT streams row-by-row.
        // --------------------------------------------------
        for (int col = 0; col < COLS; col++) begin
            for (int row = 0; row < ROWS; row++) begin
                if (received[col][row] !== expected[row][col]) begin
                    $error("[%s] Mismatch at col=%0d row=%0d: got %0d, expected %0d",
                           test_name, col, row,
                           received[col][row], expected[row][col]);
                    errors++;
                end
            end
        end

        if (errors == 0)
            $display("[%s] PASS - all %0d values correct", test_name, ROWS*COLS);
        else
            $display("[%s] FAIL - %0d errors found", test_name, errors);

        // --------------------------------------------------
        // Verify stream_done pulses
        // --------------------------------------------------
        // stream_done should assert around or just after last valid beat
        begin
            automatic int sd_wait = 0;
            while (!stream_done && sd_wait < 5) begin
                @(posedge clk);
                sd_wait++;
            end
            if (!stream_done)
                $error("[%s] stream_done never asserted after streaming", test_name);
            else
                $display("[%s] stream_done asserted correctly", test_name);
        end
    endtask

    // =========================================================
    // Helper: Fill matrix with sequential values
    // =========================================================
    task fill_sequential(
        output logic signed [ACC_W-1:0] m [ROWS][COLS],
        input int base
    );
        for (int r = 0; r < ROWS; r++)
            for (int c = 0; c < COLS; c++)
                m[r][c] = base + r*COLS + c;
    endtask

    // =========================================================
    // Helper: Fill matrix with a constant
    // =========================================================
    task automatic fill_constant(
        output logic signed [ACC_W-1:0] m [ROWS][COLS],
        input logic signed [ACC_W-1:0]  val
    );
        for (int r = 0; r < ROWS; r++)
            for (int c = 0; c < COLS; c++)
                m[r][c] = val;
    endtask

    // =========================================================
    // Test Matrices
    // =========================================================
    logic signed [ACC_W-1:0] mat_a [ROWS][COLS];
    logic signed [ACC_W-1:0] mat_b [ROWS][COLS];
    logic signed [ACC_W-1:0] mat_c [ROWS][COLS];

    // =========================================================
    // Main Test Body
    // =========================================================
    initial begin
        $display("========================================");
        $display("  data_lane Testbench Start");
        $display("  ROWS=%0d  COLS=%0d  ACC_W=%0d", ROWS, COLS, ACC_W);
        $display("========================================");

        // --------------------------------------------------
        // Reset
        // --------------------------------------------------
        apply_reset();
        $display("[INIT] Reset complete");

        // ==================================================
        // TEST 1: Sequential values (0..63)
        // ==================================================
        $display("\n--- TEST 1: Sequential values ---");
        fill_sequential(mat_a, 0);
        drive_mac_result(mat_a);
        collect_and_verify(mat_a, "TEST1_Sequential");

        repeat(2) @(posedge clk);

        // ==================================================
        // TEST 2: All zeros
        // ==================================================
        $display("\n--- TEST 2: All-zero matrix ---");
        fill_constant(mat_b, 32'sd0);
        drive_mac_result(mat_b);
        collect_and_verify(mat_b, "TEST2_AllZeros");

        repeat(2) @(posedge clk);

        // ==================================================
        // TEST 3: All ones
        // ==================================================
        $display("\n--- TEST 3: All-ones matrix ---");
        fill_constant(mat_c, 32'sd1);
        drive_mac_result(mat_c);
        collect_and_verify(mat_c, "TEST3_AllOnes");

        repeat(2) @(posedge clk);

        // ==================================================
        // TEST 4: Negative values
        // ==================================================
        $display("\n--- TEST 4: Negative values ---");
        fill_sequential(mat_a, -32);  // values -32 to +31
        drive_mac_result(mat_a);
        collect_and_verify(mat_a, "TEST4_Negative");

        repeat(2) @(posedge clk);

        // ==================================================
        // TEST 5: Large positive values
        // ==================================================
        $display("\n--- TEST 5: Large positive values ---");
        fill_sequential(mat_a, 1000000);
        drive_mac_result(mat_a);
        collect_and_verify(mat_a, "TEST5_Large");

        repeat(2) @(posedge clk);

        // ==================================================
        // TEST 6: Back-to-back (two consecutive matrices)
        // ==================================================
        $display("\n--- TEST 6: Back-to-back matrices ---");
        fill_sequential(mat_a, 100);
        fill_sequential(mat_b, 200);

        // First matrix
        drive_mac_result(mat_a);
        collect_and_verify(mat_a, "TEST6a_BackToBack_First");

        // Immediately drive second matrix (no idle cycles)
        drive_mac_result(mat_b);
        collect_and_verify(mat_b, "TEST6b_BackToBack_Second");

        repeat(2) @(posedge clk);

        // ==================================================
        // TEST 7: Reset mid-stream (robustness)
        // ==================================================
        $display("\n--- TEST 7: Reset during stream ---");
        fill_sequential(mat_a, 50);
        // Start streaming
        for (int r = 0; r < ROWS; r++)
            for (int c = 0; c < COLS; c++)
                mac_data[r][c] = mat_a[r][c];
        @(posedge clk); #1;
        mac_done = 1;
        @(posedge clk); #1;
        mac_done = 0;

        // Wait a couple of beats then reset
        repeat(3) @(posedge clk);
        $display("[TEST7] Asserting reset mid-stream");
        reset_n = 0;
        repeat(2) @(posedge clk);
        reset_n = 1;
        @(posedge clk);

        // valid_out and stream_done must be deasserted after reset
        @(posedge clk); #1;
        if (valid_out)
            $error("[TEST7] valid_out still high after reset");
        else
            $display("[TEST7] PASS - valid_out cleared after reset");

        if (stream_done)
            $error("[TEST7] stream_done still high after reset");
        else
            $display("[TEST7] PASS - stream_done cleared after reset");

        repeat(2) @(posedge clk);

        // ==================================================
        // Done
        // ==================================================
        $display("\n========================================");
        $display("  data_lane Testbench Complete");
        $display("========================================");
        $finish;
    end

    // =========================================================
    // Watchdog
    // =========================================================
    initial begin
        #(CLK_PERIOD * 10000);
        $error("WATCHDOG: simulation exceeded time limit");
        $finish;
    end

endmodule

