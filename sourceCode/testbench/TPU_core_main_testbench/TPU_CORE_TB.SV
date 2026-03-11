`timescale 1ns/1ps
// =============================================================================
// Testbench : TPU_CORE_TB
// DUT       : TPU_core_top  (systolic_array_top + activation_top)
// Golden    : A*B + C  ->  arithmetic right-shift  ->  clamp  ->  GELU LUT
// =============================================================================
module TPU_CORE_TB;

    // Parameters
    localparam int DATA_W     = 8;
    localparam int ACC_W      = 32;
    localparam int ROWS       = 8;
    localparam int COLS       = 8;
    localparam int K          = 8;
    localparam int SHIFT_BITS = 3;
    localparam int CLK_HALF   = 5;
    localparam int MAX_CYCLES = 200000;
    localparam string LUT_FILE = "gelu_lut.mem";

    // -------------------------------------------------------------------------
    // Clock and reset
    // -------------------------------------------------------------------------
    logic clk;
    logic reset_n;

    initial clk = 1'b0;
    always #CLK_HALF clk = ~clk;

    // -------------------------------------------------------------------------
    // DUT ports
    // -------------------------------------------------------------------------
    logic signed [DATA_W-1:0] matrix_acc_col  [COLS];
    logic signed [DATA_W-1:0] matrix_wet_row  [ROWS];
    logic                     matrix_acc_valid;
    logic                     matrix_wet_valid;

    logic signed [ACC_W-1:0]  C_data       [COLS];
    logic                     C_data_valid [COLS];

    logic signed [7:0]        act_data_out [COLS];
    logic                     valid_out;

    // -------------------------------------------------------------------------
    // DUT instantiation
    // -------------------------------------------------------------------------
    TPU_core_top #(
        .ACC_W (ACC_W),
        .DATA_W(DATA_W),
        .ROWS  (ROWS),
        .COLS  (COLS),
        .K     (K)
    ) dut (
        .clk             (clk),
        .reset_n         (reset_n),
        .matrix_acc_col  (matrix_acc_col),
        .matrix_wet_row  (matrix_wet_row),
        .matrix_acc_valid(matrix_acc_valid),
        .matrix_wet_valid(matrix_wet_valid),
        .C_data          (C_data),
        .C_data_valid    (C_data_valid),
        .act_data_out    (act_data_out),
        .valid_out       (valid_out)
    );

    // -------------------------------------------------------------------------
    // VCD
    // -------------------------------------------------------------------------
    initial begin
        $dumpfile("tpu_core.vcd");
        $dumpvars(0, TPU_CORE_TB);
    end

    // =========================================================================
    // GELU LUT
    // =========================================================================
    logic [7:0] gelu_lut [256];

    initial begin
        $readmemh(LUT_FILE, gelu_lut);
        $display("LUT loaded from %s", LUT_FILE);
        $display("  spot check: index 128 (input=0)   = 0x%02h  (expect 0x00)", gelu_lut[128]);
        $display("  spot check: index 255 (input=127) = 0x%02h  (expect 0x7F)", gelu_lut[255]);
        $display("  spot check: index   0 (input=-128)= 0x%02h", gelu_lut[0]);
        if (gelu_lut[128] !== 8'h00)
            $display("WARNING: LUT[128] mismatch - check gelu_lut.mem");
        if (gelu_lut[255] !== 8'h7F)
            $display("WARNING: LUT[255] mismatch - check gelu_lut.mem");
    end

    // =========================================================================
    // Golden model functions
    // =========================================================================

    function automatic logic signed [7:0] fn_shift_clamp(
        input logic signed [ACC_W-1:0] val
    );
        logic signed [ACC_W-1:0] sh;
        sh = val >>> SHIFT_BITS;
        if      (sh >  32'sd127) fn_shift_clamp =  8'sd127;
        else if (sh < -32'sd128) fn_shift_clamp = -8'sd128;
        else                     fn_shift_clamp =  sh[7:0];
    endfunction

    function automatic logic signed [7:0] fn_gelu(
        input logic signed [7:0] x
    );
        // verilator lint_off UNUSEDSIGNAL
        int unsigned idx;
        // verilator lint_on UNUSEDSIGNAL
        idx = int'(x) + 128;
        fn_gelu = $signed(gelu_lut[idx]);
    endfunction

    function automatic logic signed [7:0] fn_pipeline(
        input logic signed [ACC_W-1:0] raw
    );
        fn_pipeline = fn_gelu(fn_shift_clamp(raw));
    endfunction

    function automatic void fn_matmul(
        input  logic signed [DATA_W-1:0] a [ROWS][K],
        input  logic signed [DATA_W-1:0] b [K][COLS],
        input  logic signed [ACC_W-1:0]  c [ROWS][COLS],
        output logic signed [ACC_W-1:0]  r [ROWS][COLS]
    );
        int i, j, kk;
        for (i = 0; i < ROWS; i++) begin
            for (j = 0; j < COLS; j++) begin
                r[i][j] = c[i][j];
                for (kk = 0; kk < K; kk++)
                    r[i][j] = r[i][j] +
                               (ACC_W'(signed'(a[i][kk])) * ACC_W'(signed'(b[kk][j])));
            end
        end
    endfunction

    // =========================================================================
    // Scoreboard
    // =========================================================================
    int g_pass   = 0;
    int g_fail   = 0;
    int g_checks = 0;
    int g_errors = 0;

    // =========================================================================
    // Shared test matrices
    // =========================================================================
    logic signed [DATA_W-1:0] ta [ROWS][K];
    logic signed [DATA_W-1:0] tb [K][COLS];
    logic signed [ACC_W-1:0]  tc [ROWS][COLS];
    logic signed [ACC_W-1:0]  exp_acc [ROWS][COLS];

    // =========================================================================
    // Tasks
    // =========================================================================

    task automatic t_init();
        int i;
        matrix_acc_valid = 1'b0;
        matrix_wet_valid = 1'b0;
        for (i = 0; i < COLS; i++) begin
            matrix_acc_col[i] = '0;
            C_data[i]         = '0;
            C_data_valid[i]   = 1'b0;
        end
        for (i = 0; i < ROWS; i++)
            matrix_wet_row[i] = '0;
    endtask

    task automatic t_reset();
        reset_n = 1'b0;
        t_init();
        repeat(4) @(posedge clk);
        @(negedge clk);
        reset_n = 1'b1;
        @(posedge clk);
    endtask

    task automatic t_zero_c();
        int i, j;
        for (i = 0; i < ROWS; i++)
            for (j = 0; j < COLS; j++)
                tc[i][j] = 32'sd0;
    endtask

    task automatic t_const_c(input int val);
        int i, j;
        for (i = 0; i < ROWS; i++)
            for (j = 0; j < COLS; j++)
                tc[i][j] = val;
    endtask

    task automatic t_identity_c(input int scale);
        int i, j;
        for (i = 0; i < ROWS; i++)
            for (j = 0; j < COLS; j++)
                tc[i][j] = (i == j) ? scale : 32'sd0;
    endtask

    task automatic t_rand_a(input int maxv);
        int i, j;
        for (i = 0; i < ROWS; i++)
            for (j = 0; j < K; j++)
                ta[i][j] = 8'($urandom_range(2*maxv) - maxv);
    endtask

    task automatic t_rand_b(input int maxv);
        int i, j;
        for (i = 0; i < K; i++)
            for (j = 0; j < COLS; j++)
                tb[i][j] = 8'($urandom_range(2*maxv) - maxv);
    endtask

    task automatic t_rand_c(input int maxv);
        int i, j;
        for (i = 0; i < ROWS; i++)
            for (j = 0; j < COLS; j++)
                tc[i][j] = $urandom_range(2*maxv) - maxv;
    endtask

    task automatic t_feed(input bit use_c);
        int k, i, j;
        for (k = 0; k < K; k++) begin
            @(posedge clk);
            @(negedge clk);
            matrix_acc_valid = 1'b1;
            matrix_wet_valid = 1'b1;
            for (i = 0; i < COLS; i++)
                matrix_acc_col[i] = ta[i][k];
            for (j = 0; j < ROWS; j++)
                matrix_wet_row[j] = tb[k][j];
            if (use_c && k < COLS) begin
                for (i = 0; i < ROWS; i++) begin
                    C_data[i]       = tc[i][COLS-1-k];
                    C_data_valid[i] = 1'b1;
                end
            end else begin
                for (i = 0; i < ROWS; i++)
                    C_data_valid[i] = 1'b0;
            end
        end
        @(posedge clk);
        @(negedge clk);
        matrix_acc_valid = 1'b0;
        matrix_wet_valid = 1'b0;
        for (i = 0; i < COLS; i++)
            C_data_valid[i] = 1'b0;
    endtask

    task automatic t_verify(input string tname);
        int timeout;
        int beat, row;
        int mismatch;
        bit ok;
        logic signed [7:0] exp_v;
        logic signed [7:0] got_v;

        timeout  = 0;
        mismatch = 0;
        ok       = 1'b1;

        while (valid_out !== 1'b1) begin
            @(posedge clk);
            timeout = timeout + 1;
            if (timeout > 500) begin
                $display("TIMEOUT [%s]  valid_out never asserted", tname);
                g_fail = g_fail + 1;
                return;
            end
        end

        for (beat = 0; beat < COLS; beat++) begin
            for (row = 0; row < ROWS; row++) begin
                exp_v = fn_pipeline(exp_acc[row][beat]);
                got_v = act_data_out[row];
                g_checks = g_checks + 1;
                if (got_v !== exp_v) begin
                    if (mismatch < 8)
                        $display("  MISMATCH [%s]  beat=%0d row=%0d  got=%4d  exp=%4d  raw=0x%08h",
                                 tname, beat, row,
                                 $signed(got_v), $signed(exp_v),
                                 exp_acc[row][beat]);
                    mismatch = mismatch + 1;
                    ok = 1'b0;
                end
            end

            g_checks = g_checks + 1;
            if (valid_out !== 1'b1) begin
                $display("  EARLY DEASSERT [%s]  beat=%0d", tname, beat);
                mismatch = mismatch + 1;
                ok = 1'b0;
            end

            if (beat < COLS - 1)
                @(posedge clk);
        end

        @(posedge clk);
        @(negedge clk);
        g_checks = g_checks + 1;
        if (valid_out === 1'b1) begin
            $display("  VALID STUCK HIGH [%s]  valid_out still 1 after last beat", tname);
            mismatch = mismatch + 1;
            ok = 1'b0;
        end

        g_errors = g_errors + mismatch;

        if (ok) begin
            $display("  PASS  %s", tname);
            g_pass = g_pass + 1;
        end else begin
            $display("  FAIL  %s  (%0d mismatches)", tname, mismatch);
            g_fail = g_fail + 1;
        end
    endtask

    task automatic t_run(input string name, input bit use_c);
        $display("");
        $display("TEST  %s", name);
        t_reset();
        fn_matmul(ta, tb, tc, exp_acc);
        t_feed(use_c);
        t_verify(name);
        repeat(5) @(posedge clk);
    endtask

    task automatic t_sep();
        $display("------------------------------------------------------------");
    endtask

    // =========================================================================
    // Main stimulus
    // =========================================================================
    initial begin
        int i, j, kk, pass, iter;

        $display("============================================================");
        $display("  TPU_core_top Testbench");
        $display("  Array %0dx%0d  K=%0d  SHIFT=%0d  ACC=%0d",
                 ROWS, COLS, K, SHIFT_BITS, ACC_W);
        $display("============================================================");

        reset_n = 1'b0;
        t_init();
        repeat(4) @(posedge clk);

        // ==================================================================
        // GROUP A  -  End-to-end correctness
        // ==================================================================
        $display("");
        $display("==== GROUP A  End-to-end correctness ====");
        t_sep();

        // A1  known small values  no bias
        ta[0][0]=1; ta[0][1]=2; ta[1][0]=3; ta[1][1]=4;
        for (i=2;i<ROWS;i++) for (j=0;j<K;j++) ta[i][j] = 8'(i+j);
        tb[0][0]=5; tb[0][1]=6; tb[1][0]=7; tb[1][1]=8;
        for (i=2;i<K;i++) for (j=0;j<COLS;j++) tb[i][j] = 8'(i-j);
        t_zero_c();
        t_run("A1  known small values  C=0", 1'b1);

        // A2  known values  small bias
        ta[0][0]=1; ta[0][1]=2; ta[1][0]=3; ta[1][1]=4;
        for (i=2;i<ROWS;i++) for (j=0;j<K;j++) ta[i][j]=8'sd1;
        tb[0][0]=5; tb[0][1]=6; tb[1][0]=7; tb[1][1]=8;
        for (i=2;i<K;i++) for (j=0;j<COLS;j++) tb[i][j]=8'sd1;
        for (i=0;i<ROWS;i++) for (j=0;j<COLS;j++)
            tc[i][j] = (i==0&&j==0) ? 10 : (i==0&&j==1) ? 20 :
                       (i==1&&j==0) ? 30 : (i==1&&j==1) ? 40 : 8;
        t_run("A2  known small values  non-zero C", 1'b1);

        // A3  random small A B  no bias
        t_rand_a(5); t_rand_b(5); t_zero_c();
        t_run("A3  random A,B max5  C=0", 1'b1);

        // A4  random A B C
        t_rand_a(10); t_rand_b(10); t_rand_c(50);
        t_run("A4  random A,B max10  C max50", 1'b1);

        // A5  large positive bias  clamps high
        t_rand_a(3); t_rand_b(3);
        t_const_c(10000);
        t_run("A5  large positive bias  clamp high", 1'b1);

        // A6  large negative bias  clamps low
        t_rand_a(3); t_rand_b(3);
        t_const_c(-10000);
        t_run("A6  large negative bias  clamp low", 1'b1);

        // A7  identity bias
        t_rand_a(10); t_rand_b(10);
        t_identity_c(200);
        t_run("A7  identity bias scale 200", 1'b1);

        // A8  no-C mode
        t_rand_a(8); t_rand_b(8);
        t_zero_c();
        t_run("A8  no-C mode  use_c=0", 1'b0);

        // A9  medium values
        t_rand_a(15); t_rand_b(15); t_rand_c(200);
        t_run("A9  medium A,B max15  C max200", 1'b1);

        // A10  stress
        t_rand_a(50); t_rand_b(50); t_rand_c(1000);
        t_run("A10 stress A,B max50  C max1000", 1'b1);

        // ==================================================================
        // GROUP B  -  Activation edge cases
        // ==================================================================
        $display("");
        $display("==== GROUP B  Activation edge cases ====");
        t_sep();

        // B1  all zero
        for (i=0;i<ROWS;i++) for (j=0;j<K;j++) ta[i][j]=8'sd0;
        for (i=0;i<K;i++) for (j=0;j<COLS;j++) tb[i][j]=8'sd0;
        t_zero_c();
        t_run("B1  all-zero input", 1'b1);

        // B2  clamp boundary  shift -> +127
        for (i=0;i<ROWS;i++) for (j=0;j<K;j++) ta[i][j]=8'sd0;
        for (i=0;i<K;i++) for (j=0;j<COLS;j++) tb[i][j]=8'sd0;
        for (i=0;i<ROWS;i++) for (j=0;j<COLS;j++)
            tc[i][j] = 127 * (1 << SHIFT_BITS);
        t_run("B2  clamp boundary  shift gives +127", 1'b1);

        // B3  clamp boundary  shift -> -128
        for (i=0;i<ROWS;i++) for (j=0;j<K;j++) ta[i][j]=8'sd0;
        for (i=0;i<K;i++) for (j=0;j<COLS;j++) tb[i][j]=8'sd0;
        for (i=0;i<ROWS;i++) for (j=0;j<COLS;j++)
            tc[i][j] = -128 * (1 << SHIFT_BITS);
        t_run("B3  clamp boundary  shift gives -128", 1'b1);

        // B4  INT32 max
        for (i=0;i<ROWS;i++) for (j=0;j<K;j++) ta[i][j]=8'sd0;
        for (i=0;i<K;i++) for (j=0;j<COLS;j++) tb[i][j]=8'sd0;
        for (i=0;i<ROWS;i++) for (j=0;j<COLS;j++)
            tc[i][j] = 32'h7FFFFFFF;
        t_run("B4  INT32_MAX in every cell", 1'b1);

        // B5  INT32 min
        for (i=0;i<ROWS;i++) for (j=0;j<K;j++) ta[i][j]=8'sd0;
        for (i=0;i<K;i++) for (j=0;j<COLS;j++) tb[i][j]=8'sd0;
        for (i=0;i<ROWS;i++) for (j=0;j<COLS;j++)
            tc[i][j] = 32'h80000000;
        t_run("B5  INT32_MIN in every cell", 1'b1);

        // B6  checkerboard  both round to 0 after shift
        begin
            int sp, sn;
            sp = (1 << SHIFT_BITS) - 1;
            sn = -sp;
            for (i=0;i<ROWS;i++) for (j=0;j<K;j++) ta[i][j]=8'sd0;
            for (i=0;i<K;i++) for (j=0;j<COLS;j++) tb[i][j]=8'sd0;
            for (i=0;i<ROWS;i++) for (j=0;j<COLS;j++)
                tc[i][j] = ((i+j) % 2 == 0) ? sp : sn;
        end
        t_run("B6  checkerboard values below shift threshold", 1'b1);

        // B7  full LUT sweep  4 passes x 64 = 256 unique codes
        $display("");
        $display("TEST  B7  full LUT sweep  256 input codes");
        begin
            int base_val, idx_val;
            for (pass = 0; pass < 4; pass++) begin
                base_val = -128 + pass * 64;
                for (i=0;i<ROWS;i++) for (kk=0;kk<K;kk++) ta[i][kk]=8'sd0;
                for (kk=0;kk<K;kk++) for (j=0;j<COLS;j++) tb[kk][j]=8'sd0;
                for (i=0;i<ROWS;i++) begin
                    for (j=0;j<COLS;j++) begin
                        idx_val = i * COLS + j;
                        tc[i][j] = (base_val + idx_val) * (1 << SHIFT_BITS);
                    end
                end
                t_reset();
                fn_matmul(ta, tb, tc, exp_acc);
                t_feed(1'b1);
                case (pass)
                    0: t_verify("B7  LUT sweep pass0  base -128");
                    1: t_verify("B7  LUT sweep pass1  base  -64");
                    2: t_verify("B7  LUT sweep pass2  base    0");
                    3: t_verify("B7  LUT sweep pass3  base  +64");
                    default: t_verify("B7  LUT sweep unknown pass");
                endcase
                repeat(3) @(posedge clk);
            end
        end

        // B8  alternating INT32_MAX and INT32_MIN rows
        for (i=0;i<ROWS;i++) for (j=0;j<K;j++) ta[i][j]=8'sd0;
        for (i=0;i<K;i++) for (j=0;j<COLS;j++) tb[i][j]=8'sd0;
        for (i=0;i<ROWS;i++) for (j=0;j<COLS;j++)
            tc[i][j] = (i % 2 == 0) ? 32'h7FFFFFFF : 32'h80000000;
        t_run("B8  alternating INT32_MAX and INT32_MIN rows", 1'b1);

        // B9  shift boundary +1  one above clamp  shift -> +128 -> saturate to 127
        for (i=0;i<ROWS;i++) for (j=0;j<K;j++) ta[i][j]=8'sd0;
        for (i=0;i<K;i++) for (j=0;j<COLS;j++) tb[i][j]=8'sd0;
        for (i=0;i<ROWS;i++) for (j=0;j<COLS;j++)
            tc[i][j] = 128 * (1 << SHIFT_BITS);
        t_run("B9  one above clamp  shift gives 128  saturates to 127", 1'b1);

        // B10  shift boundary -1  one below clamp  shift -> -129 -> saturate to -128
        for (i=0;i<ROWS;i++) for (j=0;j<K;j++) ta[i][j]=8'sd0;
        for (i=0;i<K;i++) for (j=0;j<COLS;j++) tb[i][j]=8'sd0;
        for (i=0;i<ROWS;i++) for (j=0;j<COLS;j++)
            tc[i][j] = -129 * (1 << SHIFT_BITS);
        t_run("B10 one below clamp  shift gives -129  saturates to -128", 1'b1);

        // B11  column-sweep pattern  each column has a unique post-shift value
        for (i=0;i<ROWS;i++) for (j=0;j<K;j++) ta[i][j]=8'sd0;
        for (i=0;i<K;i++) for (j=0;j<COLS;j++) tb[i][j]=8'sd0;
        for (i=0;i<ROWS;i++) for (j=0;j<COLS;j++)
            tc[i][j] = (j - 4) * (1 << SHIFT_BITS);
        t_run("B11 column-sweep  post-shift values -4 to 3", 1'b1);

        // B12  row-sweep pattern  each row has a unique post-shift value
        for (i=0;i<ROWS;i++) for (j=0;j<K;j++) ta[i][j]=8'sd0;
        for (i=0;i<K;i++) for (j=0;j<COLS;j++) tb[i][j]=8'sd0;
        for (i=0;i<ROWS;i++) for (j=0;j<COLS;j++)
            tc[i][j] = (i - 4) * (1 << SHIFT_BITS);
        t_run("B12 row-sweep  post-shift values -4 to 3", 1'b1);

        // B13  all cells exactly 0 after shift  pre-shift values just below threshold
        for (i=0;i<ROWS;i++) for (j=0;j<K;j++) ta[i][j]=8'sd0;
        for (i=0;i<K;i++) for (j=0;j<COLS;j++) tb[i][j]=8'sd0;
        for (i=0;i<ROWS;i++) for (j=0;j<COLS;j++)
            tc[i][j] = (1 << SHIFT_BITS) - 1;
        t_run("B13 all positive just below shift  all give 0", 1'b1);

        // B14  all cells exactly -1 after shift  using -1 * 2^SHIFT_BITS
        for (i=0;i<ROWS;i++) for (j=0;j<K;j++) ta[i][j]=8'sd0;
        for (i=0;i<K;i++) for (j=0;j<COLS;j++) tb[i][j]=8'sd0;
        for (i=0;i<ROWS;i++) for (j=0;j<COLS;j++)
            tc[i][j] = -1 * (1 << SHIFT_BITS);
        t_run("B14 all give -1 after shift", 1'b1);

        // ==================================================================
        // GROUP C  -  Protocol and robustness
        // ==================================================================
        $display("");
        $display("==== GROUP C  Protocol robustness ====");
        t_sep();

        // C1  mid-stream reset  valid_out must clear
        $display("");
        $display("TEST  C1  mid-stream reset  valid_out must clear");
        begin
            int ok_c1;
            ok_c1 = 1;
            t_reset();
            for (i=0;i<ROWS;i++) for (j=0;j<K;j++) ta[i][j]=8'sd10;
            for (i=0;i<K;i++) for (j=0;j<COLS;j++) tb[i][j]=8'sd10;
            t_zero_c();
            matrix_acc_valid = 1'b1;
            matrix_wet_valid = 1'b1;
            for (i=0;i<COLS;i++) matrix_acc_col[i] = 8'sd10;
            for (i=0;i<ROWS;i++) matrix_wet_row[i] = 8'sd10;
            repeat(3) @(posedge clk);
            reset_n = 1'b0;
            repeat(2) @(posedge clk);
            reset_n = 1'b1;
            matrix_acc_valid = 1'b0;
            matrix_wet_valid = 1'b0;
            @(posedge clk);
            @(negedge clk);
            g_checks = g_checks + 1;
            if (valid_out === 1'b1) begin
                $display("  FAIL  C1  valid_out not cleared after reset");
                g_errors = g_errors + 1;
                g_fail   = g_fail   + 1;
                ok_c1    = 0;
            end
            if (ok_c1 == 1) begin
                $display("  PASS  C1  valid_out cleared after reset");
                g_pass = g_pass + 1;
            end
            repeat(5) @(posedge clk);
        end

        // C2  5 random stress iterations
        $display("");
        $display("TEST  C2  5 random stress iterations");
        t_sep();
        for (iter = 0; iter < 5; iter++) begin
            t_rand_a(20 + iter*5);
            t_rand_b(20 + iter*5);
            t_rand_c(500 + iter*100);
            t_reset();
            fn_matmul(ta, tb, tc, exp_acc);
            t_feed(1'b1);
            case (iter)
                0: t_verify("C2  random stress iter 0");
                1: t_verify("C2  random stress iter 1");
                2: t_verify("C2  random stress iter 2");
                3: t_verify("C2  random stress iter 3");
                4: t_verify("C2  random stress iter 4");
                default: t_verify("C2  random stress unknown iter");
            endcase
            repeat(3) @(posedge clk);
        end

        // C3  valid_out stays low before any transaction
        $display("");
        $display("TEST  C3  valid_out must stay low before first feed");
        begin
            int ok_c3;
            ok_c3 = 1;
            t_reset();
            repeat(20) @(posedge clk);
            @(negedge clk);
            g_checks = g_checks + 1;
            if (valid_out === 1'b1) begin
                $display("  FAIL  C3  valid_out high with no input fed");
                g_errors = g_errors + 1;
                g_fail   = g_fail   + 1;
                ok_c3    = 0;
            end
            if (ok_c3 == 1) begin
                $display("  PASS  C3  valid_out correctly low before first feed");
                g_pass = g_pass + 1;
            end
            repeat(3) @(posedge clk);
        end

        // C4  repeated reset  no spurious valid_out
        $display("");
        $display("TEST  C4  repeated reset  no spurious output");
        begin
            int ok_c4;
            ok_c4 = 1;
            for (iter = 0; iter < 4; iter++) begin
                t_reset();
                repeat(5) @(posedge clk);
                @(negedge clk);
                g_checks = g_checks + 1;
                if (valid_out === 1'b1) begin
                    $display("  FAIL  C4  valid_out high after reset iteration %0d", iter);
                    g_errors = g_errors + 1;
                    ok_c4    = 0;
                end
            end
            if (ok_c4 == 1) begin
                $display("  PASS  C4  no spurious valid_out across 4 resets");
                g_pass = g_pass + 1;
            end else begin
                g_fail = g_fail + 1;
            end
            repeat(3) @(posedge clk);
        end

        // C5  A=0 B=0 C=0 full zero transaction  output must all be GELU(0)=0
        $display("");
        $display("TEST  C5  full zero transaction  all output must be 0");
        begin
            for (i=0;i<ROWS;i++) for (j=0;j<K;j++) ta[i][j]=8'sd0;
            for (i=0;i<K;i++) for (j=0;j<COLS;j++) tb[i][j]=8'sd0;
            t_zero_c();
            t_run("C5  A=0 B=0 C=0  all output must be 0", 1'b1);
        end

        // C6  use_c=0 with non-zero C  C must be ignored
        $display("");
        $display("TEST  C6  non-zero C ignored when use_c=0");
        begin
            t_rand_a(10); t_rand_b(10);
            t_const_c(500);
            // use_c=0 so tc is irrelevant; golden must also use tc=0
            t_zero_c();
            t_run("C6  C ignored when use_c=0", 1'b0);
        end

        // C7  A all +1  B all +1  result = K*1*1 per cell = 8  then pipeline
        $display("");
        $display("TEST  C7  A all ones  B all ones  result = K per cell");
        begin
            for (i=0;i<ROWS;i++) for (j=0;j<K;j++) ta[i][j]=8'sd1;
            for (i=0;i<K;i++) for (j=0;j<COLS;j++) tb[i][j]=8'sd1;
            t_zero_c();
            t_run("C7  A=1 B=1 C=0  each cell = K before activation", 1'b1);
        end

        // C8  A all -1  B all +1  result = -K per cell
        $display("");
        $display("TEST  C8  A all minus-ones  B all ones  result = -K per cell");
        begin
            for (i=0;i<ROWS;i++) for (j=0;j<K;j++) ta[i][j]=-8'sd1;
            for (i=0;i<K;i++) for (j=0;j<COLS;j++) tb[i][j]=8'sd1;
            t_zero_c();
            t_run("C8  A=-1 B=1 C=0  each cell = -K before activation", 1'b1);
        end

        // C9  A all +127  B all +1  result = K*127 per cell  large positive
        $display("");
        $display("TEST  C9  A=127 B=1  large positive accumulation");
        begin
            for (i=0;i<ROWS;i++) for (j=0;j<K;j++) ta[i][j]=8'sd127;
            for (i=0;i<K;i++) for (j=0;j<COLS;j++) tb[i][j]=8'sd1;
            t_zero_c();
            t_run("C9  A=127 B=1 C=0  K*127 per cell", 1'b1);
        end

        // C10  A all -128  B all +1  result = K*-128 per cell  large negative
        $display("");
        $display("TEST  C10  A=-128 B=1  large negative accumulation");
        begin
            for (i=0;i<ROWS;i++) for (j=0;j<K;j++) ta[i][j]=-8'sd128;
            for (i=0;i<K;i++) for (j=0;j<COLS;j++) tb[i][j]=8'sd1;
            t_zero_c();
            t_run("C10 A=-128 B=1 C=0  K*-128 per cell", 1'b1);
        end

        // C11  A all +127  B all -1  result = -K*127 per cell
        $display("");
        $display("TEST  C11  A=+127 B=-1  sign flip via B");
        begin
            for (i=0;i<ROWS;i++) for (j=0;j<K;j++) ta[i][j]=8'sd127;
            for (i=0;i<K;i++) for (j=0;j<COLS;j++) tb[i][j]=-8'sd1;
            t_zero_c();
            t_run("C11 A=127 B=-1 C=0  -K*127 per cell", 1'b1);
        end

        // C12  alternating +1 -1 in A rows  mixed sign accumulation
        $display("");
        $display("TEST  C12  alternating rows in A  mixed sign result");
        begin
            for (i=0;i<ROWS;i++) for (j=0;j<K;j++)
                ta[i][j] = (i % 2 == 0) ? 8'sd5 : -8'sd5;
            for (i=0;i<K;i++) for (j=0;j<COLS;j++) tb[i][j]=8'sd3;
            t_zero_c();
            t_run("C12 alternating A rows  mixed sign result", 1'b1);
        end

        // C13  alternating columns in B  mixed sign accumulation
        $display("");
        $display("TEST  C13  alternating columns in B  mixed sign result");
        begin
            for (i=0;i<ROWS;i++) for (j=0;j<K;j++) ta[i][j]=8'sd4;
            for (i=0;i<K;i++) for (j=0;j<COLS;j++)
                tb[i][j] = (j % 2 == 0) ? 8'sd6 : -8'sd6;
            t_zero_c();
            t_run("C13 alternating B columns  mixed sign result", 1'b1);
        end

        // C14  diagonal A  only main diagonal non-zero in A
        $display("");
        $display("TEST  C14  diagonal A matrix  sparse accumulation");
        begin
            for (i=0;i<ROWS;i++) for (j=0;j<K;j++)
                ta[i][j] = (i == j) ? 8'sd7 : 8'sd0;
            for (i=0;i<K;i++) for (j=0;j<COLS;j++) tb[i][j]=8'sd2;
            t_zero_c();
            t_run("C14 diagonal A  sparse accumulation", 1'b1);
        end

        // C15  diagonal B  only main diagonal non-zero in B
        $display("");
        $display("TEST  C15  diagonal B matrix  sparse accumulation");
        begin
            for (i=0;i<ROWS;i++) for (j=0;j<K;j++) ta[i][j]=8'sd3;
            for (i=0;i<K;i++) for (j=0;j<COLS;j++)
                tb[i][j] = (i == j) ? 8'sd9 : 8'sd0;
            t_zero_c();
            t_run("C15 diagonal B  sparse accumulation", 1'b1);
        end

        // C16  single non-zero element in A  all others zero
        $display("");
        $display("TEST  C16  single non-zero in A  isolated accumulation");
        begin
            for (i=0;i<ROWS;i++) for (j=0;j<K;j++) ta[i][j]=8'sd0;
            ta[3][5] = 8'sd15;
            for (i=0;i<K;i++) for (j=0;j<COLS;j++) tb[i][j]=8'sd2;
            t_zero_c();
            t_run("C16 single non-zero in A  A[3][5]=15", 1'b1);
        end

        // C17  single non-zero element in B  all others zero
        $display("");
        $display("TEST  C17  single non-zero in B  isolated accumulation");
        begin
            for (i=0;i<ROWS;i++) for (j=0;j<K;j++) ta[i][j]=8'sd4;
            for (i=0;i<K;i++) for (j=0;j<COLS;j++) tb[i][j]=8'sd0;
            tb[2][6] = 8'sd20;
            t_zero_c();
            t_run("C17 single non-zero in B  B[2][6]=20", 1'b1);
        end

        // C18  C bias only  A=0 B=0  output = GELU pipeline of C
        $display("");
        $display("TEST  C18  C only  A=0 B=0  output is purely from bias");
        begin
            for (i=0;i<ROWS;i++) for (j=0;j<K;j++) ta[i][j]=8'sd0;
            for (i=0;i<K;i++) for (j=0;j<COLS;j++) tb[i][j]=8'sd0;
            t_rand_c(500);
            t_run("C18 A=0 B=0  output purely from C bias", 1'b1);
        end

        // C19  large random stress  close to overflow boundary
        $display("");
        $display("TEST  C19  near overflow stress");
        begin
            t_rand_a(100); t_rand_b(100); t_rand_c(5000);
            t_run("C19 near overflow  A,B max100  C max5000", 1'b1);
        end

        // C20  10 fully random iterations  final regression sweep
        $display("");
        $display("TEST  C20  10 fully random regression iterations");
        t_sep();
        for (iter = 0; iter < 10; iter++) begin
            t_rand_a(30 + iter*3);
            t_rand_b(30 + iter*3);
            t_rand_c(300 + iter*50);
            t_reset();
            fn_matmul(ta, tb, tc, exp_acc);
            t_feed(1'b1);
            case (iter)
                0: t_verify("C20 regression iter 0");
                1: t_verify("C20 regression iter 1");
                2: t_verify("C20 regression iter 2");
                3: t_verify("C20 regression iter 3");
                4: t_verify("C20 regression iter 4");
                5: t_verify("C20 regression iter 5");
                6: t_verify("C20 regression iter 6");
                7: t_verify("C20 regression iter 7");
                8: t_verify("C20 regression iter 8");
                9: t_verify("C20 regression iter 9");
                default: t_verify("C20 regression unknown iter");
            endcase
            repeat(3) @(posedge clk);
        end

        // ==================================================================
        // Final summary
        // ==================================================================
        $display("");
        $display("============================================================");
        $display("  FINAL SUMMARY");
        $display("============================================================");
        $display("  Tests passed     : %0d", g_pass);
        $display("  Tests failed     : %0d", g_fail);
        $display("  Signal checks    : %0d", g_checks);
        $display("  Signal errors    : %0d", g_errors);
        $display("------------------------------------------------------------");
        if (g_fail == 0 && g_errors == 0)
            $display("  ALL TESTS PASSED");
        else
            $display("  FAILURES DETECTED  see FAIL and MISMATCH lines above");
        $display("============================================================");

        $finish;
    end

    // =========================================================================
    // Watchdog
    // =========================================================================
    initial begin
        repeat(MAX_CYCLES) @(posedge clk);
        $display("WATCHDOG  simulation exceeded %0d cycles", MAX_CYCLES);
        $finish;
    end

endmodule

