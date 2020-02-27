///////////////////////////////////////////////////////////////
//
// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.
//
////////////////////////////////////////////////////////////////

module pipemux_prim2
#(
    parameter WIDTH = 72,
    parameter N = 4 // 4 is sweet spot in # ALMs / input (~18.25)
)
(
    input                   CLK,
    input                   RST_N,

    //input [N*WIDTH-1:0]     data_in,
    input [WIDTH-1:0]       data_in   [N-1:0],
    input [N-1:0]           valid_in,

    output reg [WIDTH-1:0]  data_out,
    output reg              valid_out
); 
 
    //pipeline style, pot16 phit256, Fmax 156.94MHz
    integer i;
    always@(posedge CLK) begin
        valid_out <= RST_N ? (|valid_in) : 1'b0;
        for(i=0; i < N; i=i+1) 
            if(valid_in[i]) data_out <= data_in[i];
    end
	
endmodule
