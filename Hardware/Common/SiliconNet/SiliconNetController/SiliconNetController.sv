///////////////////////////////////////////////////////////////
//
// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.
//
////////////////////////////////////////////////////////////////

import SiliconNetTypes::*;
import NetworkTypes::IP4Address;

module SiliconNetController
#(
    // Connector related
    parameter NUM_PORTS                         = SN_NUM_PORTS,
    // ForwardingTable related
    parameter NUM_TABLES                        = 2,
    parameter NUM_KEYS_HIGH                     = 4,
    parameter NUM_KEYS_LOW                      = 16,
    parameter WIDTH_HIGH                        = $bits(IP4Address),
    parameter WIDTH_LOW                         = SN_ADDR_WIDTH,
    // ForwardingTable config parameters
    parameter CTL_REG_WRITE_KEY_ADDR            = SN_CTL_REG_WRITE_KEY_ADDR,
    parameter CTL_REG_WRITE_MSK_ADDR            = SN_CTL_REG_WRITE_MSK_ADDR,
    parameter CTL_REG_READ_KEY_ADDR             = SN_CTL_REG_READ_KEY_ADDR,
    parameter CTL_REG_READ_MSK_ADDR             = SN_CTL_REG_READ_MSK_ADDR,
    parameter CTL_REG_READ_EP_ADDR              = SN_CTL_REG_READ_EP_ADDR,
    parameter CTL_REG_ADDR                      = SN_CTL_REG_ADDR,
    // Connector counter
    parameter CTL_REG_COUNTER_VALUE_ADDR        = SN_CTL_REG_COUNTER_VALUE_ADDR
)
(
    input                                       clk,
    input                                       rst,

    // Controller Register Interface
    input                                       ctl_read_in,
    input                                       ctl_write_in,
    input         [15:0]                        ctl_addr_in,
    input         [63:0]                        ctl_wrdata_in,
    output reg    [63:0]                        ctl_rddata_out,
    output reg                                  ctl_rdvalid_out,

    // Address high field configure
    output reg                                  high_cfg_out                [NUM_PORTS-1:0],
    output reg    [$clog2(NUM_KEYS_HIGH):0]     high_cfg_index_out          [NUM_PORTS-1:0],  // index [NUM_KEYS] is used for set and load the default endpoint
    output reg                                  high_cfg_valid_out          [NUM_PORTS-1:0],
    output reg    [WIDTH_HIGH-1:0]              high_cfg_key_out            [NUM_PORTS-1:0],
    output reg    [WIDTH_HIGH-1:0]              high_cfg_msk_out            [NUM_PORTS-1:0],
    output reg    [$clog2(NUM_PORTS)-1:0]       high_cfg_endpoint_out       [NUM_PORTS-1:0],
    // read out
    output reg                                  high_cfg_read_out           [NUM_PORTS-1:0],
    input                                       high_cfg_read_valid_in      [NUM_PORTS-1:0],
    input                                       high_cfg_valid_in           [NUM_PORTS-1:0],
    input         [WIDTH_HIGH-1:0]              high_cfg_key_in             [NUM_PORTS-1:0],
    input         [WIDTH_HIGH-1:0]              high_cfg_msk_in             [NUM_PORTS-1:0],
    input         [$clog2(NUM_PORTS)-1:0]       high_cfg_endpoint_in        [NUM_PORTS-1:0],

    // Address low field onfigure
    output reg                                  low_cfg_out                 [NUM_PORTS-1:0],
    output reg    [$clog2(NUM_KEYS_LOW):0]      low_cfg_index_out           [NUM_PORTS-1:0],   // index [NUM_KEYS] is used for set and load the default endpoint
    output reg                                  low_cfg_valid_out           [NUM_PORTS-1:0],
    output reg    [WIDTH_LOW-1:0]               low_cfg_key_out             [NUM_PORTS-1:0],
    output reg    [WIDTH_LOW-1:0]               low_cfg_msk_out             [NUM_PORTS-1:0],
    output reg    [$clog2(NUM_PORTS)-1:0]       low_cfg_endpoint_out        [NUM_PORTS-1:0],
    //
    output reg                                  low_cfg_read_out            [NUM_PORTS-1:0],
    input                                       low_cfg_read_valid_in       [NUM_PORTS-1:0],
    input                                       low_cfg_valid_in            [NUM_PORTS-1:0],
    input         [WIDTH_LOW-1:0]               low_cfg_key_in              [NUM_PORTS-1:0],
    input         [WIDTH_LOW-1:0]               low_cfg_msk_in              [NUM_PORTS-1:0],
    input         [$clog2(NUM_PORTS)-1:0]       low_cfg_endpoint_in         [NUM_PORTS-1:0],

    // connector debug counter
    output reg                                  counter_read_out            [NUM_PORTS-1:0],
    output reg    [2:0]                         counter_index_out           [NUM_PORTS-1:0],
    input                                       counter_value_valid_in      [NUM_PORTS-1:0],
    input         [63:0]                        counter_value_in            [NUM_PORTS-1:0]
);

    typedef struct packed
    {
        //byte 7
        logic               wr_req;             //63
        logic               wr_cmpl;            //62
        logic               rd_req;             //61
        logic               rd_cmpl;            //60
        logic               valid;              //59
        logic               counter_req;        //58
        logic               counter_cmpl;       //57
        logic               reserved1;          //56
        //byte 6
        logic [ 5:0]        connector_id;       //55:50
        logic [ 1:0]        table_id;           //49:48
        //byte 5,4
        logic [15:0]        entry_id;           //47:32
        //byte3
        logic [ 5:0]        ep;                 //31:26
        logic [ 1:0]        reserved2;          //25:24
        //byte 2
        logic [ 3:0]        wr_req_counter;     //23:20
        logic [ 3:0]        wr_cmpl_counter;    //19:16
        //byte 1
        logic [ 3:0]        rd_req_counter;     //15:12
        logic [ 3:0]        rd_cmpl_counter;    //11:8
        //byte0
        logic [ 7:0]        reserved3;          //7:0
    } Control_Reg;

    typedef struct packed
    {
        logic               valid;
        logic [ 5:0]        ep;
        logic [56:0]        reserved;
    } Read_EP_Reg;

    /////////////////////////////////////////////////////////////////////////////////////////////
    // Register Interface
    /////////////////////////////////////////////////////////////////////////////////////////////

    //SN_CTL_REG defination

    
    //SN_CTL_REG_xxx_KEY defination
    //(1) bit 63-0 :         table entry key value
    
    //SN_CTL_REG_xxx_MSK defination
    //(1) bit 63-0 :         table entry mask value

    Control_Reg sn_ctl_reg;
    reg [63:0]  sn_ctl_write_key_reg;
    reg [63:0]  sn_ctl_write_msk_reg;
    reg [63:0]  sn_ctl_read_key_reg;
    reg [63:0]  sn_ctl_read_msk_reg;
    Read_EP_Reg sn_ctl_read_ep_reg;
    reg [63:0]  sn_ctl_read_counter_reg;
    
    //temp reg
    reg [5 :0]  connector_id;
    reg [1 :0]  table_id;     
    reg [15:0]  entry_id;

    reg write_cmpl_user;
    reg write_cmpl_sn;
    reg read_cmpl_user;
    reg read_cmpl_sn;
    reg counter_cmpl_user;
    reg counter_cmpl_sn;

    integer i;

    // reg write
    always @ (posedge clk) begin
        if (rst) begin
            // sn_ctl_reg
            sn_ctl_reg.wr_req         <= 1'b0;
            sn_ctl_reg.rd_req         <= 1'b0;
            sn_ctl_reg.counter_req    <= 1'b0;
            sn_ctl_reg.valid          <= 1'b0;
            sn_ctl_reg.connector_id   <= 6'd0;
            sn_ctl_reg.table_id       <= 2'd0;
            sn_ctl_reg.entry_id       <= 16'd0;
            sn_ctl_reg.ep             <= 6'd0;
            sn_ctl_reg.wr_req_counter <= 4'd0;
            sn_ctl_reg.rd_req_counter <= 4'd0;
            sn_ctl_reg.reserved1      <= 0;
            sn_ctl_reg.reserved2      <= 0;
            sn_ctl_reg.reserved3      <= 0;
            // sn_key & msk reg
            sn_ctl_write_key_reg      <= 64'hcafe;
            sn_ctl_write_msk_reg      <= 64'hcafe;
            // internal use
            connector_id              <= 6'd0;
            table_id                  <= 1'd0;
            entry_id                  <= 12'd0;
            write_cmpl_user           <= 1'b0;
            read_cmpl_user            <= 1'b0;
            counter_cmpl_user         <= 1'b0;
        end
        else if (ctl_write_in) begin
            case (ctl_addr_in)
                CTL_REG_WRITE_KEY_ADDR: begin
                    sn_ctl_write_key_reg      <= ctl_wrdata_in;
                end
                CTL_REG_WRITE_MSK_ADDR: begin
                    sn_ctl_write_msk_reg      <= ctl_wrdata_in;
                end
                CTL_REG_ADDR: begin
                    sn_ctl_reg.wr_req         <= ctl_wrdata_in[63];     //write request
                    write_cmpl_user           <= 1'b0;                    
                    sn_ctl_reg.rd_req         <= ctl_wrdata_in[61];     //read request
                    read_cmpl_user            <= 1'b0;
                    sn_ctl_reg.counter_req    <= ctl_wrdata_in[58];     //counter request
                    counter_cmpl_user         <= 1'b0;
                    sn_ctl_reg.connector_id   <= ctl_wrdata_in[55:50];  //connector id
                    sn_ctl_reg.table_id       <= ctl_wrdata_in[49:48];  //table id
                    sn_ctl_reg.entry_id       <= ctl_wrdata_in[47:32];  //entry id
                    sn_ctl_reg.ep             <= ctl_wrdata_in[31:26];  //endpoint value
                    sn_ctl_reg.valid          <= ctl_wrdata_in[59];     //key validation status
                    // internal use
                    connector_id              <= ctl_wrdata_in[55:50];  //connector id
                    table_id                  <= ctl_wrdata_in[49:48];  //table id
                    entry_id                  <= ctl_wrdata_in[47:32];  //entry id
                    if (ctl_wrdata_in[63]) begin
                        sn_ctl_reg.wr_req_counter <= sn_ctl_reg.wr_req_counter + 1'b1;
                    end
                    if (ctl_wrdata_in[61]) begin
                        sn_ctl_reg.rd_req_counter <= sn_ctl_reg.rd_req_counter + 1'b1;
                    end
                end
                default: begin
                    // sn_ctl_reg
                    sn_ctl_reg.wr_req         <= 1'b0;
                    sn_ctl_reg.rd_req         <= 1'b0;
                    sn_ctl_reg.counter_req    <= 1'b0;
                    sn_ctl_reg.valid          <= 1'b0;
                    sn_ctl_reg.connector_id   <= 6'd0;
                    sn_ctl_reg.table_id       <= 2'd0;
                    sn_ctl_reg.entry_id       <= 16'd0;
                    sn_ctl_reg.ep             <= 6'd0;
                    sn_ctl_reg.reserved1      <= 0;
                    sn_ctl_reg.reserved2      <= 0;
                    sn_ctl_reg.reserved3      <= 0;
                    // internal use
                    connector_id              <= 6'd0;
                    table_id                  <= 1'd0;
                    entry_id                  <= 12'd0;
                    write_cmpl_user           <= 1'b0;
                    read_cmpl_user            <= 1'b0;
                    counter_cmpl_user         <= 1'b0;
                end
            endcase
        end
        else begin
            // sn_ctl_reg
            sn_ctl_reg.wr_req         <= 1'b0;
            sn_ctl_reg.rd_req         <= 1'b0;
            sn_ctl_reg.counter_req    <= 1'b0;
            sn_ctl_reg.valid          <= 1'b0;
            sn_ctl_reg.connector_id   <= 6'd0;
            sn_ctl_reg.table_id       <= 2'd0;
            sn_ctl_reg.entry_id       <= 16'd0;
            sn_ctl_reg.ep             <= 6'd0;
            sn_ctl_reg.reserved1      <= 0;
            sn_ctl_reg.reserved2      <= 0;
            sn_ctl_reg.reserved3      <= 0;
            // internal use
            connector_id              <= 6'd0;
            table_id                  <= 1'd0;
            entry_id                  <= 12'd0;
        end
    end

    // reg read
    always @ (posedge clk) begin
        if (rst) begin
            ctl_rddata_out          <= 64'd0;
            ctl_rdvalid_out         <= 1'b0;
        end
        else if (ctl_read_in) begin
            case (ctl_addr_in)
                CTL_REG_READ_KEY_ADDR: begin
                    ctl_rddata_out      <= sn_ctl_read_key_reg;
                    ctl_rdvalid_out     <= 1'b1;
                end
                CTL_REG_READ_MSK_ADDR: begin
                    ctl_rddata_out      <= sn_ctl_read_msk_reg;
                    ctl_rdvalid_out     <= 1'b1;
                end
                CTL_REG_READ_EP_ADDR: begin
                    ctl_rddata_out      <= sn_ctl_read_ep_reg;
                    ctl_rdvalid_out     <= 1'b1;
                end
                SN_CTL_REG_COUNTER_VALUE_ADDR: begin
                    ctl_rddata_out      <= sn_ctl_read_counter_reg;
                    ctl_rdvalid_out     <= 1'b1;
                end                
                CTL_REG_ADDR: begin
                    ctl_rddata_out              <= 62'd0;
                    ctl_rddata_out[62]          <= sn_ctl_reg.wr_cmpl;     //write complete, read only
                    ctl_rddata_out[60]          <= sn_ctl_reg.rd_cmpl;     //read complete, read only
                    ctl_rddata_out[57]          <= sn_ctl_reg.counter_cmpl;//counter complete, read only
                    ctl_rddata_out[23:20]       <= sn_ctl_reg.wr_req_counter;
                    ctl_rddata_out[19:16]       <= sn_ctl_reg.wr_cmpl_counter;
                    ctl_rddata_out[15:12]       <= sn_ctl_reg.rd_req_counter;
                    ctl_rddata_out[11:8]        <= sn_ctl_reg.rd_cmpl_counter;
                    ctl_rdvalid_out             <= 1'b1;                    
                end
                default: begin
                    ctl_rddata_out  <= {32'hdeadbeef, 16'h0, ctl_addr_in};
                    ctl_rdvalid_out <= 1'b1;
                end
            endcase
        end
        else begin
            ctl_rddata_out          <= 64'd0;
            ctl_rdvalid_out         <= 1'b0;
        end
    end

    /////////////////////////////////////////////////////////////////////////////////////////////
    // Forwarding Table Configuration Interface
    /////////////////////////////////////////////////////////////////////////////////////////////

    // configuration
    always @ (posedge clk) begin
        if (rst) begin
            for (i = 0; i < NUM_PORTS; i++) begin
                // config write
                high_cfg_out[i]             <= 1'b0;
                high_cfg_index_out[i]       <= {($clog2(NUM_KEYS_HIGH)+1){1'b0}};
                high_cfg_valid_out[i]       <= 1'b0;
                high_cfg_key_out[i]         <= {WIDTH_HIGH{1'b0}};
                high_cfg_msk_out[i]         <= {WIDTH_HIGH{1'b0}};
                high_cfg_endpoint_out[i]    <= {$clog2(NUM_PORTS){1'b0}};
                low_cfg_out[i]              <= 1'b0;
                low_cfg_index_out[i]        <= {($clog2(NUM_KEYS_LOW)+1){1'b0}};
                low_cfg_valid_out[i]        <= 1'b0;
                low_cfg_key_out[i]          <= {WIDTH_LOW{1'b0}};
                low_cfg_msk_out[i]          <= {WIDTH_LOW{1'b0}};
                low_cfg_endpoint_out[i]     <= {$clog2(NUM_PORTS){1'b0}};
                // config read
                high_cfg_read_out[i]        <= 1'b0;
                high_cfg_index_out[i]       <= {($clog2(NUM_KEYS_HIGH)+1){1'b0}};                
                low_cfg_read_out[i]         <= 1'b0;
                low_cfg_index_out[i]        <= {($clog2(NUM_KEYS_LOW)+1){1'b0}}; 
            end
            write_cmpl_sn                   <= 1'b0;
            sn_ctl_reg.wr_cmpl_counter      <= 4'd0;
        end
        else if ((sn_ctl_reg.wr_req)&(~sn_ctl_reg.rd_req)) begin  //ctl reg set to write
            case (table_id)  //check table id
                8'd1: begin  //high table
                    high_cfg_out[connector_id]             <= 1'b1;
                    high_cfg_index_out[connector_id]       <= sn_ctl_reg.entry_id;
                    high_cfg_valid_out[connector_id]       <= sn_ctl_reg.valid;
                    high_cfg_key_out[connector_id]         <= sn_ctl_write_key_reg;
                    high_cfg_msk_out[connector_id]         <= sn_ctl_write_msk_reg;
                    high_cfg_endpoint_out[connector_id]    <= sn_ctl_reg.ep;
                    write_cmpl_sn                          <= 1'b1;
                    sn_ctl_reg.wr_cmpl_counter             <= sn_ctl_reg.wr_cmpl_counter + 1'b1;
                end
                8'd0: begin  //low table
                    low_cfg_out[connector_id]              <= 1'b1;
                    low_cfg_index_out[connector_id]        <= sn_ctl_reg.entry_id;
                    low_cfg_valid_out[connector_id]        <= sn_ctl_reg.valid;
                    low_cfg_key_out[connector_id]          <= sn_ctl_write_key_reg;
                    low_cfg_msk_out[connector_id]          <= sn_ctl_write_msk_reg;
                    low_cfg_endpoint_out[connector_id]     <= sn_ctl_reg.ep;
                    write_cmpl_sn                          <= 1'b1;
                    sn_ctl_reg.wr_cmpl_counter             <= sn_ctl_reg.wr_cmpl_counter + 1'b1;
                end                
                default: begin
                    for (i = 0; i < NUM_PORTS; i++) begin
                        high_cfg_out[i]             <= 1'b0;
                        high_cfg_index_out[i]       <= {($clog2(NUM_KEYS_HIGH)+1){1'b0}};
                        high_cfg_valid_out[i]       <= 1'b0;
                        high_cfg_key_out[i]         <= {WIDTH_HIGH{1'b0}};
                        high_cfg_msk_out[i]         <= {WIDTH_HIGH{1'b0}};
                        high_cfg_endpoint_out[i]    <= {$clog2(NUM_PORTS){1'b0}};
                        low_cfg_out[i]              <= 1'b0;
                        low_cfg_index_out[i]        <= {($clog2(NUM_KEYS_LOW)+1){1'b0}};
                        low_cfg_valid_out[i]        <= 1'b0;
                        low_cfg_key_out[i]          <= {WIDTH_LOW{1'b0}};
                        low_cfg_msk_out[i]          <= {WIDTH_LOW{1'b0}};
                        low_cfg_endpoint_out[i]     <= {$clog2(NUM_PORTS){1'b0}};
                    end
                    write_cmpl_sn                   <= 1'b0;
                end
            endcase
        end
        else if ((~sn_ctl_reg.wr_req)&(sn_ctl_reg.rd_req)) begin  //ctl reg set to read
            case (table_id)  //check table id
                8'd1: begin  //high table
                    high_cfg_read_out[connector_id]        <= 1'b1;
                    high_cfg_index_out[connector_id]       <= sn_ctl_reg.entry_id;
                end
                8'd0: begin  //low table
                    low_cfg_read_out[connector_id]         <= 1'b1;
                    low_cfg_index_out[connector_id]        <= sn_ctl_reg.entry_id;
                end                
                default: begin
                    for (i = 0; i < NUM_PORTS; i++) begin
                        high_cfg_read_out[i]        <= 1'b0;
                        high_cfg_index_out[i]       <= {($clog2(NUM_KEYS_HIGH)+1){1'b0}};                
                        low_cfg_read_out[i]         <= 1'b0;
                        low_cfg_index_out[i]        <= {($clog2(NUM_KEYS_LOW)+1){1'b0}}; 
                    end
                end
            endcase
        end
        else begin
            for (i = 0; i < NUM_PORTS; i++) begin
                high_cfg_out[i]             <= 1'b0;
                high_cfg_index_out[i]       <= {($clog2(NUM_KEYS_HIGH)+1){1'b0}};
                high_cfg_valid_out[i]       <= 1'b0;
                high_cfg_key_out[i]         <= {WIDTH_HIGH{1'b0}};
                high_cfg_msk_out[i]         <= {WIDTH_HIGH{1'b0}};
                high_cfg_endpoint_out[i]    <= {$clog2(NUM_PORTS){1'b0}};
                low_cfg_out[i]              <= 1'b0;
                low_cfg_index_out[i]        <= {($clog2(NUM_KEYS_LOW)+1){1'b0}};
                low_cfg_valid_out[i]        <= 1'b0;
                low_cfg_key_out[i]          <= {WIDTH_LOW{1'b0}};
                low_cfg_msk_out[i]          <= {WIDTH_LOW{1'b0}};
                low_cfg_endpoint_out[i]     <= {$clog2(NUM_PORTS){1'b0}};
                high_cfg_read_out[i]        <= 1'b0;
                high_cfg_index_out[i]       <= {($clog2(NUM_KEYS_HIGH)+1){1'b0}};                
                low_cfg_read_out[i]         <= 1'b0;
                low_cfg_index_out[i]        <= {($clog2(NUM_KEYS_LOW)+1){1'b0}};
            end
        end
    end

    // table content read back to register
    always @ (posedge clk) begin
        if (rst) begin
            sn_ctl_read_key_reg             <= 64'd0;
            sn_ctl_read_msk_reg             <= 64'd0;
            sn_ctl_read_ep_reg              <= 64'd0;
            read_cmpl_sn                    <= 1'b0;
            sn_ctl_reg.rd_cmpl_counter      <= 0;
        end
        else begin
            for (i=0; i<NUM_PORTS; i++) begin
                if (high_cfg_read_valid_in[i]) begin
                    sn_ctl_read_key_reg         <= high_cfg_key_in[i];
                    sn_ctl_read_msk_reg         <= high_cfg_msk_in[i];
                    sn_ctl_read_ep_reg.valid    <= high_cfg_valid_in[i];
                    sn_ctl_read_ep_reg.ep       <= high_cfg_endpoint_in[i];
                    read_cmpl_sn                <= 1'b1;
                    sn_ctl_reg.rd_cmpl_counter  <= sn_ctl_reg.rd_cmpl_counter + 1'b1;
                end            
                else if (low_cfg_read_valid_in[i]) begin
                    sn_ctl_read_key_reg         <= low_cfg_key_in[i];
                    sn_ctl_read_msk_reg         <= low_cfg_msk_in[i];
                    sn_ctl_read_ep_reg.valid    <= low_cfg_valid_in[i];
                    sn_ctl_read_ep_reg.ep       <= low_cfg_endpoint_in[i];
                    read_cmpl_sn                <= 1'b1;
                    sn_ctl_reg.rd_cmpl_counter  <= sn_ctl_reg.rd_cmpl_counter + 1'b1;
                end
            end
        end
    end

    // generate write completion
    always @ (posedge clk) begin
        if (rst) begin
            sn_ctl_reg.wr_cmpl      <= 1'b0;
        end
        else if (sn_ctl_reg.wr_req) begin //user write triggered
            sn_ctl_reg.wr_cmpl      <= write_cmpl_user;
        end
        else begin
            sn_ctl_reg.wr_cmpl      <= write_cmpl_sn;
        end
    end

    // generate read completion
    always @ (posedge clk) begin
        if (rst) begin
            sn_ctl_reg.rd_cmpl      <= 1'b0;
        end
        else if (sn_ctl_reg.rd_req) begin //user write triggered
            sn_ctl_reg.rd_cmpl      <= read_cmpl_user;
        end
        else begin
            sn_ctl_reg.rd_cmpl      <= read_cmpl_sn;
        end
    end

    /////////////////////////////////////////////////////////////////////////////////////////////
    // Counter readout Interface
    /////////////////////////////////////////////////////////////////////////////////////////////

    // counter
    always @ (posedge clk) begin
        if (rst) begin
            for (i = 0; i < NUM_PORTS; i++) begin
                counter_read_out[i]         <= 1'b0;
                counter_index_out[i]        <= 3'b0;
            end
        end
        else if (sn_ctl_reg.counter_req) begin  //ctl reg set to counter request
            counter_read_out[connector_id]      <= 1'b1;
            counter_index_out[connector_id]     <= sn_ctl_reg.entry_id;                    
        end
        else begin
            for (i = 0; i < NUM_PORTS; i++) begin
                counter_read_out[i]         <= 1'b0;
                counter_index_out[i]        <= 3'b0;
            end
        end
    end

    // counter read back to register
    always @ (posedge clk) begin
        if (rst) begin
            sn_ctl_read_counter_reg             <= 64'd0;
            counter_cmpl_sn                     <= 1'b0;
        end
        else begin
            for (i=0; i<NUM_PORTS; i++) begin
                if (counter_value_valid_in[i]) begin
                    sn_ctl_read_counter_reg         <= counter_value_in[i];
                    counter_cmpl_sn                 <= 1'b1;
                end
            end
        end
    end

    // generate counter completion
    always @ (posedge clk) begin
        if (rst) begin
            sn_ctl_reg.counter_cmpl      <= 1'b0;
        end
        else if (sn_ctl_reg.counter_req) begin //user write triggered
            sn_ctl_reg.counter_cmpl      <= counter_cmpl_user;
        end
        else begin
            sn_ctl_reg.counter_cmpl      <= counter_cmpl_sn;
        end
    end

endmodule