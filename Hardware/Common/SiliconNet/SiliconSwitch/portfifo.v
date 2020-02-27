///////////////////////////////////////////////////////////////
//
// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.
//
////////////////////////////////////////////////////////////////

module PORTFIFO
#(
    parameter NUM_PORTS    = 16,
    parameter DATA_WIDTH = 64,
    parameter FIFO_DEPTH = 64
)
(
    input                                   clk,
    input                                   rst,

    input wire [$clog2(NUM_PORTS)-1:0]      wrport_in,
    input wire                              wrreq_in,
    input wire [DATA_WIDTH-1:0]             data_in,

    input wire [$clog2(NUM_PORTS)-1:0]      rdport_in,
    input wire                              rdreq_in,
    output wire [DATA_WIDTH-1:0]            q_out
);

    localparam PTR_WIDTH  = $clog2(FIFO_DEPTH);
    localparam ADDR_WIDTH = $clog2(NUM_PORTS * FIFO_DEPTH);

    wire [PTR_WIDTH-1:0] rdptr_net,
                         rdptr_nxt;

    wire [PTR_WIDTH-1:0] wrptr_net,
                         wrptr_nxt;

    lutram_dual
    #(
        .WIDTH              (PTR_WIDTH),
        .DEPTH              (NUM_PORTS)
    )
    WritePtrRam
    (
        .CLK                (clk),
        .CLR                (rst),
        .wen                (wrreq_in),
        .waddr              (wrport_in),
        .din                (wrptr_nxt),

        .raddr_0            (wrport_in),
        .dout_0             (wrptr_net),
        .raddr_1            (/*unused*/),
        .dout_1             (/*unused*/)
    );
 
    lutram_dual
    #(
        .WIDTH              (PTR_WIDTH),
        .DEPTH              (NUM_PORTS)
    )
    ReadPtrRam
    (
        .CLK                (clk),
        .CLR                (rst),
        .wen                (rdreq_in),
        .waddr              (rdport_in),
        .din                (rdptr_nxt),

        .raddr_0            (rdport_in),
        .dout_0             (rdptr_net),
        .raddr_1            (/*unused*/),
        .dout_1             (/*unused*/)
    ); 

    mram
    #(
        .DATA_WIDTH         (DATA_WIDTH), 
        .ADDR_WIDTH         (ADDR_WIDTH)
    )
    data_ram
    (
        .clk                (clk),

        .we_a               (wrreq_in),
        .addr_a             ({wrport_in,wrptr_net}),
        .data_a             (data_in),
        .q_a                (/*unused*/),

        .we_b               (1'b0),
        .data_b             ({DATA_WIDTH{1'bx}}),
        .addr_b             ({rdport_in,rdreq_in ? rdptr_nxt : rdptr_net}), /*** IF READING, PREFETCH NEXT ELEMENT ***/
        .q_b                (q_out)
    );

    assign wrptr_nxt = wrptr_net + 1'b1;
    assign rdptr_nxt = rdptr_net + 1'b1;
     
endmodule
