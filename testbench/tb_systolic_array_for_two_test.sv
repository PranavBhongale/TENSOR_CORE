`timescale 1ns/1ps

module tb_systolic_array_for_two_test;

    // Parameters
    localparam int DATA_W = 8;
    localparam int ACC_W  = 32;
    localparam int ROWS   = 8;
    localparam int COLS   = 8;
    localparam int K      = 8;

    // Clock period
    localparam int CLK_PERIOD = 10;

    // Clock & reset
    logic clk;
    logic reset_n;

    // DUT I/O
    logic done;
    logic signed [DATA_W-1:0] matrix_acc_col  [COLS];
    logic                     matrix_acc_valid;
    logic signed [DATA_W-1:0] matrix_wet_row  [ROWS];
    logic                     matrix_wet_valid;
    logic signed [ACC_W-1:0]  result_matrix   [ROWS][COLS];
    logic                     result_valid;

    // Test matrices
    logic signed [DATA_W-1:0] test_matrix_a   [ROWS][K];
    logic signed [DATA_W-1:0] test_matrix_b   [K][COLS];
    logic signed [ACC_W-1:0]  expected_result [ROWS][COLS];

    // Test control
    int pass_count = 0;
    int fail_count = 0;

    //========================================================================
    // Clock Generation
    //========================================================================
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    //========================================================================
    // DUT Instantiation
    //========================================================================
    systolic_array_top #(
        .DATA_W(DATA_W),
        .ACC_W (ACC_W),
        .ROWS  (ROWS),
        .COLS  (COLS)
    ) dut (
        .clk              (clk),
        .reset_n          (reset_n),
        .done             (done),
        .matrix_acc_col   (matrix_acc_col),
        .matrix_acc_valid (matrix_acc_valid),
        .matrix_wet_row   (matrix_wet_row),
        .matrix_wet_valid (matrix_wet_valid),
        .result_matrix    (result_matrix),
        .result_valid     (result_valid)
    );

    //========================================================================
    // Tasks
    //========================================================================

    // Task: Initialize signals
    task automatic init_signals();
        matrix_acc_valid = 0;
        matrix_wet_valid = 0;
        for (int i = 0; i < COLS; i++) matrix_acc_col[i] = 0;
        for (int i = 0; i < ROWS; i++) matrix_wet_row[i] = 0;
    endtask

    // Task: Apply reset
    task automatic apply_reset();
        $display("[%0t] Applying reset...", $time);
        reset_n = 0;
        init_signals();
        repeat(3) @(posedge clk);
        reset_n = 1;
        repeat(2) @(posedge clk);
        $display("[%0t] Reset released", $time);
    endtask

    // Task: Randomize matrix A with signed values in range [-max_val, max_val]
    task automatic randomize_matrix_a(input int max_val = 10);
        for (int i = 0; i < ROWS; i++)
            for (int j = 0; j < K; j++)
                test_matrix_a[i][j] = 8'(signed'($urandom_range(2*max_val+1)) - max_val);
    endtask

    // Task: Randomize matrix B with signed values in range [-max_val, max_val]
    task automatic randomize_matrix_b(input int max_val = 10);
        for (int i = 0; i < K; i++)
            for (int j = 0; j < COLS; j++)
                test_matrix_b[i][j] = 8'(signed'($urandom_range(2*max_val+1)) - max_val);
    endtask

    // Function: Software golden reference model
    function automatic void calculate_expected_result(
        input  logic signed [DATA_W-1:0] mat_a    [ROWS][K],
        input  logic signed [DATA_W-1:0] mat_b    [K][COLS],
        output logic signed [ACC_W-1:0]  expected [ROWS][COLS]
    );
        for (int i = 0; i < ROWS; i++)
            for (int j = 0; j < COLS; j++) begin
                expected[i][j] = 0;
                for (int k = 0; k < K; k++)
                    expected[i][j] += ACC_W'(signed'(mat_a[i][k])) *
                                      ACC_W'(signed'(mat_b[k][j]));
            end
    endfunction

    // Task: Feed matrices to DUT column by column
    task automatic feed_matrices(
        input logic signed [DATA_W-1:0] mat_a [ROWS][K],
        input logic signed [DATA_W-1:0] mat_b [K][COLS]
    );
        $display("[%0t] Feeding matrices to DUT...", $time);
        for (int k = 0; k < K; k++) begin
            @(posedge clk);
            matrix_acc_valid = 1;
            matrix_wet_valid = 1;
            for (int i = 0; i < ROWS; i++) matrix_acc_col[i] = mat_a[i][k];
            for (int j = 0; j < COLS; j++) matrix_wet_row[j] = mat_b[k][j];
        end
        @(posedge clk);
        matrix_acc_valid = 0;
        matrix_wet_valid = 0;
        $display("[%0t] Finished feeding matrices", $time);
    endtask

    // Task: Wait for done + result_valid with timeout
    task automatic wait_for_completion(input int timeout_cycles = 1000);
        $display("[%0t] Waiting for done signal...", $time);
        fork
            begin
                wait(done == 1);
                $display("[%0t] Done signal asserted", $time);
            end
            begin
                repeat(timeout_cycles) @(posedge clk);
                $display("[%0t] ERROR: Timeout! Done never asserted.", $time);
            end
        join_any
        disable fork;
        wait(result_valid == 1);
        $display("[%0t] Result valid asserted", $time);
    endtask

    // Task: Display matrix A
    task automatic display_matrix_a(
        input string name,
        input logic signed [DATA_W-1:0] mat [ROWS][K]
    );
        $display("\n  %s [%0dx%0d]:", name, ROWS, K);
        for (int i = 0; i < ROWS; i++) begin
            $write("    | ");
            for (int j = 0; j < K; j++) $write("%5d ", mat[i][j]);
            $write("|\n");
        end
    endtask

    // Task: Display matrix B
    task automatic display_matrix_b(
        input string name,
        input logic signed [DATA_W-1:0] mat [K][COLS]
    );
        $display("\n  %s [%0dx%0d]:", name, K, COLS);
        for (int i = 0; i < K; i++) begin
            $write("    | ");
            for (int j = 0; j < COLS; j++) $write("%5d ", mat[i][j]);
            $write("|\n");
        end
    endtask

    // Task: Display result/expected matrix
    task automatic display_result_matrix(
        input string name,
        input logic signed [ACC_W-1:0] mat [ROWS][COLS]
    );
        $display("\n  %s [%0dx%0d]:", name, ROWS, COLS);
        for (int i = 0; i < ROWS; i++) begin
            $write("    | ");
            for (int j = 0; j < COLS; j++) $write("%8d ", mat[i][j]);
            $write("|\n");
        end
    endtask

    // Task: Check DUT result vs golden model
    task automatic check_results(
        input string test_name,
        input logic signed [ACC_W-1:0] expected [ROWS][COLS]
    );
        bit passed     = 1;
        int mismatches = 0;

        $display("\n  ----------------------------------------");
        $display("  Checking: %s", test_name);
        $display("  ----------------------------------------");

        for (int i = 0; i < ROWS; i++)
            for (int j = 0; j < COLS; j++)
                if (result_matrix[i][j] !== expected[i][j]) begin
                    $display("  MISMATCH [%0d][%0d]: Expected = %0d,  Got = %0d",
                             i, j, expected[i][j], result_matrix[i][j]);
                    passed = 0;
                    mismatches++;
                end

        display_result_matrix("Expected Result", expected);
        display_result_matrix("DUT Result     ", result_matrix);

        $display("\n  ----------------------------------------");
        if (passed) begin
            $display("  RESULT:  PASS ✓  [%s]", test_name);
            pass_count++;
        end else begin
            $display("  RESULT:  FAIL ✗  [%s]  (%0d mismatches)", test_name, mismatches);
            fail_count++;
        end
        $display("  ----------------------------------------\n");
    endtask

    // Task: Run one complete test  (reset → feed → wait → check)
    task automatic run_test(input string test_name);
        $display("\n\n========================================");
        $display("  %s", test_name);
        $display("========================================");

        // Reset DUT before every test
        apply_reset();

        // Show randomized inputs
        display_matrix_a("Matrix A (Activations)", test_matrix_a);
        display_matrix_b("Matrix B (Weights)",     test_matrix_b);

        // Compute golden result
        calculate_expected_result(test_matrix_a, test_matrix_b, expected_result);

        // Drive DUT
        feed_matrices(test_matrix_a, test_matrix_b);

        // Wait for DUT to finish
        wait_for_completion();

        // Compare and report
        check_results(test_name, expected_result);

        repeat(10) @(posedge clk);
    endtask

    //========================================================================
    // MAIN TEST SEQUENCE
    //========================================================================
    initial begin

        clk     = 0;
        reset_n = 0;
        init_signals();

        // ================================================================
        //  TEST 1  —  Small random values  (-5 to +5)
        // ================================================================
        randomize_matrix_a(5);
        randomize_matrix_b(5);
        run_test("TEST 1  |  Random Values  (-5 to +5)");

        // ================================================================
        //  TEST 2  —  Medium random values  (-15 to +15)
        // ================================================================
        randomize_matrix_a(15);
        randomize_matrix_b(15);
        run_test("TEST 2  |  Random Values  (-15 to +15)");

        // ================================================================
        //  TEST 3  —  Large random values  (-50 to +50)
        // ================================================================
        randomize_matrix_a(50);
        randomize_matrix_b(50);
        run_test("TEST 3  |  Random Values  (-50 to +50)");

        // ================================================================
        //  Final Summary
        // ================================================================
        $display("\n");
        $display("=========================================");
        $display("||          TEST SUMMARY               ||");
        $display("=========================================");
        $display("||  Total Tests :  3                   ||");
        $display("||  Passed      :  %0d                   ||", pass_count);
        $display("||  Failed      :  %0d                   ||", fail_count);
        $display("=========================================");
        if (fail_count == 0)
            $display("||  Result : ALL TESTS PASSED  ✓       ||");
        else
            $display("||  Result : SOME TESTS FAILED ✗       ||");
        $display("=========================================\n");

        $finish;
    end

    //========================================================================
    // Waveform Dump
    //========================================================================
    initial begin
        $dumpfile("sa.vcd");
        $dumpvars(0, tb_systolic_array_for_two_test);
    end

    //========================================================================
    // Simulation Watchdog
    //========================================================================
    initial begin
        #500000;
        $display("ERROR: Simulation watchdog timeout!");
        $finish;
    end

endmodule
