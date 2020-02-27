///////////////////////////////////////////////////////////////
//
// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.
//
////////////////////////////////////////////////////////////////

import SiliconNetTypes::*;
import NetworkTypes::IP4Address;

module SiliconNet
#(
    ////////// Connector
    // Interface parameter
    parameter DATA_WIDTH                        = SN_DATA_WIDTH,
    parameter UID_WIDTH                         = SN_UID_WIDTH,
    parameter LENGTH_WIDTH                      = SN_LENGTH_WIDTH,
    parameter FLAG_WIDTH                        = SN_FLAG_WIDTH,
    parameter SEQNUM_WIDTH                      = SN_SEQNUM_WIDTH,
    parameter TYPE_WIDTH                        = SN_TYPE_WIDTH,
    parameter PARAM_WIDTH                       = SN_PARAM_WIDTH,
    parameter NUM_PORTS                         = SN_NUM_PORTS,
    parameter MAX_MSG_LENGTH                    = SN_MAX_MSG_LENGTH,
    // ForwardingTable related
    parameter NUM_TABLES                        = 2,
    parameter NUM_KEYS_HIGH                     = 16,
    parameter NUM_KEYS_LOW                      = 64,
    parameter WIDTH_HIGH                        = $bits(IP4Address),
    parameter WIDTH_LOW                         = SN_DEVID_WIDTH,
    // ForwardingTable config parameters
    parameter CTL_REG_WRITE_KEY_ADDR            = SN_CTL_REG_WRITE_KEY_ADDR,
    parameter CTL_REG_WRITE_MSK_ADDR            = SN_CTL_REG_WRITE_MSK_ADDR,
    parameter CTL_REG_READ_KEY_ADDR             = SN_CTL_REG_READ_KEY_ADDR,
    parameter CTL_REG_READ_MSK_ADDR             = SN_CTL_REG_READ_MSK_ADDR,
    parameter CTL_REG_READ_EP_ADDR              = SN_CTL_REG_READ_EP_ADDR,
    parameter CTL_REG_ADDR                      = SN_CTL_REG_ADDR,
    // Connector counter
    parameter CTL_REG_COUNTER_VALUE_ADDR        = SN_CTL_REG_COUNTER_VALUE_ADDR,

    ////////// SiliconSwitch
    // Core parameter
    parameter NUM_VCS                           = SN_NUM_VCS,
    parameter PHIT_WIDTH                        = SN_PHIT_WIDTH,
    parameter FLIT_WIDTH                        = SN_FLIT_WIDTH,
    // Per-Input Port Parameters
    parameter NUM_FLITS                         = SN_NUM_FLITS,
    parameter FLITS_PER_MESSAGE                 = SN_FLITS_PER_MESSAGE,
    // Per-Output Downstream Parameters
    parameter MAX_FLITS_PER_PORT_DOWNSTREAM     = SN_FLITS_PER_PORT_DOWNSTREAM,
    parameter MAX_CREDIT_WIDTH                  = SN_MAX_CREDIT_WIDTH,
    // Optimization
    parameter DISABLE_UTURN                     = SN_DISABLE_UTURN,
    parameter USE_LUTRAM                        = SN_USE_LUTRAM
)
(    
    input                                 clk,
    input                                 rst,

    // Stack/App side
    input                                 sa_clk                    [NUM_PORTS-1:0],
    input                                 sa_rst                    [NUM_PORTS-1:0],

    // Stack/App Side - (RX: SiliconNet -> Stack/App)
    output reg [DATA_WIDTH-1:0]           sa_data_out               [NUM_PORTS-1:0],
    output reg                            sa_valid_out              [NUM_PORTS-1:0],
    output reg                            sa_first_out              [NUM_PORTS-1:0],
    output reg                            sa_last_out               [NUM_PORTS-1:0],
    input                                 sa_ready_in               [NUM_PORTS-1:0],

    // Stack/App Side - (TX: Stack/App -> SiliconNet)
    input      [DATA_WIDTH-1:0]           sa_data_in                [NUM_PORTS-1:0],
    input                                 sa_valid_in               [NUM_PORTS-1:0],
    input                                 sa_first_in               [NUM_PORTS-1:0],
    input                                 sa_last_in                [NUM_PORTS-1:0],
    output reg                            sa_ready_out              [NUM_PORTS-1:0],

    // ForwardingTable in Connector Configuration
    input                                 ctl_read_in,
    input                                 ctl_write_in,
    input      [15:0]                     ctl_addr_in,
    input      [63:0]                     ctl_wrdata_in,
    output reg [63:0]                     ctl_rddata_out,
    output reg                            ctl_rdvalid_out
);

    // Address high field configure
    reg                                   high_cfg_in               [NUM_PORTS-1:0];    
    reg     [$clog2(NUM_KEYS_HIGH):0]     high_cfg_index_in         [NUM_PORTS-1:0];
    reg                                   high_cfg_valid_in         [NUM_PORTS-1:0];
    reg     [WIDTH_HIGH-1:0]              high_cfg_key_in           [NUM_PORTS-1:0];
    reg     [WIDTH_HIGH-1:0]              high_cfg_msk_in           [NUM_PORTS-1:0];
    reg     [$clog2(NUM_PORTS)-1:0]       high_cfg_endpoint_in      [NUM_PORTS-1:0];
    //
    reg                                   high_cfg_read_in          [NUM_PORTS-1:0];
    wire                                  high_cfg_read_valid_out   [NUM_PORTS-1:0];
    wire                                  high_cfg_valid_out        [NUM_PORTS-1:0];
    wire    [WIDTH_HIGH-1:0]              high_cfg_key_out          [NUM_PORTS-1:0];
    wire    [WIDTH_HIGH-1:0]              high_cfg_msk_out          [NUM_PORTS-1:0];
    wire    [$clog2(NUM_PORTS)-1:0]       high_cfg_endpoint_out     [NUM_PORTS-1:0];

    // Address low field onfigure
    reg                                   low_cfg_in                [NUM_PORTS-1:0];    
    reg     [$clog2(NUM_KEYS_LOW):0]      low_cfg_index_in          [NUM_PORTS-1:0];
    reg                                   low_cfg_valid_in          [NUM_PORTS-1:0];
    reg     [WIDTH_LOW-1:0]               low_cfg_key_in            [NUM_PORTS-1:0];
    reg     [WIDTH_LOW-1:0]               low_cfg_msk_in            [NUM_PORTS-1:0];
    reg     [$clog2(NUM_PORTS)-1:0]       low_cfg_endpoint_in       [NUM_PORTS-1:0];
    //
    reg                                   low_cfg_read_in           [NUM_PORTS-1:0];
    wire                                  low_cfg_read_valid_out    [NUM_PORTS-1:0];
    wire                                  low_cfg_valid_out         [NUM_PORTS-1:0];
    wire    [WIDTH_LOW-1:0]               low_cfg_key_out           [NUM_PORTS-1:0];
    wire    [WIDTH_LOW-1:0]               low_cfg_msk_out           [NUM_PORTS-1:0];
    wire    [$clog2(NUM_PORTS)-1:0]       low_cfg_endpoint_out      [NUM_PORTS-1:0];

    // counter related
    reg                                   counter_read_in           [NUM_PORTS-1:0];
    reg     [2:0]                         counter_index_in          [NUM_PORTS-1:0];
    wire                                  counter_value_valid_out   [NUM_PORTS-1:0];
    wire    [63:0]                        counter_value_out         [NUM_PORTS-1:0];
 
    // Input ports
    SwitchInterface                      rtr_input_ifc    [NUM_PORTS-1:0];
    logic [NUM_PORTS-1:0]                rtr_input_valid;

    // Input-side Credits
    SwitchCredit                         rtr_credit_out   [NUM_PORTS-1:0];
    logic                                rtr_credack_in   [NUM_PORTS-1:0];
    
    // Output port
    logic                                rtr_output_rst   [NUM_PORTS-1:0];
    SwitchInterface                      rtr_output_ifc   [NUM_PORTS-1:0];
    logic [NUM_PORTS-1:0]                rtr_output_valid;
    logic                                rtr_output_stall [NUM_PORTS-1:0];

    // Credit returns
    SwitchCredit                         rtr_credit_in    [NUM_PORTS-1:0];
    logic                                rtr_credack_out  [NUM_PORTS-1:0];

    // ShimInterface
    SwitchInterface                      usr_in_ifc       [NUM_PORTS-1:0];
    logic [NUM_PORTS-1:0]                usr_in_wren;
    logic [NUM_PORTS-1:0]                usr_out_full     [NUM_PORTS-1:0];//20180308

    SwitchInterface                      usr_out_ifc      [NUM_PORTS-1:0];
    logic [NUM_PORTS-1:0]                usr_out_wren;
    logic [NUM_PORTS-1:0]                usr_in_full;


    // debug only
    SiliconNetHead                       dbg_head_send    [NUM_PORTS-1:0];
    SiliconData256                       dbg_data_send    [NUM_PORTS-1:0];
    SiliconNetHead                       dbg_head_receive [NUM_PORTS-1:0];
    SiliconData256                       dbg_data_receive [NUM_PORTS-1:0];

    genvar i;

    ////////////////////////////////////////////////////////////////////////
    //SiliconSwitch/////////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////    
    SiliconSwitch
    #(
        .NUM_VCS                        (NUM_VCS),
        .PHIT_WIDTH                     (PHIT_WIDTH),
        .FLIT_WIDTH                     (FLIT_WIDTH),
        .NUM_PORTS                      (NUM_PORTS),

        .NUM_FLITS                      (NUM_FLITS),
        .FLITS_PER_MESSAGE              (FLITS_PER_MESSAGE),

        .MAX_FLITS_PER_PORT_DOWNSTREAM  (MAX_FLITS_PER_PORT_DOWNSTREAM),
        .MAX_CREDIT_WIDTH               (MAX_CREDIT_WIDTH),

        .DISABLE_UTURN                  (DISABLE_UTURN),
        .USE_LUTRAM                     (USE_LUTRAM)
    )
    SiliconSwitch
    (
        .clk                            (clk),
        .rst                            (rst),

        .input_ifc_in                   (rtr_input_ifc),
        .input_valid_in                 (rtr_input_valid),
        .credit_out                     (rtr_credit_out),
        .credack_in                     (rtr_credack_in),

        .output_ifc_out                 (rtr_output_ifc),
        .output_valid_out               (rtr_output_valid),
        .output_stall_in                (rtr_output_stall),
        .credit_in                      (rtr_credit_in),
        .credack_out                    (rtr_credack_out)
    );    

    ////////////////////////////////////////////////////////////////////////
    //ShimInterface/////////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////   
    generate
        for(i=0; i < NUM_PORTS; i=i+1) begin : gen_ShimInterface
            ShimInterface
            #(
                .FLIT_WIDTH                     (FLIT_WIDTH),
                .PHIT_WIDTH                     (PHIT_WIDTH),
                .NUM_VCS                        (NUM_VCS),
                .NUM_PORTS                      (NUM_PORTS),
                .MAX_CREDIT_WIDTH               (MAX_CREDIT_WIDTH),
                .DISABLE_FULL_PIPE              (0)
            )
            ShimInterface
            (
                .clk                            (clk),
                .rst                            (rst),

                .usr_ifc_in                     (usr_in_ifc[i]),
                .usr_wren_in                    (usr_in_wren[i]),
                .usr_full_out                   (usr_out_full[i]),

                .usr_ifc_out                    (usr_out_ifc[i]),
                .usr_wren_out                   (usr_out_wren[i]),
                .usr_full_in                    (usr_in_full[i]),

                .rtr_ifc_out                    (rtr_input_ifc[i]),
                .rtr_valid_out                  (rtr_input_valid[i]),
                .rtr_credit_in                  (rtr_credit_out[i]),
                .rtr_credack_out                (rtr_credack_in[i]),

                .rtr_ifc_in                     (rtr_output_ifc[i]),
                .rtr_valid_in                   (rtr_output_valid[i]),
                .rtr_output_stall_out           (rtr_output_stall[i]),
                .rtr_credit_out                 (rtr_credit_in[i]),
                .rtr_credack_in                 (rtr_credack_out[i])
            ); 
        end
    endgenerate

    ////////////////////////////////////////////////////////////////////////
    //Connector/////////////////////////////////////////////////////////////
    //////////////////////////////////////////////////////////////////////// 
    generate
        for(i=0; i < NUM_PORTS; i=i+1) begin : gen_Connector
            Connector
            #(
                .DATA_WIDTH                      (DATA_WIDTH),
                .UID_WIDTH                       (UID_WIDTH),
                .LENGTH_WIDTH                    (LENGTH_WIDTH),
                .FLAG_WIDTH                      (FLAG_WIDTH),
                .SEQNUM_WIDTH                    (SEQNUM_WIDTH),
                .TYPE_WIDTH                      (TYPE_WIDTH),
                .PARAM_WIDTH                     (PARAM_WIDTH),
                .NUM_PORTS                       (NUM_PORTS),
                .MAX_MSG_LENGTH                  (MAX_MSG_LENGTH),
                .THIS_ID_PORT                    (i),
                .THIS_ID_VC                      (1),
                
                .NUM_TABLES                      (NUM_TABLES),
                .NUM_KEYS_HIGH                   (NUM_KEYS_HIGH),
                .NUM_KEYS_LOW                    (NUM_KEYS_LOW),
                .WIDTH_HIGH                      (WIDTH_HIGH),
                .WIDTH_LOW                       (WIDTH_LOW)
            )
            Connector
            (
                .clk                             (clk),
                .rst                             (rst),

                // Stack/App side
                .sa_clk                          (sa_clk[i]),
                .sa_rst                          (sa_rst[i]),

                // Full Switch Side - (RX: ShimInterface -> Connector) 
                .fs_ifc_in                       (usr_out_ifc[i]),
                .fs_wren_in                      (usr_out_wren[i]),
                .fs_full_out                     (usr_in_full[i]),

                // Full Switch Side - (TX: Connctor -> ShimInterface) 
                .fs_ifc_out                      (usr_in_ifc[i]),
                .fs_wren_out                     (usr_in_wren[i]),
                .fs_full_in                      (usr_out_full[i]),

                // Stack/App Side - (RX: Connector -> Stack/App)
                .sa_data_out                     (sa_data_out[i]),
                .sa_valid_out                    (sa_valid_out[i]),
                .sa_first_out                    (sa_first_out[i]),
                .sa_last_out                     (sa_last_out[i]),
                .sa_ready_in                     (sa_ready_in[i]),

                // Stack/App Side - (TX: Stack/App -> Connector)
                .sa_data_in                      (sa_data_in[i]),
                .sa_valid_in                     (sa_valid_in[i]),
                .sa_first_in                     (sa_first_in[i]),
                .sa_last_in                      (sa_last_in[i]),
                .sa_ready_out                    (sa_ready_out[i]),

                // Configure to FPGA CA

                // Address high field configure
                .high_cfg_in                     (high_cfg_in[i]),                
                .high_cfg_index_in               (high_cfg_index_in[i]),
                .high_cfg_valid_in               (high_cfg_valid_in[i]),
                .high_cfg_key_in                 (high_cfg_key_in[i]),
                .high_cfg_msk_in                 (high_cfg_msk_in[i]),
                .high_cfg_endpoint_in            (high_cfg_endpoint_in[i]),
                //
                .high_cfg_read_in                (high_cfg_read_in[i]),
                .high_cfg_read_valid_out         (high_cfg_read_valid_out[i]),
                .high_cfg_valid_out              (high_cfg_valid_out[i]),
                .high_cfg_key_out                (high_cfg_key_out[i]),
                .high_cfg_msk_out                (high_cfg_msk_out[i]),
                .high_cfg_endpoint_out           (high_cfg_endpoint_out[i]),

                // Address low field onfigure
                .low_cfg_in                      (low_cfg_in[i]),                
                .low_cfg_index_in                (low_cfg_index_in[i]),
                .low_cfg_valid_in                (low_cfg_valid_in[i]),
                .low_cfg_key_in                  (low_cfg_key_in[i]),
                .low_cfg_msk_in                  (low_cfg_msk_in[i]),
                .low_cfg_endpoint_in             (low_cfg_endpoint_in[i]),
                //
                .low_cfg_read_in                 (low_cfg_read_in[i]),
                .low_cfg_read_valid_out          (low_cfg_read_valid_out[i]),
                .low_cfg_valid_out               (low_cfg_valid_out[i]),
                .low_cfg_key_out                 (low_cfg_key_out[i]),
                .low_cfg_msk_out                 (low_cfg_msk_out[i]),
                .low_cfg_endpoint_out            (low_cfg_endpoint_out[i]),

                .counter_read_in                 (counter_read_in[i]),
                .counter_index_in                (counter_index_in[i]),
                .counter_value_valid_out         (counter_value_valid_out[i]),
                .counter_value_out               (counter_value_out[i])
            );
        end
    endgenerate

    ////////////////////////////////////////////////////////////////////////
    //Controller////////////////////////////////////////////////////////////
    //////////////////////////////////////////////////////////////////////// 
    SiliconNetController
    #(
        
        .NUM_PORTS                         (NUM_PORTS),
        
        .NUM_TABLES                        (NUM_TABLES),
        .NUM_KEYS_HIGH                     (NUM_KEYS_HIGH),
        .NUM_KEYS_LOW                      (NUM_KEYS_LOW),
        .WIDTH_HIGH                        (WIDTH_HIGH),
        .WIDTH_LOW                         (WIDTH_LOW),
        
        .CTL_REG_WRITE_KEY_ADDR            (CTL_REG_WRITE_KEY_ADDR),
        .CTL_REG_WRITE_MSK_ADDR            (CTL_REG_WRITE_MSK_ADDR),
        .CTL_REG_READ_KEY_ADDR             (CTL_REG_READ_KEY_ADDR),
        .CTL_REG_READ_MSK_ADDR             (CTL_REG_READ_MSK_ADDR),
        .CTL_REG_ADDR                      (CTL_REG_ADDR),

        .CTL_REG_COUNTER_VALUE_ADDR        (CTL_REG_COUNTER_VALUE_ADDR)
    )
    SiliconNetController
    (
        .clk                         (clk),
        .rst                         (rst),


        .ctl_read_in                 (ctl_read_in),
        .ctl_write_in                (ctl_write_in),
        .ctl_addr_in                 (ctl_addr_in),
        .ctl_wrdata_in               (ctl_wrdata_in),
        .ctl_rddata_out              (ctl_rddata_out),
        .ctl_rdvalid_out             (ctl_rdvalid_out),


        .high_cfg_out                (high_cfg_in),
        .high_cfg_index_out          (high_cfg_index_in),
        .high_cfg_valid_out          (high_cfg_valid_in),
        .high_cfg_key_out            (high_cfg_key_in),
        .high_cfg_msk_out            (high_cfg_msk_in),
        .high_cfg_endpoint_out       (high_cfg_endpoint_in),

        .high_cfg_read_out           (high_cfg_read_in),
        .high_cfg_read_valid_in      (high_cfg_read_valid_out),
        .high_cfg_valid_in           (high_cfg_valid_out),
        .high_cfg_key_in             (high_cfg_key_out),
        .high_cfg_msk_in             (high_cfg_msk_out),
        .high_cfg_endpoint_in        (high_cfg_endpoint_out),


        .low_cfg_out                 (low_cfg_in),
        .low_cfg_index_out           (low_cfg_index_in),
        .low_cfg_valid_out           (low_cfg_valid_in),
        .low_cfg_key_out             (low_cfg_key_in),
        .low_cfg_msk_out             (low_cfg_msk_in),
        .low_cfg_endpoint_out        (low_cfg_endpoint_in),

        .low_cfg_read_out            (low_cfg_read_in),
        .low_cfg_read_valid_in       (low_cfg_read_valid_out),
        .low_cfg_valid_in            (low_cfg_valid_out),
        .low_cfg_key_in              (low_cfg_key_out),
        .low_cfg_msk_in              (low_cfg_msk_out),
        .low_cfg_endpoint_in         (low_cfg_endpoint_out),

        .counter_read_out            (counter_read_in),
        .counter_index_out           (counter_index_in),
        .counter_value_valid_in      (counter_value_valid_out),
        .counter_value_in            (counter_value_out)
    );

    // debug only
    genvar gen_i;
    // check send msg header   
    generate
        for (gen_i = 0; gen_i < NUM_PORTS; gen_i++) begin : gen_dbg_head_send
            assign dbg_head_send[gen_i] = sa_first_in[gen_i] ? sa_data_in[gen_i] : {$bits(SiliconNetHead){1'bx}};
        end
    endgenerate
    // check send msg data
    generate
        for (gen_i = 0; gen_i < NUM_PORTS; gen_i++) begin : gen_dbg_data_send
            assign dbg_data_send[gen_i] = sa_valid_in[gen_i] ? (sa_first_in[gen_i] ? {{($bits(sa_data_in[gen_i])-1){1'bz}},1'b0} : sa_data_in[gen_i]) : {($bits(sa_data_in[gen_i])){1'bx}};
        end
    endgenerate

    // check received msg header   
    generate
        for (gen_i = 0; gen_i < NUM_PORTS; gen_i++) begin : gen_dbg_head_receive
            assign dbg_head_receive[gen_i] = sa_first_out[gen_i] ? sa_data_out[gen_i] : {$bits(SiliconNetHead){1'bx}};
        end
    endgenerate
    // check received msg data
    generate
        for (gen_i = 0; gen_i < NUM_PORTS; gen_i++) begin : gen_dbg_data_receive
            assign dbg_data_receive[gen_i] = sa_valid_out[gen_i] ? (sa_first_out[gen_i] ? {{($bits(sa_data_out[gen_i])-1){1'bz}},1'b0} : sa_data_out[gen_i]) : {($bits(sa_data_out[gen_i])){1'bx}};
        end
    endgenerate

endmodule