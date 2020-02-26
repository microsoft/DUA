///////////////////////////////////////////////////////////////
//
// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.
//
////////////////////////////////////////////////////////////////

module FIFOFast
#(
    parameter LOG_DEPTH      = 10,
    parameter WIDTH          = 32,
    parameter ALMOSTFULL_VAL = (2**LOG_DEPTH)/2,
    parameter USE_LUTRAM     = 0,
    parameter USE_OUTREG     = 1,
    parameter DBG_ENABLE     = 0
)
(
    input                       clock,
    input                       reset_n,

    input                       wrreq,
    input  [WIDTH-1:0]          data,
    output                      full,
    output                      almost_full,
    output [LOG_DEPTH:0]        usedw,

    input                       rdreq,
    output                      empty,
    output                      almost_empty,
    output [WIDTH-1:0]          q
);

    reg [LOG_DEPTH-1:0] read_ptr_ff,
                        write_ptr_ff;

    reg [LOG_DEPTH:0]   used;

    always @ (posedge clock) begin
        if(~reset_n) begin
            read_ptr_ff   <= {LOG_DEPTH{1'b0}};
        end
        else begin
            if (rdreq) begin
                read_ptr_ff <= read_ptr_ff + 1'b1;
            end
        end
    end

    always @ (posedge clock) begin
        if(~reset_n) begin
            write_ptr_ff  <= {LOG_DEPTH{1'b0}};
        end
        else begin
            if (wrreq) begin
                write_ptr_ff <= write_ptr_ff + 1'b1;
            end
        end
    end

    always @ (posedge clock) begin
        if(~reset_n) begin
            used          <= {(LOG_DEPTH+1){1'b0}};
        end
        else begin
            if (wrreq & ~rdreq) begin
                used <= used + 1'b1;
            end
            else if (~wrreq & rdreq) begin
                used <= used - 1'b1;
            end
        end
    end

    assign full         = (used == 2**LOG_DEPTH);
    assign almost_full  = (used >= ALMOSTFULL_VAL);
    assign empty        = (used == 0);
    assign almost_empty = (used <= 1);
    assign usedw        = used;

    lutram_dual#(.WIDTH(WIDTH),.DEPTH(2**LOG_DEPTH)) FifoDataInst
    (
        .CLK                (clock),
        .CLR                (~reset_n),
        .wen                (wrreq),
        .waddr              (write_ptr_ff),
        .raddr_0            (read_ptr_ff),
        .din                (data),
        .dout_0             (q),
        .raddr_1            (/*unused*/),
        .dout_1             (/*unused*/)
    );

endmodule
