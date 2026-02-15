`timescale 1ns/1ps
module tb_systolic_array_for_two_test();
    // Parameters
    localparam int DATA_W = 8;
    localparam int ACC_W  = 32;
    localparam int ROWS   = 4;
    localparam int COLS   = 4;
    localparam int K      = 4;

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

    // Matrix C inputs (row-by-row loading)
    logic signed [ACC_W-1:0]  C_data          [ROWS];
    logic                     C_data_valid    [ROWS];

    logic signed [ACC_W-1:0]  result_matrix   [ROWS][COLS];
    logic                     result_valid;

    // Test matrices
    logic signed [DATA_W-1:0] test_matrix_a   [ROWS][K];
    logic signed [DATA_W-1:0] test_matrix_b   [K][COLS];
    logic signed [ACC_W-1:0]  test_matrix_c   [ROWS][COLS];
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
        .COLS  (COLS),
        .K     (K)
    ) dut (
        .clk              (clk),
        .reset_n          (reset_n),
        .done             (done),
        .matrix_acc_col   (matrix_acc_col),
        .matrix_acc_valid (matrix_acc_valid),
        .matrix_wet_row   (matrix_wet_row),
        .matrix_wet_valid (matrix_wet_valid),
        .C_data           (C_data),
        .C_data_valid     (C_data_valid),
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
        for (int i = 0; i < ROWS; i++) begin
            matrix_wet_row[i] = 0;
            C_data[i] = 0;
            C_data_valid[i] = 0;
        end
    endtask

    // Task: Apply reset
    task automatic apply_reset();
        $display("[%0t] Applying reset...", $time);
        reset_n = 0;
        init_signals();
        repeat(1) @(posedge clk);
        reset_n = 1;
        repeat(1) @(posedge clk);
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

    // Task: Randomize matrix C with signed values in range [-max_val, max_val]
    task automatic randomize_matrix_c(input int max_val = 100);
        for (int i = 0; i < ROWS; i++)
            for (int j = 0; j < COLS; j++)
                test_matrix_c[i][j] = 32'(signed'($urandom_range(2*max_val+1)) - max_val);
    endtask

    // Task: Set matrix C to zeros (for testing without accumulation)
    task automatic zero_matrix_c();
        for (int i = 0; i < ROWS; i++)
            for (int j = 0; j < COLS; j++)
                test_matrix_c[i][j] = 0;
    endtask

    // Task: Set matrix C to identity scaled by a value
    task automatic identity_matrix_c(input int scale = 1);
        for (int i = 0; i < ROWS; i++)
            for (int j = 0; j < COLS; j++)
                test_matrix_c[i][j] = (i == j) ? scale : 0;
    endtask

    // Task: Set matrix C to a constant value
    task automatic constant_matrix_c(input int value = 100);
        for (int i = 0; i < ROWS; i++)
            for (int j = 0; j < COLS; j++)
                test_matrix_c[i][j] = value;
    endtask

    // Function: Software golden reference model for Y = A*B + C
    function automatic void calculate_expected_result(
        input  logic signed [DATA_W-1:0] mat_a    [ROWS][K],
        input  logic signed [DATA_W-1:0] mat_b    [K][COLS],
        input  logic signed [ACC_W-1:0]  mat_c    [ROWS][COLS],
        output logic signed [ACC_W-1:0]  expected [ROWS][COLS]
    );
        logic signed [ACC_W-1:0] ab_product;

        for (int i = 0; i < ROWS; i++)
            for (int j = 0; j < COLS; j++) begin
                // Compute A*B
                ab_product = 0;
                for (int k = 0; k < K; k++)
                    ab_product += ACC_W'(signed'(mat_a[i][k])) *
                                  ACC_W'(signed'(mat_b[k][j]));

                // Add C:  Y = A*B + C
                expected[i][j] = ab_product + mat_c[i][j];
            end
    endfunction

    // Task: Feed matrices A, B, and C SIMULTANEOUSLY (ZERO DELAY - OPTIMIZED!)
    task automatic feed_matrices(
        input logic signed [DATA_W-1:0] mat_a [ROWS][K],
        input logic signed [DATA_W-1:0] mat_b [K][COLS],
        input logic signed [ACC_W-1:0]  mat_c [ROWS][COLS],
        input bit use_c = 1  // Flag to enable/disable C accumulation
    );
        $display("[%0t] ========================================", $time);
        $display("[%0t] Feeding A, B, C SIMULTANEOUSLY (OPTIMIZED!)", $time);
        $display("[%0t] ========================================", $time);

        // Feed all three matrices at the same time - NO SEPARATE PHASES!
        // Each cycle loads: A column + B row + C column
        for (int k = 0; k < K; k++) begin
            @(posedge clk);
            
            // ===== Feed A (column k) =====
            matrix_acc_valid = 1;
            for (int i = 0; i < COLS; i++) 
                matrix_acc_col[i] = mat_a[i][k];

            // ===== Feed B (row k) =====
            matrix_wet_valid = 1;
            for (int j = 0; j < ROWS; j++) 
                matrix_wet_row[j] = mat_b[k][j];

            // ===== Feed C (column k) SIMULTANEOUSLY =====
            if (use_c && k < COLS) begin  // C has COLS columns
                for (int row = 0; row < ROWS; row++) begin
                C_data[row] = mat_c[row][COLS-1-k];
                    C_data_valid[row] = 1;
                end
                $display("[%0t]   Cycle %0d: A[col%0d] + B[row%0d] + C[col%0d] loaded", 
                         $time, k+1, k, k, k);
            end else if (use_c) begin
                // After COLS cycles, no more C to load but keep A and B going
                for (int row = 0; row < ROWS; row++) begin
                    C_data_valid[row] = 0;
                end
                $display("[%0t]   Cycle %0d: A[col%0d] + B[row%0d] (C already loaded)", 
                         $time, k+1, k, k);
            end else begin
                for (int row = 0; row < ROWS; row++) begin
                    C_data_valid[row] = 0;
                end
                $display("[%0t]   Cycle %0d: A[col%0d] + B[row%0d] (C disabled)", 
                         $time, k+1, k, k);
            end
        end
        
        // Deassert all valid signals
        @(posedge clk);
        matrix_acc_valid = 0;
        matrix_wet_valid = 0;
        for (int row = 0; row < ROWS; row++) begin
            C_data_valid[row] = 0;
        end
        
        $display("[%0t] ✓ All matrices loaded in %0d cycles (ZERO DELAY!)", $time, K);
        $display("[%0t] ========================================", $time);
    endtask

    // Task: Wait for done + result_valid with timeout
    task automatic wait_for_completion(input int timeout_cycles = 1000);
        $display("[%0t] Waiting for computation to complete...", $time);
        
        fork
            begin
                wait(done == 1);
                $display("[%0t] ✓ Done signal asserted", $time);
            end
            begin
                repeat(timeout_cycles) @(posedge clk);
                $display("[%0t] ✗ ERROR: Timeout! Done never asserted.", $time);
            end
        join_any
        disable fork;
        
        // Wait for result_valid
        fork
            begin
                wait(result_valid == 1);
                $display("[%0t] ✓ Result valid asserted", $time);
            end
            begin
                repeat(100) @(posedge clk);
                $display("[%0t] ✗ WARNING: Result valid not asserted after done!", $time);
            end
        join_any
        disable fork;
        
        @(posedge clk);  // Sample the result
    endtask

    // Task: Display matrix A
    task automatic display_matrix_a(
        input string name,
        input logic signed [DATA_W-1:0] mat [ROWS][K]
    );
        $display("\n  %s [%0dx%0d]:", name, ROWS, K);
        for (int i = 0; i < ROWS; i++) begin
            $write("    Row %0d | ", i);
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
            $write("    Row %0d | ", i);
            for (int j = 0; j < COLS; j++) $write("%5d ", mat[i][j]);
            $write("|\n");
        end
    endtask

    // Task: Display result/expected matrix (32-bit)
    task automatic display_result_matrix(
        input string name,
        input logic signed [ACC_W-1:0] mat [ROWS][COLS]
    );
        $display("\n  %s [%0dx%0d]:", name, ROWS, COLS);
        for (int i = 0; i < ROWS; i++) begin
            $write("    Row %0d | ", i);
            for (int j = 0; j < COLS; j++) $write("%8d ", mat[i][j]);
            $write("|\n");
        end
    endtask

    // Task: Check DUT result vs golden model with detailed error reporting
    task automatic check_results(
        input string test_name,
        input logic signed [ACC_W-1:0] expected [ROWS][COLS]
    );
        bit passed     = 1;
        int mismatches = 0;
        int max_errors_to_show = 10;
        int errors_shown = 0;

        $display("\n  ========================================");
        $display("  VERIFICATION: %s", test_name);
        $display("  ========================================");

        // Check all elements
        for (int i = 0; i < ROWS; i++)
            for (int j = 0; j < COLS; j++)
                if (result_matrix[i][j] !== expected[i][j]) begin
                    if (errors_shown < max_errors_to_show) begin
                        $display("  ✗ MISMATCH [%0d][%0d]: Expected = %0d,  Got = %0d,  Diff = %0d",
                                 i, j, expected[i][j], result_matrix[i][j], 
                                 result_matrix[i][j] - expected[i][j]);
                        errors_shown++;
                    end
                    passed = 0;
                    mismatches++;
                end

        if (mismatches > max_errors_to_show)
            $display("  ... and %0d more mismatches (not shown)", 
                     mismatches - max_errors_to_show);

        // Display matrices for comparison
        display_matrix_a("Matrix A (Input)", test_matrix_a);
        display_matrix_b("Matrix B (Weights)", test_matrix_b);
        if (!passed || 1) begin  // Always show C for verification
            display_result_matrix("Matrix C (Bias)   ", test_matrix_c);
        end
        display_result_matrix("Expected (A*B + C)", expected);
        display_result_matrix("DUT Result        ", result_matrix);

        // Summary
        $display("\n  ========================================");
        if (passed) begin
            $display("  ✓✓✓  PASS  ✓✓✓  [%s]", test_name);
            $display("  All %0d elements matched!", ROWS*COLS);
            pass_count++;
        end else begin
            $display("  ✗✗✗  FAIL  ✗✗✗  [%s]", test_name);
            $display("  %0d/%0d elements mismatched (%.1f%% error)", 
                     mismatches, ROWS*COLS, 
                     100.0 * real'(mismatches) / real'(ROWS*COLS));
            fail_count++;
        end
        $display("  ========================================\n");
    endtask

    // Task: Run one complete test  (reset → feed → wait → check)
    task automatic run_test(input string test_name, input bit use_c = 1);
        $display("\n\n");
        $display("=========================================================");
        $display("  %s", test_name);
        $display("=========================================================");

        // Reset DUT before every test
        apply_reset();

        // Compute golden result: Y = A*B + C
        calculate_expected_result(test_matrix_a, test_matrix_b, test_matrix_c, expected_result);

        // Drive DUT with simultaneous A, B, C loading
        feed_matrices(test_matrix_a, test_matrix_b, test_matrix_c, use_c);

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

        $display("\n\n");
        $display("=========================================================");
        $display("  SYSTOLIC ARRAY TESTBENCH - SIMULTANEOUS A,B,C LOADING");
        $display("  Y = A*B + C");
        $display("  Configuration: %0dx%0d array, K=%0d MAC operations", ROWS, COLS, K);
        $display("  OPTIMIZED: Zero delay between matrix loads!");
        $display("=========================================================");
        $display("\n");

        repeat(2) @(posedge clk);

        // ================================================================
        //  TEST 1  —  Baseline: Y = A*B + 0  (C = zeros)
        // ================================================================
        test_matrix_a[0][0] = 1; test_matrix_a[0][1] = 2;
        test_matrix_a[1][0] = 3; test_matrix_a[1][1] = 4;
        
        test_matrix_b[0][0] = 5; test_matrix_b[0][1] = 6;
        test_matrix_b[1][0] = 7; test_matrix_b[1][1] = 8;
        
        zero_matrix_c();
        run_test("TEST 1  |  Y = A*B + 0  (Known values, C=0)");

        // ================================================================
        //  TEST 2  —  Y = A*B + C  (With bias)
        // ================================================================
        test_matrix_a[0][0] = 1; test_matrix_a[0][1] = 2;
        test_matrix_a[1][0] = 3; test_matrix_a[1][1] = 4;

        test_matrix_b[0][0] = 5; test_matrix_b[0][1] = 6;
        test_matrix_b[1][0] = 7; test_matrix_b[1][1] = 8;

        test_matrix_c[0][0] = 10; test_matrix_c[0][1] = 20;
        test_matrix_c[1][0] = 30; test_matrix_c[1][1] = 40;
        run_test("TEST 2  |  Y = A*B + C  (Known values with bias)");

        // ================================================================
        //  TEST 3  —  Random small values
        // ================================================================
        randomize_matrix_a(5);
        randomize_matrix_b(5);
        randomize_matrix_c(50);
        run_test("TEST 3  |  Y = A*B + C  (Random: A,B=±5, C=±50)");

        // ================================================================
        //  TEST 4  —  Constant bias
        // ================================================================
        randomize_matrix_a(10);
        randomize_matrix_b(10);
        constant_matrix_c(100);
        run_test("TEST 4  |  Y = A*B + C  (Constant bias = 100)");

        // ================================================================
        //  TEST 5  —  Identity bias
        // ================================================================
        randomize_matrix_a(10);
        randomize_matrix_b(10);
        identity_matrix_c(200);
        run_test("TEST 5  |  Y = A*B + C  (Identity bias, scale=200)");

        // ================================================================
        //  TEST 6  —  Negative bias
        // ================================================================
        randomize_matrix_a(10);
        randomize_matrix_b(10);
        for (int i = 0; i < ROWS; i++)
            for (int j = 0; j < COLS; j++)
                test_matrix_c[i][j] = -300;
        run_test("TEST 6  |  Y = A*B + C  (Large negative bias = -300)");

        // // ================================================================
        // //  TEST 7  —  Medium values
        // ================================================================
        randomize_matrix_a(15);
        randomize_matrix_b(15);
        randomize_matrix_c(200);
        run_test("TEST 7  |  Y = A*B + C  (Medium A,B; bias ±200)");

        // ================================================================
        //  TEST 8  —  Stress test
        // ================================================================
        randomize_matrix_a(50);
        randomize_matrix_b(50);
        randomize_matrix_c(1000);
        run_test("TEST 8  |  Y = A*B + C  (Stress: A,B=±50, C=±1000)");

        // ================================================================
        //  Final Summary
        // ================================================================
        $display("\n\n");
        $display("=========================================================");
        $display("||                 TEST SUMMARY                        ||");
        $display("=========================================================");
        $display("|| Total Tests    :  8                                 ||");
        $display("|| Passed         :  %0d                               ||", pass_count);
        $display("|| Failed         :  %0d                               ||", fail_count);
        $display("=========================================================");
        if (fail_count == 0) begin
            $display("||                                                     ||");
            $display("||               ALL TESTS PASSED                      ||");
            $display("||                                                     ||");
        end else begin
            $display("||                                                     ||");
            $display("||               SOME TESTS FAILED                     ||");
            $display("||                                                     ||");
        end
        $display("=========================================================\n");

        $finish;
    end

    //========================================================================
    // Waveform Dump
    //========================================================================
    initial begin
        $dumpfile("aa.vcd");
        $dumpvars(0, tb_systolic_array_for_two_test);
    end

    //========================================================================
    // Simulation Watchdog
    //========================================================================
    initial begin
        #5000;
        $display("\n\n✗✗✗ ERROR: Simulation watchdog timeout! ✗✗✗\n");
        $finish;
    end

    //========================================================================
    // Optional: Monitor key signals during simulation
    //========================================================================
    initial begin
        $display("\n[Monitor] Starting signal monitoring...\n");

        forever begin
            @(posedge clk);
            if (done)
                $display("[%0t] [Monitor] Done signal HIGH", $time);
            if (result_valid)
                $display("[%0t] [Monitor] Result valid HIGH", $time);
        end
    end

endmodule
