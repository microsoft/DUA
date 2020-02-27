///////////////////////////////////////////////////////////////
//
// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.
//
////////////////////////////////////////////////////////////////

module FIFOCounter
#(
    parameter DATA_WIDTH    =16,
    parameter DEPTH         =16
)
(
    input                            clk,
    input                            rst,
    input                            rd_req,
    input                            wr_req,
    input        [DATA_WIDTH-1:0]    data_in,
    output  reg  [DATA_WIDTH-1:0]    data_out,
    output  wire [DATA_WIDTH-1:0]    data_prefetch,
    output                           empty,
    output                           half_full,
    output                           full,
    output  reg  [$clog2(DEPTH):0]   counter
);
    
    reg     [$clog2(DEPTH)-1:0]     i;
    reg     [$clog2(DEPTH)-1:0]     rd_ptr;
    reg     [$clog2(DEPTH)-1:0]     wr_ptr;                        //pointer and counter

    (* ramstyle = "MLAB, no_rw_check" *)  reg [DATA_WIDTH-1:0] ram [DEPTH-1:0];

    always @ (posedge clk) begin
        if (rst) begin                                    //initialize
            rd_ptr                      <= {$clog2(DEPTH){1'b0}};
            wr_ptr                      <= {$clog2(DEPTH){1'b0}};
            counter                     <= {$clog2(DEPTH){1'b0}};
            data_out                    <= {DATA_WIDTH{1'b0}};
        end
        else begin
            case({rd_req,wr_req})
                2'b00: begin                                //no write or read request
                    counter             <= counter;
                    data_out            <= {DATA_WIDTH{1'b0}};
                end
                2'b01: begin                                //write request, data into fifo
                    ram[wr_ptr]         <= data_in;
                    counter             <= counter+1'b1;
                    wr_ptr              <= (wr_ptr==DEPTH-1) ? 0 : wr_ptr+1'b1;
                    data_out            <= {DATA_WIDTH{1'b0}};
                end
                2'b10: begin                                //read request, fifo out data
                    data_out            <= ram[rd_ptr];
                    counter             <= counter-1'b1;
                    rd_ptr              <= (rd_ptr==DEPTH-1) ? 0 : rd_ptr+1'b1;
                end
                2'b11: begin                                //write and read request, data pass through
                    if(counter==0)
                        data_out        <= data_in;
                    else begin
                        ram[wr_ptr]     <= data_in;
                        data_out        <= ram[rd_ptr];
                        wr_ptr          <= (wr_ptr==DEPTH-1) ? 0 : wr_ptr+1'b1;
                        rd_ptr          <= (rd_ptr==DEPTH-1) ? 0 : rd_ptr+1'b1;
                    end
                end
                default: begin
                    rd_ptr                      <= {$clog2(DEPTH){1'b0}};
                    wr_ptr                      <= {$clog2(DEPTH){1'b0}};
                    counter                     <= {$clog2(DEPTH){1'b0}};
                    data_out                    <= {DATA_WIDTH{1'b0}};
                end
            endcase
        end
    end

    //flag, combinational output
    assign empty     = (counter==0);
    assign half_full = counter[$clog2(DEPTH)-1]|counter[$clog2(DEPTH)];
    assign full      = (counter==DEPTH);

    assign data_prefetch = empty ? {DATA_WIDTH{1'b0}} : ram[rd_ptr];

endmodule