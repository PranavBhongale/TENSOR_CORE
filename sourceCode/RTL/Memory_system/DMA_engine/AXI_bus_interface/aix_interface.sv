
`timescale 1ns/1ps

//==============================================================================
// AXI4-Lite Slave Module
//==============================================================================
module axi4lite_slave #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32,
    parameter NUM_REGS = 16
)(
    input wire ACLK,
    input wire ARESETN,

    // Write Address Channel
    input  wire [ADDR_WIDTH-1:0] S_AXI_AWADDR,
    input  wire [2:0]            S_AXI_AWPROT,
    input  wire                  S_AXI_AWVALID,
    output reg                   S_AXI_AWREADY,

    // Write Data Channel
    input  wire [DATA_WIDTH-1:0] S_AXI_WDATA,
    input  wire [DATA_WIDTH/8-1:0] S_AXI_WSTRB,
    input  wire                  S_AXI_WVALID,
    output reg                   S_AXI_WREADY,

    // Write Response Channel
    output reg  [1:0]            S_AXI_BRESP,
    output reg                   S_AXI_BVALID,
    input  wire                  S_AXI_BREADY,

    // Read Address Channel
    input  wire [ADDR_WIDTH-1:0] S_AXI_ARADDR,
    input  wire [2:0]            S_AXI_ARPROT,
    input  wire                  S_AXI_ARVALID,
    output reg                   S_AXI_ARREADY,

    // Read Data Channel
    output reg  [DATA_WIDTH-1:0] S_AXI_RDATA,
    output reg  [1:0]            S_AXI_RRESP,
    output reg                   S_AXI_RVALID,
    input  wire                  S_AXI_RREADY
);

    // Response types
    localparam RESP_OKAY   = 2'b00;
    localparam RESP_SLVERR = 2'b10;

    // Internal register file
    reg [DATA_WIDTH-1:0] registers [0:NUM_REGS-1];

    // Internal address/data latches and flags
    reg [ADDR_WIDTH-1:0] aw_addr_latch;
    reg aw_valid_latched;    // true when AW handshake accepted and awaiting W
    reg w_valid_latched;     // true when W handshake accepted and awaiting AW
    reg [DATA_WIDTH-1:0]  wdata_latch;
    reg [DATA_WIDTH/8-1:0] wstrb_latch;

    // Read address latch
    reg [ADDR_WIDTH-1:0] ar_addr_latch;
    reg ar_valid_latched;    // true when AR handshake accepted and R not yet returned

    integer i;

    // reset init
    always @(posedge ACLK) begin
        if (!ARESETN) begin
            for (i = 0; i < NUM_REGS; i = i + 1) begin
                registers[i] <= {DATA_WIDTH{1'b0}};
            end
            S_AXI_AWREADY <= 1'b0;
            S_AXI_WREADY  <= 1'b0;
            S_AXI_BVALID  <= 1'b0;
            S_AXI_BRESP   <= RESP_OKAY;
            aw_addr_latch <= {ADDR_WIDTH{1'b0}};
            aw_valid_latched <= 1'b0;
            wdata_latch <= {DATA_WIDTH{1'b0}};
            wstrb_latch <= {(DATA_WIDTH/8){1'b0}};
            w_valid_latched <= 1'b0;
            S_AXI_ARREADY <= 1'b0;
            ar_addr_latch <= {ADDR_WIDTH{1'b0}};
            ar_valid_latched <= 1'b0;
            S_AXI_RVALID <= 1'b0;
            S_AXI_RDATA  <= {DATA_WIDTH{1'b0}};
            S_AXI_RRESP  <= RESP_OKAY;
        end else begin
            // -----------------------
            // WRITE ADDRESS HANDSHAKE
            // Accept AW when AWVALID asserted and previous AW not latched
            // -----------------------
            if (!aw_valid_latched) begin
                if (S_AXI_AWVALID) begin
                    S_AXI_AWREADY <= 1'b1;
                    if (S_AXI_AWREADY && S_AXI_AWVALID) begin
                        aw_addr_latch <= S_AXI_AWADDR;
                        aw_valid_latched <= 1'b1;
                        S_AXI_AWREADY <= 1'b0; // deassert after accept
                    end
                end else begin
                    S_AXI_AWREADY <= 1'b0;
                end
            end else begin
                // if already latched, keep AWREADY low
                S_AXI_AWREADY <= 1'b0;
            end

            // -----------------------
            // WRITE DATA HANDSHAKE
            // Accept W when WVALID asserted and previous W not latched
            // -----------------------
            if (!w_valid_latched) begin
                if (S_AXI_WVALID) begin
                    S_AXI_WREADY <= 1'b1;
                    if (S_AXI_WREADY && S_AXI_WVALID) begin
                        wdata_latch <= S_AXI_WDATA;
                        wstrb_latch <= S_AXI_WSTRB;
                        w_valid_latched <= 1'b1;
                        S_AXI_WREADY <= 1'b0; // deassert after accept
                    end
                end else begin
                    S_AXI_WREADY <= 1'b0;
                end
            end else begin
                S_AXI_WREADY <= 1'b0;
            end

            // -----------------------
            // PERFORM WRITE when both AW and W latched
            // then assert BVALID until master accepts with BREADY
            // -----------------------
            if (aw_valid_latched && w_valid_latched && !S_AXI_BVALID) begin
                // address -> index (word addressing, address[1:0] ignored)
                if ((aw_addr_latch >> 2) < NUM_REGS) begin
                    // apply byte strobes
                    if (wstrb_latch[0]) registers[aw_addr_latch >> 2][7:0]   <= wdata_latch[7:0];
                    if (wstrb_latch[1]) registers[aw_addr_latch >> 2][15:8]  <= wdata_latch[15:8];
                    if (wstrb_latch[2]) registers[aw_addr_latch >> 2][23:16] <= wdata_latch[23:16];
                    if (wstrb_latch[3]) registers[aw_addr_latch >> 2][31:24] <= wdata_latch[31:24];
                    S_AXI_BRESP <= RESP_OKAY;
                end else begin
                    // invalid address
                    S_AXI_BRESP <= RESP_SLVERR;
                end
                // mark response valid and clear latched flags (response waits for BREADY)
                S_AXI_BVALID <= 1'b1;
                aw_valid_latched <= 1'b0;
                w_valid_latched <= 1'b0;
            end else if (S_AXI_BVALID && S_AXI_BREADY) begin
                // master accepted B, deassert
                S_AXI_BVALID <= 1'b0;
            end

            // -----------------------
            // READ ADDRESS HANDSHAKE
            // -----------------------
            if (!ar_valid_latched) begin
                if (S_AXI_ARVALID) begin
                    S_AXI_ARREADY <= 1'b1;
                    if (S_AXI_ARREADY && S_AXI_ARVALID) begin
                        ar_addr_latch <= S_AXI_ARADDR;
                        ar_valid_latched <= 1'b1;
                        S_AXI_ARREADY <= 1'b0;
                    end
                end else begin
                    S_AXI_ARREADY <= 1'b0;
                end
            end else begin
                S_AXI_ARREADY <= 1'b0;
            end

            // -----------------------
            // READ DATA CHANNEL
            // when AR latched and R not yet valid -> present data
            // -----------------------
            if (ar_valid_latched && !S_AXI_RVALID) begin
                if ((ar_addr_latch >> 2) < NUM_REGS) begin
                    S_AXI_RDATA <= registers[ar_addr_latch >> 2];
                    S_AXI_RRESP <= RESP_OKAY;
                end else begin
                    S_AXI_RDATA <= {DATA_WIDTH{1'b0}} ^ 32'hDEADBEEF; // sentinel
                    S_AXI_RRESP <= RESP_SLVERR;
                end
                S_AXI_RVALID <= 1'b1;
                ar_valid_latched <= 1'b0; // R now being presented
            end else if (S_AXI_RVALID && S_AXI_RREADY) begin
                S_AXI_RVALID <= 1'b0;
            end
        end
    end

endmodule


//==============================================================================
// AXI4-Lite Master Module
// - Simple single-beat master for driving the slave in testbench
//==============================================================================
module axi4lite_master #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32
)(
    input wire ACLK,
    input wire ARESETN,

    // User interface
    input  wire                  start_write,
    input  wire                  start_read,
    input  wire [ADDR_WIDTH-1:0] addr,
    input  wire [DATA_WIDTH-1:0] write_data,
    input  wire [3:0]            write_strb,
    output reg  [DATA_WIDTH-1:0] read_data,
    output reg                   write_done,
    output reg                   read_done,
    output reg  [1:0]            write_resp,
    output reg  [1:0]            read_resp,

    // Write Address Channel
    output reg  [ADDR_WIDTH-1:0] M_AXI_AWADDR,
    output reg  [2:0]            M_AXI_AWPROT,
    output reg                   M_AXI_AWVALID,
    input  wire                  M_AXI_AWREADY,

    // Write Data Channel
    output reg  [DATA_WIDTH-1:0] M_AXI_WDATA,
    output reg  [DATA_WIDTH/8-1:0] M_AXI_WSTRB,
    output reg                   M_AXI_WVALID,
    input  wire                  M_AXI_WREADY,

    // Write Response Channel
    input  wire [1:0]            M_AXI_BRESP,
    input  wire                  M_AXI_BVALID,
    output reg                   M_AXI_BREADY,

    // Read Address Channel
    output reg  [ADDR_WIDTH-1:0] M_AXI_ARADDR,
    output reg  [2:0]            M_AXI_ARPROT,
    output reg                   M_AXI_ARVALID,
    input  wire                  M_AXI_ARREADY,

    // Read Data Channel
    input  wire [DATA_WIDTH-1:0] M_AXI_RDATA,
    input  wire [1:0]            M_AXI_RRESP,
    input  wire                  M_AXI_RVALID,
    output reg                   M_AXI_RREADY
);

    // Write FSM states
    localparam W_IDLE = 3'd0;
    localparam W_ADDR = 3'd1;
    localparam W_DATA = 3'd2;
    localparam W_RESP = 3'd3;

    // Read FSM states
    localparam R_IDLE = 2'd0;
    localparam R_ADDR = 2'd1;
    localparam R_DATA = 2'd2;

    reg [2:0] write_state;
    reg [1:0] read_state;

    // internal flags to indicate whether AW/W handshake completed
    reg aw_accepted;
    reg w_accepted;

    always @(posedge ACLK) begin
        if (!ARESETN) begin
            write_state <= W_IDLE;
            M_AXI_AWADDR <= {ADDR_WIDTH{1'b0}};
            M_AXI_AWPROT <= 3'b000;
            M_AXI_AWVALID <= 1'b0;
            M_AXI_WDATA <= {DATA_WIDTH{1'b0}};
            M_AXI_WSTRB <= {(DATA_WIDTH/8){1'b0}};
            M_AXI_WVALID <= 1'b0;
            M_AXI_BREADY <= 1'b0;
            write_done <= 1'b0;
            write_resp <= {2{1'b0}};
            aw_accepted <= 1'b0;
            w_accepted <= 1'b0;
        end else begin
            // default single-cycle pulses zeroed
            write_done <= 1'b0;

            case (write_state)
                W_IDLE: begin
                    M_AXI_AWVALID <= 1'b0;
                    M_AXI_WVALID  <= 1'b0;
                    M_AXI_BREADY  <= 1'b0;
                    aw_accepted <= 1'b0;
                    w_accepted <= 1'b0;
                    if (start_write) begin
                        M_AXI_AWADDR <= addr;
                        M_AXI_AWPROT <= 3'b000;
                        M_AXI_AWVALID <= 1'b1;

                        M_AXI_WDATA <= write_data;
                        M_AXI_WSTRB <= write_strb;
                        M_AXI_WVALID <= 1'b1;

                        write_state <= W_ADDR;
                    end
                end

                W_ADDR: begin
                    // AW handshake
                    if (M_AXI_AWVALID && M_AXI_AWREADY) begin
                        M_AXI_AWVALID <= 1'b0;
                        aw_accepted <= 1'b1;
                    end

                    // W handshake
                    if (M_AXI_WVALID && M_AXI_WREADY) begin
                        M_AXI_WVALID <= 1'b0;
                        w_accepted <= 1'b1;
                    end

                    // if both accepted or both deasserted - move to response
                    if (aw_accepted && w_accepted) begin
                        M_AXI_BREADY <= 1'b1;
                        write_state <= W_RESP;
                    end
                end

                W_RESP: begin
                    if (M_AXI_BVALID) begin
                        write_resp <= M_AXI_BRESP;
                        M_AXI_BREADY <= 1'b0;
                        write_done <= 1'b1; // single-cycle pulse
                        write_state <= W_IDLE;
                        aw_accepted <= 1'b0;
                        w_accepted <= 1'b0;
                    end
                end

                default: write_state <= W_IDLE;
            endcase
        end
    end

    //==================================================================
    // READ FSM
    //==================================================================
    always @(posedge ACLK) begin
        if (!ARESETN) begin
            read_state <= R_IDLE;
            M_AXI_ARADDR <= {ADDR_WIDTH{1'b0}};
            M_AXI_ARPROT <= 3'b000;
            M_AXI_ARVALID <= 1'b0;
            M_AXI_RREADY <= 1'b0;
            read_data <= {DATA_WIDTH{1'b0}};
            read_done <= 1'b0;
            read_resp <= {2{1'b0}};
        end else begin
            // default single-cycle pulse
            read_done <= 1'b0;

            case (read_state)
                R_IDLE: begin
                    M_AXI_ARVALID <= 1'b0;
                    M_AXI_RREADY <= 1'b0;
                    if (start_read) begin
                        M_AXI_ARADDR <= addr;
                        M_AXI_ARPROT <= 3'b000;
                        M_AXI_ARVALID <= 1'b1;
                        read_state <= R_ADDR;
                    end
                end

                R_ADDR: begin
                    if (M_AXI_ARVALID && M_AXI_ARREADY) begin
                        M_AXI_ARVALID <= 1'b0;
                        M_AXI_RREADY <= 1'b1; // accept read data
                        read_state <= R_DATA;
                    end
                end

                R_DATA: begin
                    if (M_AXI_RVALID && M_AXI_RREADY) begin
                        read_data <= M_AXI_RDATA;
                        read_resp <= M_AXI_RRESP;
                        M_AXI_RREADY <= 1'b0;
                        read_done <= 1'b1; // single-cycle pulse
                        read_state <= R_IDLE;
                    end
                end

                default: read_state <= R_IDLE;
            endcase
        end
    end

endmodule


//==============================================================================
// Top-Level Integration Module
//==============================================================================
module axi4lite_system #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32
)(
    input wire ACLK,
    input wire ARESETN,

    // Master user interface
    input  wire                  start_write,
    input  wire                  start_read,
    input  wire [ADDR_WIDTH-1:0] addr,
    input  wire [DATA_WIDTH-1:0] write_data,
    input  wire [3:0]            write_strb,
    output wire [DATA_WIDTH-1:0] read_data,
    output wire                  write_done,
    output wire                  read_done,
    output wire [1:0]            write_resp,
    output wire [1:0]            read_resp
);

    // AXI4-Lite interface wires
    wire [ADDR_WIDTH-1:0] axi_awaddr;
    wire [2:0]            axi_awprot;
    wire                  axi_awvalid;
    wire                  axi_awready;

    wire [DATA_WIDTH-1:0] axi_wdata;
    wire [DATA_WIDTH/8-1:0] axi_wstrb;
    wire                  axi_wvalid;
    wire                  axi_wready;

    wire [1:0]            axi_bresp;
    wire                  axi_bvalid;
    wire                  axi_bready;

    wire [ADDR_WIDTH-1:0] axi_araddr;
    wire [2:0]            axi_arprot;
    wire                  axi_arvalid;
    wire                  axi_arready;

    wire [DATA_WIDTH-1:0] axi_rdata;
    wire [1:0]            axi_rresp;
    wire                  axi_rvalid;
    wire                  axi_rready;

    // Master instantiation
    axi4lite_master #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH)
    ) master (
        .ACLK(ACLK),
        .ARESETN(ARESETN),
        .start_write(start_write),
        .start_read(start_read),
        .addr(addr),
        .write_data(write_data),
        .write_strb(write_strb),
        .read_data(read_data),
        .write_done(write_done),
        .read_done(read_done),
        .write_resp(write_resp),
        .read_resp(read_resp),
        .M_AXI_AWADDR(axi_awaddr),
        .M_AXI_AWPROT(axi_awprot),
        .M_AXI_AWVALID(axi_awvalid),
        .M_AXI_AWREADY(axi_awready),
        .M_AXI_WDATA(axi_wdata),
        .M_AXI_WSTRB(axi_wstrb),
        .M_AXI_WVALID(axi_wvalid),
        .M_AXI_WREADY(axi_wready),
        .M_AXI_BRESP(axi_bresp),
        .M_AXI_BVALID(axi_bvalid),
        .M_AXI_BREADY(axi_bready),
        .M_AXI_ARADDR(axi_araddr),
        .M_AXI_ARPROT(axi_arprot),
        .M_AXI_ARVALID(axi_arvalid),
        .M_AXI_ARREADY(axi_arready),
        .M_AXI_RDATA(axi_rdata),
        .M_AXI_RRESP(axi_rresp),
        .M_AXI_RVALID(axi_rvalid),
        .M_AXI_RREADY(axi_rready)
    );

    // Slave instantiation
    axi4lite_slave #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .NUM_REGS(16)
    ) slave (
        .ACLK(ACLK),
        .ARESETN(ARESETN),
        .S_AXI_AWADDR(axi_awaddr),
        .S_AXI_AWPROT(axi_awprot),
        .S_AXI_AWVALID(axi_awvalid),
        .S_AXI_AWREADY(axi_awready),
        .S_AXI_WDATA(axi_wdata),
        .S_AXI_WSTRB(axi_wstrb),
        .S_AXI_WVALID(axi_wvalid),
        .S_AXI_WREADY(axi_wready),
        .S_AXI_BRESP(axi_bresp),
        .S_AXI_BVALID(axi_bvalid),
        .S_AXI_BREADY(axi_bready),
        .S_AXI_ARADDR(axi_araddr),
        .S_AXI_ARPROT(axi_arprot),
        .S_AXI_ARVALID(axi_arvalid),
        .S_AXI_ARREADY(axi_arready),
        .S_AXI_RDATA(axi_rdata),
        .S_AXI_RRESP(axi_rresp),
        .S_AXI_RVALID(axi_rvalid),
        .S_AXI_RREADY(axi_rready)
    );

endmodule

