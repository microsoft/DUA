///////////////////////////////////////////////////////////////
//
// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.
//
////////////////////////////////////////////////////////////////

import SiliconNetTypes::*;
import NetworkTypes::IP4Address;

module ForwardingTableDual
#(
    parameter NUM_KEYS_HIGH              =32'd16,
    parameter NUM_KEYS_LOW               =32'd16,
    parameter WIDTH_HIGH                 =$bits(IP4Address),
    parameter WIDTH_LOW                  =SN_DEVID_WIDTH,
    parameter NUM_PORTS                  =SN_NUM_PORTS
)
(
    input                                clk,
    input                                rst,
    // Destination UID input
    input                                dst_UID_valid_in,
    input  UID                           dst_UID_check_in,
    // Address high field configure
    input                                high_cfg_in,
    input  [$clog2(NUM_KEYS_HIGH):0]     high_cfg_index_in,  // index [NUM_KEYS] is used for set and load the default endpoint
    input                                high_cfg_valid_in,    
    input  [WIDTH_HIGH-1:0]              high_cfg_key_in,
    input  [WIDTH_HIGH-1:0]              high_cfg_msk_in,
    input  [$clog2(NUM_PORTS)-1:0]       high_cfg_endpoint_in,
    //
    input                                high_cfg_read_in,
    output reg                           high_cfg_read_valid_out,
    output reg                           high_cfg_valid_out,
    output reg [WIDTH_HIGH-1:0]          high_cfg_key_out,
    output reg [WIDTH_HIGH-1:0]          high_cfg_msk_out,
    output reg [$clog2(NUM_PORTS)-1:0]   high_cfg_endpoint_out,
    // Address low field onfigure
    input                                low_cfg_in,
    input  [$clog2(NUM_KEYS_LOW):0]      low_cfg_index_in,   // index [NUM_KEYS] is used for set and load the default endpoint
    input                                low_cfg_valid_in,    
    input  [WIDTH_LOW-1:0]               low_cfg_key_in,
    input  [WIDTH_LOW-1:0]               low_cfg_msk_in,
    input  [$clog2(NUM_PORTS)-1:0]       low_cfg_endpoint_in,
    //
    input                                low_cfg_read_in,
    output reg                           low_cfg_read_valid_out,
    output reg                           low_cfg_valid_out,
    output reg [WIDTH_LOW-1:0]           low_cfg_key_out,
    output reg [WIDTH_LOW-1:0]           low_cfg_msk_out,
    output reg [$clog2(NUM_PORTS)-1:0]   low_cfg_endpoint_out,
    // Endpoint output
    output reg                           endpoint_valid_out,
    output reg [$clog2(NUM_PORTS)-1:0]   endpoint_out,
    output reg                           endpoint_missed_out
);
    
    // Address high field endpoint output
    wire                            high_endpoint_valid_out;
    wire [$clog2(NUM_PORTS)-1:0]    high_endpoint_out;
    wire                            high_endpoint_missed_out;
    wire                            high_endpoint_special_matched;

    ForwardingTable_arbitrary
    #(
        .NUM_KEYS                   (NUM_KEYS_HIGH),
        .NUM_PORTS                  (NUM_PORTS),
        .WIDTH                      (WIDTH_HIGH)
    )
    ForwardingTable_high_ins
    (
        .clk                        (clk),
        .rst                        (rst),

        .key_valid_in               (dst_UID_valid_in),
        .key_check_in               (dst_UID_check_in.ipv4),

        .cfg_in                     (high_cfg_in),        
        .cfg_index_in               (high_cfg_index_in),
        .cfg_valid_in               (high_cfg_valid_in),
        .cfg_key_in                 (high_cfg_key_in),
        .cfg_msk_in                 (high_cfg_msk_in),
        .cfg_endpoint_in            (high_cfg_endpoint_in),

        .cfg_read_in                (high_cfg_read_in),
        .cfg_read_valid_out         (high_cfg_read_valid_out),
        .cfg_valid_out              (high_cfg_valid_out),
        .cfg_key_out                (high_cfg_key_out),
        .cfg_msk_out                (high_cfg_msk_out),
        .cfg_endpoint_out           (high_cfg_endpoint_out),

        .endpoint_valid_out         (high_endpoint_valid_out),
        .endpoint_out               (high_endpoint_out),
        .endpoint_missed_out        (high_endpoint_missed_out),
        .endpoint_special_matched   (high_endpoint_special_matched)
    );

    // Address low field endpoint output
    wire                            low_endpoint_valid_out;
    wire [$clog2(NUM_PORTS)-1:0]    low_endpoint_out;
    wire                            low_endpoint_missed_out;
    wire                            low_endpoint_special_matched;

    ForwardingTable_arbitrary
    #(
        .NUM_KEYS                   (NUM_KEYS_LOW),
        .NUM_PORTS                  (NUM_PORTS),
        .WIDTH                      (WIDTH_LOW)
    )
    ForwardingTable_low_ins
    (
        .clk                        (clk),
        .rst                        (rst),

        .key_valid_in               (dst_UID_valid_in),
        .key_check_in               (dst_UID_check_in.devID),

        .cfg_in                     (low_cfg_in),
        .cfg_index_in               (low_cfg_index_in),
        .cfg_valid_in               (low_cfg_valid_in),
        .cfg_key_in                 (low_cfg_key_in),
        .cfg_msk_in                 (low_cfg_msk_in),
        .cfg_endpoint_in            (low_cfg_endpoint_in),

        .cfg_read_in                (low_cfg_read_in),
        .cfg_read_valid_out         (low_cfg_read_valid_out),
        .cfg_valid_out              (low_cfg_valid_out),
        .cfg_key_out                (low_cfg_key_out),
        .cfg_msk_out                (low_cfg_msk_out),
        .cfg_endpoint_out           (low_cfg_endpoint_out),

        .endpoint_valid_out         (low_endpoint_valid_out),
        .endpoint_out               (low_endpoint_out),
        .endpoint_missed_out        (low_endpoint_missed_out),
        .endpoint_special_matched   (low_endpoint_special_matched)
    );

    
    // option 1: High field has higher priority
    always @ (posedge clk or posedge rst) begin
        if (rst) begin
            endpoint_valid_out      <= 1'b0;
            endpoint_out            <= {$clog2(NUM_PORTS){1'b0}};
            endpoint_missed_out     <= 1'b0;
        end
        else begin
            if (!high_endpoint_missed_out) begin      // High field matched
                endpoint_valid_out  <= high_endpoint_valid_out;
                endpoint_out        <= high_endpoint_out;
                endpoint_missed_out <= high_endpoint_missed_out;
            end
            else begin                                // High field missed
                endpoint_valid_out  <= low_endpoint_valid_out;
                endpoint_out        <= low_endpoint_out;
                endpoint_missed_out <= low_endpoint_missed_out;
            end
        end
    end
    

    // // option 2: if serverIP matched, use devID table result, otherwise use IP table result    
    // always @ (posedge clk or posedge rst) begin
    //     if (rst) begin
    //         endpoint_valid_out      <= 1'b0;
    //         endpoint_out            <= {$clog2(NUM_PORTS){1'b0}};
    //         endpoint_missed_out     <= 1'b0;
    //     end
    //     else begin
    //         if (!high_endpoint_special_matched) begin      // serverIP no match, use IP table result
    //             endpoint_valid_out  <= high_endpoint_valid_out;
    //             endpoint_out        <= high_endpoint_out;
    //             endpoint_missed_out <= high_endpoint_missed_out;
    //         end
    //         else begin                                     // serverIP matched, use devID table result
    //             endpoint_valid_out  <= low_endpoint_valid_out;
    //             endpoint_out        <= low_endpoint_out;
    //             endpoint_missed_out <= low_endpoint_missed_out;
    //         end
    //     end
    // end

endmodule