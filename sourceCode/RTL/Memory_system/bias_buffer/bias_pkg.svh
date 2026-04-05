


package bias_pkg;

typedef enum logic [1:0] {
    BUFFER_NUN    = 2'b11,
    BUFFER_SCALLER = 2'b00,   // single bias value
    BUFFER_VECTOR = 2'b01,   // vector bias (one column)
    BUFFER_FULL   = 2'b10    // full matrix bias

} buffer_type_t;

endpackage

