///////////////////////////////////////////////////////////////
//
// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.
//
////////////////////////////////////////////////////////////////

module AsyncFIFO
#(
    parameter LOG_DEPTH      = 10,
    parameter WIDTH          = 32,
    parameter ALMOSTFULL_VAL = (2**LOG_DEPTH)/2,
    parameter USE_LUTRAM     = 0,
    parameter DBG_ENABLE     = 0
)
(
    input                 aclr,

    input                 wrclk,
    input                 wrreq,
    output                wrempty,
    output                wrfull,
    output [LOG_DEPTH:0]  wrusedw,
    input  [WIDTH-1:0]    data,

    input                 rdclk,
    output                rdempty,
    output                rdfull,
    output [LOG_DEPTH:0]  rdusedw,
    input                 rdreq,
    output [WIDTH-1:0]    q,
    
    output                dbg_overflow,
    output                dbg_underflow
);

    dcfifo dcfifo_component
    (
        .rdclk            (rdclk),
        .wrreq            (wrreq),
        .aclr             (aclr),
        .data             (data),
        .rdreq            (rdreq),
        .wrclk            (wrclk),
        .wrempty          (wrempty),
        .wrfull           (wrfull),
        .q                (q),
        .rdempty          (rdempty),
        .rdfull           (rdfull),
        .wrusedw          (wrusedw),
        .rdusedw          (rdusedw)
    );

    defparam
        dcfifo_component.add_usedw_msb_bit = "ON",
        dcfifo_component.intended_device_family = "Stratix V",
		dcfifo_component.lpm_hint = USE_LUTRAM ? "RAM_BLOCK_TYPE=MLAB" : "RAM_BLOCK_TYPE=M20K",
        dcfifo_component.lpm_numwords = 2**LOG_DEPTH,
        dcfifo_component.lpm_showahead = "ON",
        dcfifo_component.lpm_type = "dcfifo",
        dcfifo_component.lpm_width = WIDTH,
        dcfifo_component.lpm_widthu = LOG_DEPTH+1,
        dcfifo_component.overflow_checking = "OFF",
        dcfifo_component.rdsync_delaypipe = 5,
        dcfifo_component.read_aclr_synch = "ON",
        dcfifo_component.underflow_checking = "OFF",
        dcfifo_component.use_eab = "ON",
        dcfifo_component.write_aclr_synch = "ON",
        dcfifo_component.wrsync_delaypipe = 5;

endmodule
