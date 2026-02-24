// this  file take the data of matrix after 12 cycle and then i will transfer it into 8 byte striming data
// for other to maintain the data flow and also to make sure that we are feeding the data at the same cycle for 
//a b and c and we are also making sure that we are feeding the data of c at the same cycle when we are feeding
// the data of a and b and we are also making sure that we are feeding the data of c to the whole systolic
// array and we are also making sure that we are feeding the signal for c_valid to the whole systolic array
// and we are also making sure that we are feeding the signal for c_lock to the whole systolic array and 
//we are also making sure that we are not feeding the data after done is asserted
`timescale 1ns/1ps

module data_lane #(
    parameter ROWS  = 8,
    parameter COLS  = 8,
    parameter ACC_W = 32
)(
    input  logic clk,
    input  logic reset_n,

    input  logic signed [ACC_W-1:0] mac_data [ROWS][COLS],
    input  logic mac_done,

    output logic signed [ACC_W-1:0] data_out [ROWS],
    output logic valid_out,
    output logic stream_done
);

    // Buffer (stores full matrix row-major)
    logic signed [ACC_W-1:0] acc_buffer [ROWS*COLS];

    // Column pointer for streaming
    logic [$clog2(COLS)-1:0] col_ptr;

    // FSM
    typedef enum logic [1:0] {
        IDLE,
        LOAD,
        STREAM,
        DONE
    } state_t;

    state_t state, next_state;

    // FSM Sequential
    always_ff @(posedge clk) begin
        if (!reset_n)
            state <= IDLE;
        else
            state <= next_state;
    end

    // FSM Combinational
    always_comb begin
        next_state = state;

        unique case (state)

            IDLE: begin
                if (mac_done)
                    next_state = LOAD;
            end

            LOAD: begin
                next_state = STREAM;
            end

            STREAM: begin
                if (col_ptr == 3'(COLS-1))
                    next_state = DONE;
            end

            DONE: begin
                next_state = IDLE;
            end

        endcase
    end

    // Data Path
    integer i, j;

    always_ff @(posedge clk) begin
        if (!reset_n) begin

            col_ptr    <= 0;
            valid_out  <= 0;
            stream_done <= 0;

            for (i = 0; i < ROWS*COLS; i++)
                acc_buffer[i] <= '0;

        end else begin

            case (state)

                // LOAD FULL MATRIX (1 cycle)

                LOAD: begin
                    for (i = 0; i < ROWS; i++) begin
                        for (j = 0; j < COLS; j++) begin
                            acc_buffer[i*COLS + j] <= mac_data[i][j];
                        end
                    end
                    col_ptr <= 0;
                    valid_out <= 0;
                    stream_done <= 0;
                end
                // i want this coloum wise striming because it is very easy to maintain the data flow
                // COLUMN-WISE STREAMING
                STREAM: begin
                    for (i = 0; i < ROWS; i++) begin
                        data_out[i] <= acc_buffer[6'(i*COLS + 32'(col_ptr))];
                    end

                    col_ptr <= col_ptr + 1;
                    valid_out <= 1;
                end

                // DONE
                DONE: begin
                    valid_out   <= 0;
                    stream_done <= 1;
                end

                default: begin
                    valid_out   <= 0;
                    stream_done <= 0;
                end

            endcase
        end
    end

endmodule
