///////////////////////////////////////////////////////////////
//
// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.
//
////////////////////////////////////////////////////////////////

module treemux16
#(
    parameter                       WIDTH   = 72,
    parameter                       N       = 16
)
(
    input                           CLK,
    input                           RST_N,
    input   [WIDTH - 1 : 0]         data_in     [N-1:0],
    input   [N - 1 : 0]             valid_in,
    output  [WIDTH - 1 : 0]         data_out,
    output                          valid_out
);

    //N must be (>4)||(<=16), (N / 4) = quot * 4 + resi  
    localparam quot = N[4 : 2];
    localparam resi = N[1 : 0];

    localparam inner_width = (resi != 2'b00)? quot + 1 : quot;
    wire    [WIDTH - 1 : 0]               data_inner    [inner_width-1:0];
    wire    [inner_width - 1 : 0]         valid_inner;

    genvar i;

    //level 1
    generate 
        for (i = 0; i < quot; i++) begin : gen_lvl_1
            treemux_prim
            #(
                .WIDTH(WIDTH),
                .N(4)
            )
            mux_inst
            (
                .CLK            (CLK),
                .RST_N          (RST_N),
                .data_in        (data_in[i*4 +: 4]),
                .valid_in       (valid_in[i*4 +: 4]),
                .data_out       (data_inner[i]),
                .valid_out      (valid_inner[i])
            );
        end
    endgenerate

    generate 
        if (resi != 2'b00) begin : gen_lvl_1_resi
            treemux_prim
            #(
                .WIDTH(WIDTH),
                .N(resi)
            )
            mux_inst
            (
                .CLK            (CLK),
                .RST_N          (RST_N),
                .data_in        (data_in[quot*4 +: resi]),
                .valid_in       (valid_in[quot*4 +: resi]),
                .data_out       (data_inner[quot]),
                .valid_out      (valid_inner[quot])
            );
        end
    endgenerate

    //level 0
    treemux_prim
    #(
        .WIDTH(WIDTH),
        .N(inner_width)
    )
    gen_lvl_0
    (
        .CLK            (CLK),
        .RST_N          (RST_N),
        .data_in        (data_inner),
        .valid_in       (valid_inner),
        .data_out       (data_out),
        .valid_out      (valid_out)
    );
    
endmodule 
