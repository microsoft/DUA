///////////////////////////////////////////////////////////////
//
// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.
//
////////////////////////////////////////////////////////////////

module shift_reg_clr
#(  
    parameter DELAY = 2,
    parameter WIDTH = 32
)
(  
    input               CLK,
    input               CLR,
    input   [WIDTH-1:0] in,
    output  [WIDTH-1:0] out
);

genvar gen_i;
  
reg [WIDTH-1:0]  data_internal [DELAY-1:0];

always @(posedge CLK) begin
    data_internal[0] <= in;
end

generate 
    for (gen_i = 1; gen_i < DELAY; gen_i = gen_i + 1) begin: gen_internal    
        always @ (posedge CLK) begin
            if (CLR) begin
                data_internal[gen_i] <= {WIDTH{1'b0}};
            end
            else begin
                data_internal[gen_i] <= data_internal[gen_i-1];
            end
        end
    end
endgenerate

assign out = data_internal[DELAY-1];

endmodule
