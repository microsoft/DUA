///////////////////////////////////////////////////////////////
//
// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.
//
////////////////////////////////////////////////////////////////

module lutram_dual
#(
    parameter WIDTH      = 256,
    parameter DEPTH      = 2,
    parameter LOG_DEPTH  = $clog2(DEPTH)
)
(
    input                   CLK,
    input                   CLR,

    input                   wen,
    input [LOG_DEPTH-1:0]   waddr,
    input [LOG_DEPTH-1:0]   raddr_0,
    input [LOG_DEPTH-1:0]   raddr_1,
    input [WIDTH-1:0]       din,

    output [WIDTH-1:0]      dout_0,
    output [WIDTH-1:0]      dout_1
);

    integer i;

    (* ramstyle = "MLAB, no_rw_check" *) reg [WIDTH-1:0] ram_0 [DEPTH-1:0];
    (* ramstyle = "MLAB, no_rw_check" *) reg [WIDTH-1:0] ram_1 [DEPTH-1:0];    

    always@(posedge CLK) begin
        // Require a long reset
        if(CLR) begin
            for(i=0; i < DEPTH; i=i+1) begin
                ram_0[i] = {WIDTH{1'b0}};
                ram_1[i] = {WIDTH{1'b0}};
            end
        end
        else if(wen) begin
            ram_0[waddr] <= din;
            ram_1[waddr] <= din;
        end
    end

    assign dout_0 = ram_0[raddr_0];
    assign dout_1 = ram_1[raddr_1];

endmodule
