///////////////////////////////////////////////////////////////
//
// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.
//
////////////////////////////////////////////////////////////////

module sync_regs
#(  
    parameter DEPTH = 2,
    parameter WIDTH = 32
)
(  
    input               clk,
    input   [WIDTH-1:0] din,
    output  [WIDTH-1:0] dout
);

genvar gen_i;
  
reg [WIDTH-1:0]  data_internal [DEPTH-1:0];

always @(posedge clk) begin
    data_internal[0] <= din;
end

generate 
    for (gen_i = 1; gen_i < DEPTH; gen_i = gen_i + 1) begin: gen_internal
        always @ (posedge clk) begin
            data_internal[gen_i] <= data_internal[gen_i-1];
        end
    end
endgenerate

assign dout = data_internal[DEPTH-1];

endmodule
