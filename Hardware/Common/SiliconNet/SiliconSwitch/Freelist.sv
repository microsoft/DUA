///////////////////////////////////////////////////////////////
//
// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.
//
////////////////////////////////////////////////////////////////

module Freelist
#(
    parameter MAX_COUNT  = 1024,
    parameter DATA_WIDTH = 10
)
(
    input                         write_clk,
    input                         read_clk,
    input                         rst,

    // Deposit
    input wire                    wren_in,
    input wire [DATA_WIDTH-1:0]   data_in,

    // Debit
    output wire [DATA_WIDTH-1:0]  data_out,
    output wire                   valid_out,
    input  wire                   rden_in,

    output wire                   dbg_underflow,
    output wire                   dbg_overflow,

    output wire                   initd_out
);

    reg [3:0]                     wait_ff = 1'b0;
    reg [$clog2(MAX_COUNT):0]     count_ff = 1'b0;
    reg                           init_ff  = 1'b0;
    wire                          empty_net;
    wire                          wrfull_net;

    assign initd_out = init_ff;
    logic rst_write_clk, 
          rst_read_clk;

    sync_regs#(.WIDTH(1)) rstsync_wrclk(.clk(write_clk),.din(rst),.dout(rst_write_clk));
    sync_regs#(.WIDTH(1)) rstsync_rdclk(.clk(read_clk),.din(rst),.dout(rst_read_clk));

    always@(posedge write_clk) begin
        if(rst_write_clk) begin
            wait_ff  <= 1'b0;
            init_ff  <= 1'b0;
            count_ff <= 1'b0;
        end
        else begin

            if(~wait_ff[3]) wait_ff <= wait_ff + 1'b1;

            if(wait_ff[3] & ~init_ff & ~wrfull_net) begin
                count_ff <= count_ff + 1'b1;
                if(count_ff == (MAX_COUNT-1)) begin
                    init_ff <= 1'b1;
                end
            end
        end
    end

    logic [DATA_WIDTH-1:0] data_net;

    logic outputQ_full,
          outputQ_empty;

    logic transfer_net;

    assign transfer_net = ~empty_net & ~outputQ_full;
 
    //AsyncFIFO
    //#(
    //    .LOG_DEPTH                ($clog2(MAX_COUNT)),
    //    .WIDTH                    (DATA_WIDTH)
    //) 
    //FreelistFIFO
    //(
    //    .aclr                     (rst_write_clk),
    //    .wrclk                    (write_clk),  
    //    .wrreq                    (~rst_write_clk & ~wrfull_net & ((wait_ff[3] & ~init_ff) | wren_in)),
    //    .wrempty                  (/*unused*/),
    //    .wrfull                   (wrfull_net),
    //    .wrusedw                  (/*unused*/),
    //    .data                     (~init_ff ? count_ff[$clog2(MAX_COUNT)-1:0] : data_in),

    //    .rdclk                    (read_clk),  
    //    .rdempty                  (empty_net),
    //    .rdfull                   (/*unused*/),
    //    .rdusedw                  (/*unused*/),
    //    .rdreq                    (transfer_net),
    //    .q                        (data_net),

    //    .dbg_overflow             (dbg_overflow),
    //    .dbg_underflow            (dbg_underflow)
    //);

    FIFO
    #(
        .LOG_DEPTH                  ($clog2(MAX_COUNT)),
        .WIDTH                      (DATA_WIDTH),
        .USE_LUTRAM                 (1)
    ) 
    FreelistFIFO
    (
        .clock                      (write_clk),
        .reset_n                    (~rst_write_clk),

        .wrreq                      (~rst_write_clk & ~wrfull_net & ((wait_ff[3] & ~init_ff) | wren_in)),
        .data                       (~init_ff ? count_ff[$clog2(MAX_COUNT)-1:0] : data_in),
        .full                       (wrfull_net),
        .almost_full                (),
        .usedw                      (),

        .rdreq                      (transfer_net),
        .empty                      (empty_net),
        .almost_empty               (),
        .q                          (data_net)
    );

    // Help with timing closure

    RegisterFIFOFast#(.WIDTH(DATA_WIDTH)) OutputFIFO
    (
        .clock                    (read_clk),
        .reset_n                  (~rst_read_clk),

        .wrreq                    (transfer_net),
        .data                     (data_net),
        .full                     (outputQ_full),

        .rdreq                    (rden_in),
        .empty                    (outputQ_empty),
        .q                        (data_out)
    );

    //synopsys translate off
    always@(negedge write_clk) begin
        if(~init_ff & wren_in) begin
            $display("Error, accessing freelist before it is ready");
            $finish(0);
        end
    end
    //synopsys translate on

    assign valid_out = ~outputQ_empty & init_ff;

endmodule
