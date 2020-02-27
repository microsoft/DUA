///////////////////////////////////////////////////////////////
//
// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.
//
////////////////////////////////////////////////////////////////

module treemux_prim
#(
    parameter WIDTH = 72,
    parameter N = 4 // 4 is sweet spot in # ALMs / input (~18.25)
)
(
    input                   CLK,
    input                   RST_N,
    input [WIDTH-1:0]       data_in     [N-1:0],
    input [N-1:0]           valid_in,
    output reg [WIDTH-1:0]  data_out,
    output reg              valid_out

);

    integer i;

    //generate data_out logic
    generate
        case (N)
            4: begin
                always@(posedge CLK) begin
                    if (RST_N) begin
                        data_out  <= (valid_in[0]|valid_in[1]) ? (valid_in[0]? (data_in[0]) : (data_in[1])) : (valid_in[2] ? (data_in[2]) :(data_in[3]));
                    end
                end
            end
            3: begin
                always@(posedge CLK) begin
                    if (RST_N) begin
                        data_out  <= (valid_in[0]|valid_in[1]) ? (valid_in[0]? (data_in[0]) : (data_in[1])) : (data_in[2]);
                    end
                end
            end
            2: begin
                always@(posedge CLK) begin
                    if (RST_N) begin
                        data_out  <= valid_in[0]? (data_in[0]) : (data_in[1]);
                    end
                end
            end
            1: begin
                always@(posedge CLK) begin
                    if (RST_N) begin
                        data_out  <= data_in[0];
                    end
                end
            end
            default: begin
                always@(posedge CLK) begin
                    if (RST_N) begin
                        for(i=0; i < N; i=i+1) begin 
                            if (valid_in[i]) begin
                                data_out <= data_in[i];
                            end
                        end
                    end
                end
            end
        endcase
    endgenerate
    
    //generate valid_out logic


    always_ff @(posedge CLK) begin
        if (RST_N) begin
            valid_out <= (|valid_in);
        end
        else
            valid_out <= 1'b0;
    end
        
    
endmodule
