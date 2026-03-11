`timescale 1ns/1ps

module bias_controller #(
   // parameter int BIAS_WIDTH = 32,
    parameter int PE_COLS    = 8
)(
    input  logic clk,
    input  logic reset_n,
    input  logic bias_valid,
    input  bias_pkg::buffer_type_t bias_type,

    output logic streaming_valid,
    output logic streaming_start,
    output logic streaming_end,
    output logic bias_ready,
    output logic bias_ready_full_matrix,
    output logic [1:0] buffer_select_load,
    output logic [1:0] buffer_select_stream,
    output logic buffer_read,
    output logic buffer_write
);

logic streaming_valid_reg ;
assign streaming_valid = streaming_valid_reg && ~streaming_end;
// MAIN FSM
  logic stream_end_reg ;
  always_ff@(posedge clk ) begin
    if(!reset_n) begin
     streaming_end <= '0;
    end
    else begin
        streaming_end <= stream_end_reg;
    end
  end
typedef enum logic [1:0] {
    BUF_IDLE,
    BUF_LOAD,
    BUF_READY
} bias_state_t;

bias_state_t state, next_state;


// BUFFER FSM


typedef enum logic [1:0] {
    BUFFER_READY,
    BUFFER_LOAD,
    BUFFER_STREAM
} buffer_state_t;

buffer_state_t stateA, next_stateA;
buffer_state_t stateB, next_stateB;
buffer_state_t stateC, next_stateC;


// COUNTERS


logic [$clog2(PE_COLS):0] loadcounterA;
logic [$clog2(PE_COLS):0] loadcounterB;
logic [$clog2(PE_COLS)+3:0] loadcounterC;
logic [$clog2(PE_COLS):0] stream_counter;


// COUNTER LOGIC
logic [3:0] counter, next_counter;
logic bias_valid_reg;
logic readyA;
logic readyB;
logic readyC;

always_comb begin
    next_counter = counter;

    if (bias_valid && (bias_type == 2'b00)) begin
        next_counter = 4'd1;     // start counting
    end
    else if (bias_valid_reg) begin
        next_counter = counter + 1;
    end else if (next_counter == 4'd8)begin 
        next_counter = 0;
    end
end


always_ff @(posedge clk ) begin
    if(!reset_n) begin
        counter <= 0;
        bias_valid_reg <= 0;
    end
    else begin
        counter <= next_counter;

        // start valid
        if(bias_valid)
            bias_valid_reg <= 1;

        // stop after 8 cycles
        if(next_counter == 4'd8)begin
            bias_valid_reg <= 0;
           // next_counter <= 0;
        end
    end
end


always_ff @(posedge clk) begin
    if(!reset_n)
        loadcounterA <= 0;
    else if(bias_valid_reg)
        loadcounterA <= loadcounterA + 1;
    else
        loadcounterA <= 0;
end

always_ff @(posedge clk ) begin
    if(!reset_n)
        loadcounterB <= 0;
    else if(bias_valid_reg)
        loadcounterB <= loadcounterB + 1;
    else
        loadcounterB <= 0;
end

always_ff @(posedge clk ) begin
    if(!reset_n)
        loadcounterC <= 0;
    else if(bias_valid|| (bias_type == BUFFER_NUN))
        loadcounterC <= loadcounterC + 1;
    else
        loadcounterC <= 0;
end

always_ff @(posedge clk ) begin
    if(!reset_n)
        stream_counter <= 0;
    else if( streaming_valid )
        stream_counter <= stream_counter + 1;
    else
        stream_counter <= 0;
end


// STATE REGISTERS


always_ff @(posedge clk )
    if(!reset_n) state <= BUF_IDLE;
    else state <= next_state;

always_ff @(posedge clk )
    if(!reset_n) stateA <= BUFFER_READY;
    else stateA <= next_stateA;

always_ff @(posedge clk )
    if(!reset_n) stateB <= BUFFER_READY;
    else stateB <= next_stateB;

always_ff @(posedge clk )
    if(!reset_n) stateC <= BUFFER_READY;
    else stateC <= next_stateC;


// MAIN FSM NEXT STATE


always_comb begin

    next_state = state;

  unique  case(state)

        BUF_IDLE:
            if(bias_valid)
                next_state = BUF_LOAD;

        BUF_LOAD:
            if(stateA == BUFFER_READY ||
               stateB == BUFFER_READY ||
               (stateC == BUFFER_READY && bias_type == BUFFER_FULL))
                next_state = BUF_READY;

        BUF_READY:
            if(bias_valid)
                next_state = BUF_IDLE;

    endcase

end

// BUFFER A FSM
logic lock ;
always_comb begin

    next_stateA = stateA;
     lock = 1'b1;
     readyA = 1'b1;
  unique  case(stateA)

        BUFFER_READY: begin
            if((bias_valid_reg || bias_valid) && !lock2 && (bias_type != 2'b10)) begin
                next_stateA = BUFFER_LOAD;
            end
            lock = 1'b1;
             readyA = 1'b1;
        end

        BUFFER_LOAD:begin
            if(stateC != BUFFER_STREAM && stateB != BUFFER_STREAM)begin
                next_stateA = BUFFER_STREAM;
                 readyA = 1'b0;
            end
           readyA = 1'b0;
        end
        BUFFER_STREAM:  begin
            if(stream_counter == 4'(PE_COLS))begin
                next_stateA = BUFFER_READY;
              //  streaming_valid = 0;
            end
             lock =  1'b0;
             readyA = 1'b0;
        end


    endcase

end


// BUFFER B FSM

logic lock2 ;
always_comb begin

    next_stateB = stateB;
    lock2 = 1'b0;
    readyB = 1'b1;
  unique  case(stateB)

        BUFFER_READY: begin
            if((bias_valid_reg || bias_valid) && !lock&& (bias_type != 2'b10 ))begin
                next_stateB = BUFFER_LOAD;
                readyB = 1'b0;
            end
        readyB = 1'b1;
        end
        BUFFER_LOAD:begin
            if( stateA != BUFFER_STREAM && stateC != BUFFER_STREAM ) begin
                next_stateB = BUFFER_STREAM;
            end
            readyB = 1'b0;
            lock2 = 1'b1;
        end
        BUFFER_STREAM: begin
            if(stream_counter == 4'(PE_COLS)) begin
                next_stateB = BUFFER_READY;

            end
            lock2 = 1'b0;
            readyB = 1'b0;
        end
    endcase

end
// BUFFER C FSM
always_comb begin

    next_stateC = stateC;
     readyC = 1'b1;
  unique  case(stateC)

        BUFFER_READY: begin
           if(bias_valid && bias_type == BUFFER_FULL && stateA != BUFFER_LOAD && stateB != BUFFER_LOAD )begin
                next_stateC = BUFFER_LOAD;
           end
          readyC = 1'b1;
        end
        BUFFER_LOAD:begin
            if(loadcounterC == 7'd64 && stateA != BUFFER_STREAM && stateB != BUFFER_STREAM)begin
                next_stateC = BUFFER_STREAM;
            end
          readyC = 1'b0;
        end

        BUFFER_STREAM: begin
            if(stream_counter == 4'(PE_COLS))begin
                next_stateC = BUFFER_READY;
               // streaming_valid = 0;
            end
        readyC = 1'b0;
        end
    endcase

end

always_comb begin

    streaming_valid_reg = 0;
    streaming_start = 0;
    stream_end_reg   = 0;

    buffer_select_load  = 0;
    buffer_read     = 0;
    buffer_write    = 0;
    buffer_select_stream = 0;
    //----------------------------
    // BUFFER A CONTROL
    //----------------------------

    if(stateA == BUFFER_LOAD) begin
        buffer_select_load = 2'b00;
        buffer_write  = 1;
    end

    if(stateA == BUFFER_STREAM) begin
        buffer_select_stream = 2'b00;
        buffer_read   = 1;
        streaming_valid_reg = 1;

        if(stream_counter == 1)
            streaming_start = 1;

        if(stream_counter == 4'(PE_COLS))
            stream_end_reg = 1;
    end


    // BUFFER B CONTROL

    if(stateB == BUFFER_LOAD) begin
        buffer_select_load = 2'b01;
        buffer_write  = 1;
    end

    if(stateB == BUFFER_STREAM) begin
        buffer_select_stream = 2'b01;
        buffer_read   = 1;
        streaming_valid_reg = 1;

        if(stream_counter == 1)
            streaming_start = 1;

        if(stream_counter == 4'(PE_COLS))
            stream_end_reg = 1;
    end
   // bufferC  controle
     if(stateC == BUFFER_LOAD) begin
        buffer_select_load = 2'b10;
        buffer_write  = 1;
    end

    if(stateC == BUFFER_STREAM) begin
        buffer_select_stream = 2'b10;
        buffer_read   = 1;
       streaming_valid_reg = 1;

        if(stream_counter == 0)
            streaming_start = 1;

        if(stream_counter == 4'(PE_COLS))
            stream_end_reg = 1;
    end

end

always_comb begin 
 bias_ready = (readyA || readyB ) &&  stateA != BUFFER_LOAD && stateB != BUFFER_LOAD ;
 bias_ready_full_matrix = readyC &&  stateA != BUFFER_LOAD && stateB != BUFFER_LOAD ;
end

endmodule
