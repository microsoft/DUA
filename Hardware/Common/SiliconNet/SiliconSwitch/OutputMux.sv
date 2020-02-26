///////////////////////////////////////////////////////////////
//
// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.
//
/////////////////////////////////////////////////////////////////

module OutputMux
#(
    parameter N = 16,
    parameter WIDTH = 329
)
(
    input                        CLK,
    input                        RST_N,

    input [WIDTH-1:0]            data_in   [N-1:0],
    input [N-1:0]                valid_in,

    output reg [WIDTH-1:0]       data_out,
    output reg                   valid_out
);      
    
    reg   [WIDTH - 1 : 0]         data_in_reg    [N-1:0];
    reg   [N - 1 : 0]             valid_in_reg;

    always@(posedge CLK) begin
        if (RST_N) begin
            data_in_reg <= data_in;
            valid_in_reg <= valid_in;
        end
        else begin
            valid_in_reg <= 0;
        end
    end

    //for port=1~4, 1 level (note the ER don't take port<4 as legal input)
    //for port=5~16, 2 levels
    //for port>16, pipeline style
    generate
        if ((N > 0) && (N < 5)) begin //1~4, one layer tree
            treemux_prim
            #(
                .WIDTH(WIDTH),
                .N(N)
            )
            tree_mux_4
            (
                .CLK                (CLK),
                .RST_N              (RST_N),
                .data_in            (data_in_reg),
				.valid_in           (valid_in_reg),
                .data_out           (data_out),
                .valid_out          (valid_out)
            );
        end
        else if ((N > 4) && (N < 17)) begin //5~16, two layer tree
            treemux16
            #(
                .WIDTH(WIDTH),
                .N(N)
            )
            tree_mux_16
            (
                .CLK                (CLK),
                .RST_N              (RST_N),
				.data_in            (data_in_reg),
				.valid_in           (valid_in_reg),
                .data_out           (data_out),
                .valid_out          (valid_out)
            );
        end
        else begin  //pipeline style
            pipemux_prim2
            #(
                .WIDTH(WIDTH),
                .N(N)
            )
            pipe_mux_n
            (
                .CLK                (CLK),
                .RST_N              (RST_N),
                .data_in            (data_in),
                .valid_in           (valid_in),
                .data_out           (data_out),
                .valid_out          (valid_out)
            );
        end
    endgenerate
    
endmodule

// Description: 
// Tree-Mux
// generates N port multiplexer using 4-Mux as unit
// one layer for input ports 1-4
// two layers for input ports 4-16
// pipelined for input ports >16