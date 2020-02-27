///////////////////////////////////////////////////////////////
//
// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.
//
////////////////////////////////////////////////////////////////

import SiliconNetTypes::*;

module ForwardingTable_arbitrary
#(
    parameter NUM_KEYS                   =32'd8,
    parameter NUM_PORTS                  =SN_NUM_PORTS,
    parameter WIDTH                      =64
)
(
    input                               clk,
    input                               rst,

    // key check input
    input                               key_valid_in,
    input  [WIDTH-1:0]                  key_check_in,

    // for control configuration in
    input                               cfg_in,
    input  [$clog2(NUM_KEYS):0]         cfg_index_in,  // index [NUM_KEYS] is reserved for special usage, eg. compare serverIP    
    input                               cfg_valid_in,
    input  [WIDTH-1:0]                  cfg_key_in,
    input  [WIDTH-1:0]                  cfg_msk_in,
    input  [$clog2(NUM_PORTS)-1:0]      cfg_endpoint_in,
    // for control configuration out
    input                               cfg_read_in,
    output reg                          cfg_read_valid_out,
    output reg                          cfg_valid_out,
    output reg [WIDTH-1:0]              cfg_key_out,
    output reg [WIDTH-1:0]              cfg_msk_out,
    output reg [$clog2(NUM_PORTS)-1:0]  cfg_endpoint_out,
    // key ep out
    output reg                          endpoint_valid_out,
    output reg [$clog2(NUM_PORTS)-1:0]  endpoint_out,
    output reg                          endpoint_missed_out,
    output reg                          endpoint_special_matched
);

    typedef struct packed {
        reg                          valid;
        reg  [WIDTH-1:0]             key;
        reg  [$clog2(NUM_PORTS)-1:0] endpoint;
    } KEY_ROUTE;
    
    KEY_ROUTE           key_store          [NUM_KEYS:0];  // key_store[NUM_KEYS] is used for set and load the default endpoint
    reg  [WIDTH-1:0]    msk_store          [NUM_KEYS:0];
    

    integer i;
    genvar  j;

    //////////////////////////////////////////////////////////////////////////////
    // Key Update 
    //////////////////////////////////////////////////////////////////////////////

    reg [NUM_KEYS:0]            cfg_tmp;
    reg [$clog2(NUM_KEYS):0]    cfg_index_tmp;
    reg                         cfg_valid_tmp;
    reg [$clog2(NUM_PORTS)-1:0] cfg_endpoint_tmp;
    reg [WIDTH-1:0]             cfg_key_tmp;
    reg [WIDTH-1:0]             cfg_msk_tmp;

    // sync input
    always @ (posedge clk or posedge rst) begin
        if (rst) begin
            cfg_tmp                 <= {(NUM_KEYS+1){1'b0}};
            cfg_index_tmp           <= {($clog2(NUM_KEYS)+1){1'b0}};
            cfg_valid_tmp           <= 1'b0;
            cfg_endpoint_tmp        <= {$clog2(NUM_PORTS){1'b0}};
            cfg_key_tmp             <= {WIDTH{1'b0}};
            cfg_msk_tmp             <= {WIDTH{1'b0}};
        end
        else begin
            if (cfg_in) begin
                cfg_tmp[cfg_index_in]   <= cfg_in;
                cfg_index_tmp           <= cfg_index_in;
                cfg_valid_tmp           <= cfg_valid_in;
                cfg_endpoint_tmp        <= cfg_endpoint_in;
                cfg_key_tmp             <= cfg_key_in & cfg_msk_in;
                cfg_msk_tmp             <= cfg_msk_in;
            end
            else begin
                cfg_tmp                 <= {(NUM_KEYS+1){1'b0}};
                cfg_index_tmp           <= {($clog2(NUM_KEYS)+1){1'b0}};
                cfg_valid_tmp           <= 1'b0;
                cfg_endpoint_tmp        <= {$clog2(NUM_PORTS){1'b0}};
                cfg_key_tmp             <= {WIDTH{1'b0}};
                cfg_msk_tmp             <= {WIDTH{1'b0}};
            end
        end
    end

    // update the keys and masks
    generate 
        for (j=0; j<NUM_KEYS+1; j++) begin : gen_store
            always @ (posedge clk or posedge rst) begin
                if (rst) begin
                    key_store[j].valid                  <= 1'b0;
                    key_store[j].key                    <= {WIDTH{1'b0}};
                    key_store[j].endpoint               <= {$clog2(NUM_PORTS){1'b0}};
                    msk_store[j]                        <= {WIDTH{1'b0}};
                end
                else begin
                    if (cfg_tmp[j]) begin
                        key_store[j].valid      <= cfg_valid_tmp;
                        key_store[j].key        <= cfg_key_tmp;
                        key_store[j].endpoint   <= cfg_endpoint_tmp;
                        msk_store[j]            <= cfg_msk_tmp;
                    end
                end
            end
        end
    endgenerate

    //////////////////////////////////////////////////////////////////////////////
    // Key read out 
    //////////////////////////////////////////////////////////////////////////////

    always @ (posedge clk or posedge rst) begin
        if (rst) begin
            cfg_read_valid_out      <= 1'b0;
            cfg_valid_out           <= 1'b0;
            cfg_key_out             <= {WIDTH{1'b0}};
            cfg_msk_out             <= {WIDTH{1'b0}};
            cfg_endpoint_out        <= {$clog2(NUM_PORTS){1'b0}};            
        end
        else begin
            if (cfg_read_in) begin
                cfg_read_valid_out      <= 1'b1;
                cfg_valid_out           <= key_store[cfg_index_in].valid;
                cfg_key_out             <= key_store[cfg_index_in].key;
                cfg_msk_out             <= msk_store[cfg_index_in];
                cfg_endpoint_out        <= key_store[cfg_index_in].endpoint;
            end
            else begin
                cfg_read_valid_out      <= 1'b0;
                cfg_valid_out           <= 1'b0;
                cfg_key_out             <= {WIDTH{1'b0}};
                cfg_msk_out             <= {WIDTH{1'b0}};
                cfg_endpoint_out        <= {$clog2(NUM_PORTS){1'b0}};
            end
        end
    end

    //////////////////////////////////////////////////////////////////////////////
    // usr check in & Compare
    //////////////////////////////////////////////////////////////////////////////

    reg                         key_valid_tmp;
    reg [WIDTH-1:0]             key_check_tmp       [NUM_KEYS:0];

    // sync input, spread input into each stored key
    generate
        for (j=0; j<NUM_KEYS+1; j++) begin : gen_key_check
            always @ (posedge clk or posedge rst) begin
                if (rst) begin
                    key_check_tmp[j]       <= {WIDTH{1'b0}};
                end
                else begin
                    if (key_valid_in) begin
                        key_check_tmp[j]   <= key_store[j].key ^~ (key_check_in & msk_store[j]); // part 1 of the formular
                    end
                    else begin
                        key_check_tmp[j]   <= {WIDTH{1'b0}};
                    end
                end
            end
        end
    endgenerate
    always @ (posedge clk or posedge rst) begin
        if (rst) begin
            key_valid_tmp       <= 1'b0;
        end
        else begin
            if (key_valid_in) begin
                key_valid_tmp   <= 1'b1;
            end
            else begin
                key_valid_tmp   <= 1'b0;
            end
        end
    end
    
    reg [NUM_KEYS:0]              endpoint_tmp;
    reg                           key_valid_tmp2;

    // generate endpoint selection for each stored key
    generate
        for (j=0; j<NUM_KEYS+1; j++) begin : gen_endpoint_matching
            always @ (posedge clk or posedge rst) begin
                if (rst) begin
                    endpoint_tmp[j]       <= 1'b0;
                end
                else begin
                    if (key_store[j].valid) begin
                        endpoint_tmp[j]       <= key_valid_tmp & (&key_check_tmp[j]);  //part 2 of the formular
                    end
                    else begin
                        endpoint_tmp[j]       <= 1'b0;
                    end
                end
            end
        end
    endgenerate
    always @ (posedge clk or posedge rst) begin
        if (rst) begin
            key_valid_tmp2       <= 1'b0;
        end
        else begin
            if (key_valid_tmp) begin
                key_valid_tmp2   <= 1'b1;
            end
            else begin
                key_valid_tmp2   <= 1'b0;
            end
        end
    end

    // generate endpoint output
    // only compare to common keys
    always @ (posedge clk or posedge rst) begin
        if (rst) begin
            endpoint_out            <= {$clog2(NUM_PORTS){1'b0}};
            endpoint_valid_out      <= 1'b0;
            endpoint_missed_out     <= 1'b0;
        end
        else begin
            if (key_valid_tmp2) begin
                if (endpoint_tmp[NUM_KEYS-1:0]!={NUM_KEYS{1'b0}}) begin
                    for (i=0; i<NUM_KEYS; i++) begin
                        if (endpoint_tmp[i]) begin
                            endpoint_out <= key_store[i].endpoint;
                        end
                    end
                    endpoint_valid_out  <= 1'b1;
                    endpoint_missed_out <= 1'b0;
                end
                else begin
                    endpoint_out        <= {$clog2(NUM_PORTS){1'bx}};
                    endpoint_valid_out  <= 1'b1;
                    endpoint_missed_out <= 1'b1;
                end
            end
            else begin
                endpoint_out        <= {$clog2(NUM_PORTS){1'b0}};
                endpoint_valid_out  <= 1'b0;
                endpoint_missed_out <= 1'b0;
            end
        end
    end
    // for the special key, use this
    always @ (posedge clk or posedge rst) begin
        if (rst) begin
            endpoint_special_matched     <= 1'b0;
        end
        else begin
            if (key_valid_tmp2) begin
                if (endpoint_tmp[NUM_KEYS]) begin                    
                    endpoint_special_matched     <= 1'b1;                    
                end
                else begin
                    endpoint_special_matched     <= 1'b0;
                end
            end
            else begin
                endpoint_special_matched     <= 1'b0;
            end
        end
    end

endmodule
