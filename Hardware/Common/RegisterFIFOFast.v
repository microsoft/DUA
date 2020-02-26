///////////////////////////////////////////////////////////////
//
// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.
//
////////////////////////////////////////////////////////////////

module RegisterFIFOFast
#(
    parameter WIDTH = 32
)
(
    input                       clock,
    input                       reset_n,

    input                       wrreq,
    input [WIDTH-1:0]           data,
    output                      full,

    input                       rdreq,
    output                      empty,
    output reg [WIDTH-1:0]      q
);

    reg                         full_ff = 1'b0;

    always@(posedge clock) begin
        if(~reset_n) begin
            full_ff  <= 1'b0;
            q        <= {WIDTH{1'bx}};
        end
        else begin
            if (wrreq) begin
                q <= data;
            end
            if (wrreq & ~rdreq) begin
                full_ff <= 1'b1;
            end
            else if (wrreq & rdreq) begin
                full_ff <= 1'b1;
            end
            else if (~wrreq & rdreq) begin
                full_ff <= 1'b0;
            end
        end
    end

    assign full  = full_ff & ~rdreq;
    assign empty = ~full_ff;
    
endmodule
