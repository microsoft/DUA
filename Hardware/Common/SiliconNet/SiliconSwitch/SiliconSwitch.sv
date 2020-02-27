///////////////////////////////////////////////////////////////
//
// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.
//
////////////////////////////////////////////////////////////////

import SiliconNetTypes::*;

module SiliconSwitch
#(
    parameter NUM_VCS,
              PHIT_WIDTH,
              FLIT_WIDTH,
              NUM_PORTS,
              // Per-Input Port Parameters
              NUM_FLITS,
              FLITS_PER_MESSAGE,
              // Per-Output Downstream Parameters
              MAX_FLITS_PER_PORT_DOWNSTREAM,
              MAX_CREDIT_WIDTH,
              // Optimization/debug/status
              DISABLE_UTURN,
              USE_LUTRAM
)
(
    input                                 clk,
    input                                 rst,

    // Injection ports
    input SwitchInterface                 input_ifc_in    [NUM_PORTS-1:0],
    input [NUM_PORTS-1:0]                 input_valid_in                 ,

    // Ejection ports
    output SwitchInterface                output_ifc_out  [NUM_PORTS-1:0],
    output [NUM_PORTS-1:0]                output_valid_out               ,
    input                                 output_stall_in [NUM_PORTS-1:0],

    // Credits (Injection ports)
    output SwitchCredit                   credit_out      [NUM_PORTS-1:0],
    input                                 credack_in      [NUM_PORTS-1:0],

    // Credits (Ejection ports)
    input  SwitchCredit                   credit_in       [NUM_PORTS-1:0],    
    output                                credack_out     [NUM_PORTS-1:0]
);

    localparam PORT_WIDTH                 = $clog2(NUM_PORTS);

    SwitchInterface                       mid_bus_net     [NUM_PORTS-1:0];
    wire [NUM_PORTS-1:0]                  mid_valid_net;
    SwitchRaise                           mid_raise       [NUM_PORTS-1:0];
    SwitchGrant                           mid_grants      [NUM_PORTS-1:0];
    wire [NUM_PORTS-1:0]                  mid_stall;
    wire [NUM_PORTS-1:0]                  mid_syncs;

    SwitchGrant                           mid_grant       [NUM_PORTS-1:0];

    genvar i;
    genvar b;
    generate

        for(i=0; i < NUM_PORTS; i=i+1) begin : gen_input_units

            integer o;
            always@(*) begin
                mid_grant[i]       = {$bits(SwitchGrant){1'b0}};
                for(o=0; o < NUM_PORTS; o=o+1) begin
                    if(mid_grants[o].valid & (mid_grants[o].src_port == i[PORT_WIDTH-1:0])) begin
                        mid_grant[i] = mid_grants[o];
                    end
                end
            end

            InputUnit
            #(
                .NUM_PORTS                (NUM_PORTS),
                .PORT_NUM                 (i),
                .NUM_FLITS                (NUM_FLITS),
                .FLITS_PER_MESSAGE         (FLITS_PER_MESSAGE),
                .PHIT_WIDTH               (PHIT_WIDTH),
                .FLIT_WIDTH               (FLIT_WIDTH),  
                .USE_LUTRAM               (USE_LUTRAM)
            )
            InputUnitInst
            (
                .clk                      (clk),
                .rst                      (rst),

                .input_ifc_in             (input_ifc_in[i]),
                .input_valid_in           (input_valid_in[i]),

                .credit_out               (credit_out[i]),
                .credack_in               (credack_in[i]),

                .output_ifc_out           (mid_bus_net[i]),
                .output_valid_out         (mid_valid_net[i]),
                .output_stall_in          (mid_stall),

                .raise_out                (mid_raise[i]),
                .grant_in                 (mid_grant[i]),
                .sync_out                 (mid_syncs[i])
            ); 
        end

        for(i=0; i < NUM_PORTS; i=i+1) begin : gen_output_units
            
            // Used to filter U-Turn Traffic
            SwitchInterface mid_bus_filtered_net [NUM_PORTS-1:0];
            wire [NUM_PORTS-1:0] mid_valid_filtered_net;
            for(b=0; b < NUM_PORTS; b = b+1) begin : gen_mid_bus
                if(b != i) begin
                    assign mid_bus_filtered_net[b]   = mid_bus_net[b];
                    assign mid_valid_filtered_net[b] = mid_valid_net[b];
                end
                else begin
                    assign mid_bus_filtered_net[b]   = (DISABLE_UTURN == 1) ? {$bits(SwitchInterface){1'bx}} : mid_bus_net[b];
                    assign mid_valid_filtered_net[b] = (DISABLE_UTURN == 1) ? 1'b0 : mid_valid_net[b];
                end
            end

            OutputUnit
            #(
                .NUM_PORTS                    (NUM_PORTS),
                .PORT_NUM                     (i),
                .MAX_FLITS_PER_PORT_DOWNSTREAM(MAX_FLITS_PER_PORT_DOWNSTREAM),
                .PHIT_WIDTH                   (PHIT_WIDTH),
                .FLIT_WIDTH                   (FLIT_WIDTH),
                .MAX_CREDIT_WIDTH             (MAX_CREDIT_WIDTH),
                .USE_LUTRAM                   (USE_LUTRAM)
            )
            OutputUnitInst
            (
                .clk                          (clk),
                .rst                          (rst),

                .input_ifc_in                 (mid_bus_filtered_net),
                .input_valid_in               (mid_valid_filtered_net),
                .input_stall_out              (mid_stall[i]),

                .raise_in                     (mid_raise),
                .grant_out                    (mid_grants[i]),
                .sync_in                      (mid_syncs[i]),

                .output_ifc_out               (output_ifc_out[i]),
                .output_valid_out             (output_valid_out[i]),
                .output_stall_in              (output_stall_in[i]),

                .credit_in                    (credit_in[i]),
                .credack_out                  (credack_out[i])
            );
        end
    endgenerate

endmodule