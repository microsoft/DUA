///////////////////////////////////////////////////////////////
//
// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.
//
////////////////////////////////////////////////////////////////

module Counter
#(
    parameter WIDTH     = 32
)
(
    input               clk,
    input               rst,
    input               inc_in,
    input               dec_in,
    output [WIDTH-1:0]  value
);

    reg [WIDTH-1:0] count_ff;

    always @ (posedge clk) begin
        if (rst) begin
            count_ff <= {WIDTH{1'b0}};
        end
        else begin
            if (inc_in & ~dec_in) begin 
                count_ff <= count_ff + 1'b1;
            end
            else if (~inc_in & dec_in) begin
                count_ff <= count_ff - 1'b1;
            end
        end
    end

    assign value = count_ff;

endmodule