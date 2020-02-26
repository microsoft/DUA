///////////////////////////////////////////////////////////////
//
// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.
//
////////////////////////////////////////////////////////////////

module FIFO
#(
    parameter LOG_DEPTH      = 10,
    parameter WIDTH          = 32,
    parameter ALMOSTFULL_VAL = (2**LOG_DEPTH)/2,
    parameter ALMOSTEMPTY_VAL= 1,
    parameter USE_LUTRAM     = 0,
    parameter USE_OUTREG     = 1,
    parameter DBG_ENABLE     = 0
)
(
    input                       clock,
    input                       reset_n,

    input                       wrreq,
    input [WIDTH-1:0]           data,
    output                      full,
    output                      almost_full,
    output [LOG_DEPTH:0]        usedw,

    input                       rdreq,
    output                      empty,
    output                      almost_empty,
    output [WIDTH-1:0]          q
);

    scfifo FIFO_Inst
    (
        .clock          (clock),
        .sclr           (~reset_n),
        .aclr           (1'b0),

        .wrreq          (wrreq),
        .data           (data),
        .full           (full),
        .almost_full    (almost_full),
        .usedw          (usedw[LOG_DEPTH-1:0]),

        .rdreq          (rdreq),
        .empty          (empty),
        .almost_empty   (almost_empty),
        .q              (q)
    );

    assign usedw[LOG_DEPTH] = full;

	defparam
		FIFO_Inst.add_ram_output_register = (USE_OUTREG == 1) ? "ON" : "OFF",
		FIFO_Inst.almost_full_value = ALMOSTFULL_VAL,
        FIFO_Inst.almost_empty_value = ALMOSTEMPTY_VAL,
		FIFO_Inst.intended_device_family = "Stratix V",
		FIFO_Inst.lpm_hint = USE_LUTRAM ? "RAM_BLOCK_TYPE=MLAB" : "RAM_BLOCK_TYPE=M20K",
		FIFO_Inst.lpm_numwords = 2**LOG_DEPTH,
		FIFO_Inst.lpm_showahead = "ON",
		FIFO_Inst.lpm_type = "scfifo",
		FIFO_Inst.lpm_width = WIDTH,
		FIFO_Inst.lpm_widthu = LOG_DEPTH,
		FIFO_Inst.overflow_checking = "OFF",
		FIFO_Inst.underflow_checking = "OFF",
		FIFO_Inst.use_eab = "ON";

endmodule
