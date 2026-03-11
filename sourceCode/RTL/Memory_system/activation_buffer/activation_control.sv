`timescale 1ns/1ps

module activation_control #(
    parameter int PE_COLS    = 8
)(
    input  logic clk,
    input  logic reset_n,
    input  logic activation_valid,
    //  this is for output to MAC

    output logic streaming_valid,
    output logic streaming_start,
    output logic streaming_end,
    output logic activation_ready,
    output logic buffer_select_load,
    output logic buffer_select_stream,
    output logic buffer_read,
    output logic buffer_write
);



// BUFFER FSM


typedef enum logic [1:0] {
    BUFFER_READY,
    BUFFER_LOAD,
    BUFFER_STREAM
} buffer_state_t;

buffer_state_t stateA, next_stateA;
buffer_state_t stateB, next_stateB;

// COUNTERS

logic [$clog2(PE_COLS)+3:0] loadcounterA;
logic [$clog2(PE_COLS)+3:0] loadcounterB;
logic [$clog2(PE_COLS):0] stream_counter;

logic readyA;
logic readyB;


always_ff @(posedge clk) begin
    if(!reset_n)
        loadcounterA <= 0;
    else if(activation_valid)
        loadcounterA <= loadcounterA + 1;
    else
        loadcounterA <= 0;
end

always_ff @(posedge clk ) begin
    if(!reset_n)
        loadcounterB <= 0;
    else if(activation_valid)
        loadcounterB <= loadcounterB + 1;
    else
        loadcounterB <= 0;
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
    if(!reset_n) stateA <= BUFFER_READY;
    else stateA <= next_stateA;

always_ff @(posedge clk )
    if(!reset_n) stateB <= BUFFER_READY;
    else stateB <= next_stateB;


// BUFFER A FSM
logic lock ;
always_comb begin

    next_stateA = stateA;
     lock = 1'b1;
     readyA = 1'b1;
  unique  case(stateA)

        BUFFER_READY: begin
            if((activation_valid) && !lock2) begin
                next_stateA = BUFFER_LOAD;
            end
            lock = 1'b1;
             readyA = 1'b1;
        end

        BUFFER_LOAD:begin
            if(loadcounterA == 7'd64 && stateB != BUFFER_STREAM)begin
                next_stateA = BUFFER_STREAM;
                 readyA = 1'b0;
            end
           readyA = 1'b0;
        end

        BUFFER_STREAM:  begin
            if(stream_counter == 4'(PE_COLS))begin
                next_stateA = BUFFER_READY;
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
            if((activation_valid) && !lock)begin
                next_stateB = BUFFER_LOAD;
                readyB = 1'b0;
            end
        readyB = 1'b1;
        end
        BUFFER_LOAD:begin
            if( loadcounterB == 7'd64 &&  stateA != BUFFER_STREAM) begin
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

    streaming_start = 0;
    streaming_end   = 0;
    streaming_valid = 0;
    buffer_select_load  = 0;
    buffer_read     = 0;
    buffer_write    = 0;
    buffer_select_stream = 0;

    if(stateA == BUFFER_LOAD) begin
        buffer_select_load = 0;
        buffer_write  = 1;
    end

    if(stateA == BUFFER_STREAM) begin
        buffer_select_stream = 0;
        buffer_read   = 1;
        streaming_valid = 1;
        if(stream_counter == 1)
            streaming_start = 1;

        if(stream_counter == 4'(PE_COLS))
            streaming_end = 1;
    end


    // BUFFER B CONTROL

    if(stateB == BUFFER_LOAD) begin
        buffer_select_load = 1;
        buffer_write  = 1;
    end

    if(stateB == BUFFER_STREAM) begin
        buffer_select_stream = 1;
        buffer_read   = 1;
        streaming_valid = 1;

        if(stream_counter == 1)
            streaming_start = 1;

        if(stream_counter == 4'(PE_COLS))
            streaming_end = 1;
    end

end

always_comb begin
 activation_ready = (readyA || readyB ) &&  stateA != BUFFER_LOAD && stateB != BUFFER_LOAD ;
end
endmodule


