///////////////////////////////////////////////////////////////
//
// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.
//
////////////////////////////////////////////////////////////////

import SiliconNetTypes::*;
import NetworkTypes::IP4Address;

`timescale 1ns / 1ps
`define STACK_IS_SLOWER = 1
//`undef STACK_IS_SLOWER

module SiliconNetTestbench;

    ////////// Connector 
    parameter DATA_WIDTH             = SN_DATA_WIDTH;
    parameter UID_WIDTH              = SN_UID_WIDTH;
    parameter LENGTH_WIDTH           = SN_LENGTH_WIDTH;
    parameter FLAG_WIDTH             = SN_FLAG_WIDTH;
    parameter SEQNUM_WIDTH           = SN_SEQNUM_WIDTH;
    parameter TYPE_WIDTH             = SN_TYPE_WIDTH;
    parameter PARAM_WIDTH            = SN_PARAM_WIDTH;  
    parameter NUM_PORTS              = SN_NUM_PORTS;
    parameter MAX_MSG_LENGTH         = SN_MAX_MSG_LENGTH;
    // ForwardingTable related
    parameter NUM_KEYS_HIGH          = SN_NUM_PORTS;
    parameter NUM_KEYS_LOW           = 16;
    parameter WIDTH_HIGH             = $bits(IP4Address);
    parameter WIDTH_LOW              = SN_DEVID_WIDTH;
    // control parameters
    parameter CTL_REG_WRITE_KEY_ADDR         = 16'h105;
    parameter CTL_REG_WRITE_MSK_ADDR         = 16'h104;
    parameter CTL_REG_READ_KEY_ADDR          = 16'h103;
    parameter CTL_REG_READ_MSK_ADDR          = 16'h102;
    parameter CTL_REG_READ_EP_ADDR           = 16'h101;
    parameter CTL_REG_ADDR                   = 16'h100;

    parameter CTL_REG_COUNTER_VALUE_ADDR     = 16'h110;

    ////////// ER
    parameter NUM_VCS                           = SN_NUM_VCS;
    parameter PHIT_WIDTH                        = SN_PHIT_WIDTH;
    parameter FLIT_WIDTH                        = SN_FLIT_WIDTH;
    // Per-Input Port Parameters
    parameter NUM_FLITS                         = SN_NUM_FLITS;
    parameter FLITS_PER_MESSAGE                 = SN_FLITS_PER_MESSAGE;
    // Per-Output Downstream Parameters
    parameter MAX_FLITS_PER_PORT_DOWNSTREAM     = SN_FLITS_PER_PORT_DOWNSTREAM;
    parameter MAX_CREDIT_WIDTH                  = SN_MAX_CREDIT_WIDTH;
    // Optimization/debug/status
    parameter DISABLE_UTURN                     = SN_DISABLE_UTURN;
    parameter USE_LUTRAM                        = SN_USE_LUTRAM;

    localparam HIGH_TABLE            = 1;
    localparam LOW_TABLE             = 0;

    parameter TEST_MODE                         = 0; 
    //0: 1-1,1-N
    //1: N-1
    //2: N-N
    //note: tester should manually comment or uncomment, only enable one block each test to prevent multi-drivring

    reg                                         clk;
    reg                                         rst;

    // Stack/App side
    reg                                         sa_clk                    [NUM_PORTS-1:0];
    reg                                         sa_rst                    [NUM_PORTS-1:0];

    // Stack/App Side - (RX: Connector -> Stack/App)
    wire          [DATA_WIDTH-1:0]              sa_data_out               [NUM_PORTS-1:0];
    wire                                        sa_valid_out              [NUM_PORTS-1:0];
    wire                                        sa_first_out              [NUM_PORTS-1:0];
    wire                                        sa_last_out               [NUM_PORTS-1:0];
    reg                                         sa_ready_in               [NUM_PORTS-1:0];

    // Stack/App Side - (TX: Stack/App -> Connector)
    reg           [DATA_WIDTH-1:0]              sa_data_in                [NUM_PORTS-1:0];
    reg                                         sa_valid_in               [NUM_PORTS-1:0];
    reg                                         sa_first_in               [NUM_PORTS-1:0];
    reg                                         sa_last_in                [NUM_PORTS-1:0];
    wire                                        sa_ready_out              [NUM_PORTS-1:0];

    // Configure to FPGA CA
    reg               ctl_read_in;
    reg               ctl_write_in;
    reg     [15:0]    ctl_addr_in;
    reg     [63:0]    ctl_wrdata_in;
    wire    [63:0]    ctl_rddata_out;
    wire              ctl_rdvalid_out;

    integer     i               = 0;
    integer     j               = 0;
    genvar      gen_i;

    integer     int_i           = 100;

    //sub test #1
    //msg length = 1;
    //sub test #2
    integer     int_j           = 0;
    integer     int_k           = 0;
    integer     int_j_length    = 2;
    //sub test #3
    integer     int_l           = 0;
    integer     int_m           = 0;
    integer     int_l_length    = 4;
    //sub test #4
    integer     int_n           = 0;
    integer     int_o           = 0;
    integer     int_n_length    = 8;
    //sub test #5, reconfig ForwardingTable
    integer     int_p           = 0;
    integer     int_q           = 0;
    integer     int_p_length    = 9;
    //sub test #6, long msg
    integer     int_r           = 0;
    integer     int_s           = 0;
    integer     int_r_length    = 200;  //max 248, exceed will cause ER buffer overflow, set 129 to cover 4KB
    //sub test #7, N-1
    reg [31:0]  int_t  [NUM_PORTS-1:0] = {0,0,0,0,0,0,0,0};
    reg [31:0]  int_u  [NUM_PORTS-1:0] = {0,0,0,0,0,0,0,0};
    integer     int_t_length    = 4;  //max 248, exceed will cause ER buffer overflow, set 129 to cover 4KB
    //sub test #8, N-N
    reg [31:0]  int_v  [NUM_PORTS-1:0] = {0,0,0,0,0,0,0,0};
    reg [31:0]  int_w  [NUM_PORTS-1:0] = {0,0,0,0,0,0,0,0};
    integer     int_v_length    = 100;  //max 248, exceed will cause ER buffer overflow, set 129 to cover 4KB

    integer     displayflag1 = 1;
    integer     displayflag2 = 1;
    integer     displayflag3 = 1;
    integer     displayflag4 = 1;
    integer     displayflag5 = 1;
    integer     displayflag6 = 1;
    integer     displayflag7 = 1;
    integer     displayflag8 = 1;

    reg [31:0]  int_rand  [NUM_PORTS-1:0] = {0,0,0,0,0,0,0,0};

    reg     [63:0]  counter     = 0;
    reg     [63:0]  counter_sa  = 0;

    typedef enum logic [3:0] {
        IDLE            = 4'd0,
        SUB1            = 4'd1,
        SUB2            = 4'd2,
        SUB3            = 4'd3,
        SUB4            = 4'd4,
        SUB5            = 4'd5,
        SUB6            = 4'd6,
        SUB7            = 4'd7,
        SUB8            = 4'd8,
        SUB9            = 4'd9,
        SUB10           = 4'd10,
        SUB11           = 4'd11,
        SUB12           = 4'd12,
        CFG             = 4'd15
    } SUB_TEST_STRUCT;

    SUB_TEST_STRUCT sub_test;
   
    SiliconNet
    #(
        .TYPE_WIDTH                     (TYPE_WIDTH),
        .DATA_WIDTH                     (DATA_WIDTH),
        .UID_WIDTH                      (UID_WIDTH),
        .LENGTH_WIDTH                   (LENGTH_WIDTH),
        .FLAG_WIDTH                     (FLAG_WIDTH),
        .PARAM_WIDTH                    (PARAM_WIDTH),
        .NUM_PORTS                      (NUM_PORTS),
        .MAX_MSG_LENGTH                 (MAX_MSG_LENGTH),
 
        .NUM_TABLES                     (2),
        .NUM_KEYS_HIGH                  (NUM_KEYS_HIGH),
        .NUM_KEYS_LOW                   (NUM_KEYS_LOW),
        .WIDTH_HIGH                     (WIDTH_HIGH),
        .WIDTH_LOW                      (WIDTH_LOW),

        .CTL_REG_WRITE_KEY_ADDR         (CTL_REG_WRITE_KEY_ADDR),
        .CTL_REG_WRITE_MSK_ADDR         (CTL_REG_WRITE_MSK_ADDR),
        .CTL_REG_READ_KEY_ADDR          (CTL_REG_READ_KEY_ADDR),
        .CTL_REG_READ_MSK_ADDR          (CTL_REG_READ_MSK_ADDR),
        .CTL_REG_ADDR                   (CTL_REG_ADDR),

        .NUM_VCS                        (NUM_VCS),
        .PHIT_WIDTH                     (PHIT_WIDTH),
        .FLIT_WIDTH                     (FLIT_WIDTH),
    
        .NUM_FLITS                      (NUM_FLITS),
        .FLITS_PER_MESSAGE              (FLITS_PER_MESSAGE),
    
        .MAX_FLITS_PER_PORT_DOWNSTREAM  (MAX_FLITS_PER_PORT_DOWNSTREAM),
        .MAX_CREDIT_WIDTH               (MAX_CREDIT_WIDTH),
    
        .DISABLE_UTURN                  (DISABLE_UTURN),
        .USE_LUTRAM                     (USE_LUTRAM)
    )
    SiliconNet
    (
        .clk                            (clk),
        .rst                            (rst),

        .sa_clk                         (sa_clk),
        .sa_rst                         (sa_rst),

        .sa_data_out                    (sa_data_out),
        .sa_valid_out                   (sa_valid_out),
        .sa_first_out                   (sa_first_out),
        .sa_last_out                    (sa_last_out),
        .sa_ready_in                    (sa_ready_in),

        .sa_data_in                     (sa_data_in),
        .sa_valid_in                    (sa_valid_in),
        .sa_first_in                    (sa_first_in),
        .sa_last_in                     (sa_last_in),
        .sa_ready_out                   (sa_ready_out),

        .ctl_read_in                    (ctl_read_in),
        .ctl_write_in                   (ctl_write_in),
        .ctl_addr_in                    (ctl_addr_in),
        .ctl_wrdata_in                  (ctl_wrdata_in),
        .ctl_rddata_out                 (ctl_rddata_out),
        .ctl_rdvalid_out                (ctl_rdvalid_out)
    );

    


    //////////////////////////////////////////////////////////////////////////////////////
    //initialization task
    //////////////////////////////////////////////////////////////////////////////////////
    task init;
        // clk & rst
        clk             = 0;
        rst             = 0;

        // regigster configuration
        ctl_read_in        = 0;
        ctl_write_in       = 0;
        ctl_addr_in        = 0;
        ctl_wrdata_in      = 0;       

        for (i = 0; i < NUM_PORTS; i++) begin
            // S/A clk and rst
            sa_clk[i]          = 0;
            sa_rst[i]          = 1;

            // S/A side rx
            sa_ready_in[i]     = 0;

            // S/A side tx
            sa_data_in[i]      = {DATA_WIDTH{1'b0}};
            sa_valid_in[i]     = 0;
            sa_first_in[i]     = 0;
            sa_last_in[i]      = 0;
        end
    endtask

    //////////////////////////////////////////////////////////////////////////////////////
    //generate packets tasks
    //////////////////////////////////////////////////////////////////////////////////////
    function UID makeUID(integer d3, integer d2, integer d1, integer d0,
                         integer devID);
        makeUID.ipv4.d3     = d3;
        makeUID.ipv4.d2     = d2;
        makeUID.ipv4.d1     = d1;
        makeUID.ipv4.d0     = d0;
        makeUID.devID       = devID;
    endfunction

    function SiliconNetHead makeSNHead(UID src_uid, UID dst_uid, integer length, integer flag, integer seqnum, SN_REQ_TYPE req, integer param);
        makeSNHead              = 0;        
        makeSNHead.src_uid      = src_uid;
        makeSNHead.dst_uid      = dst_uid;
        makeSNHead.msg_length   = length;
        makeSNHead.msg_flag     = flag;
        makeSNHead.msg_seqnum   = seqnum;
        makeSNHead.req_type     = req;
        makeSNHead.req_param    = param;
    endfunction

    task make_SiliconNet_fistlast;
        input integer       port;
        input SN_REQ_TYPE   req;
        input integer       dstIP;
        input integer       length;
        input integer       srcdevID;
        input integer       dstdevID;
        input integer       seq;
        sa_data_in[port]          = makeSNHead(makeUID(88,0,0,port, srcdevID), makeUID(0,0,0,dstIP, dstdevID), length, 0, seq, req, 0);
        sa_valid_in[port]         = 1;
        sa_first_in[port]         = 1;
        sa_last_in[port]          = 1;
        $display("SiliconNet MSG First&Last -->");
    endtask

    task make_SiliconNet_first;
        input integer       port;
        input SN_REQ_TYPE   req;
        input integer       dstIP;
        input integer       length;
        input integer       srcdevID;
        input integer       dstdevID;
        input integer       seq;
        sa_data_in[port]          = makeSNHead(makeUID(88,0,0,port, srcdevID), makeUID(0,0,0,dstIP, dstdevID), length, 0, seq, req, 0);
        sa_valid_in[port]         = 1;
        sa_first_in[port]         = 1;
        sa_last_in[port]          = 0;
        $display("SiliconNet MSG Frst -->");
    endtask
    task make_SiliconNet_last;
        input integer port;
        input reg [255:0] data;
        sa_data_in[port]          = data;
        sa_valid_in[port]         = 1;
        sa_first_in[port]         = 0;
        sa_last_in[port]          = 1;
        $display("SiliconNet MSG Last --> %d", data);
    endtask
    task make_SiliconNet_body;
        input integer port;
        input reg [255:0] data;
        sa_data_in[port]          = data;
        sa_valid_in[port]         = 1;
        sa_first_in[port]         = 0;
        sa_last_in[port]          = 0;
        $display("SiliconNet MSG Body --> %d", data);
    endtask
    task make_SiliconNet_end;
        input integer port;
        sa_data_in[port]          = 0;
        sa_valid_in[port]         = 0;
        sa_first_in[port]         = 0;
        sa_last_in[port]          = 0;
    endtask

    //////////////////////////////////////////////////////////////////////////////////////
    //config forwarding table tasks
    //////////////////////////////////////////////////////////////////////////////////////
    task table_entry_write;
        input integer port;
        input integer which_table;
        input integer index;
        input integer valid;
        input integer k3, k2, k1, k0;
        input integer m3, m2, m1, m0;
        input integer endpoint;

        ctl_write_in                = 1;
        ctl_addr_in                 = CTL_REG_WRITE_KEY_ADDR;
        ctl_wrdata_in[31:24]        = k3;
        ctl_wrdata_in[23:16]        = k2;
        ctl_wrdata_in[15: 8]        = k1;
        ctl_wrdata_in[ 7: 0]        = k0;

        #20 ctl_write_in            = 0;
        ctl_addr_in                 = 0;
        ctl_wrdata_in               = 0;

        #100 ctl_write_in            = 1;
        ctl_addr_in                 = CTL_REG_WRITE_MSK_ADDR;
        ctl_wrdata_in[31:24]        = m3;
        ctl_wrdata_in[23:16]        = m2;
        ctl_wrdata_in[15: 8]        = m1;
        ctl_wrdata_in[ 7: 0]        = m0;

        #20 ctl_write_in            = 0;
        ctl_addr_in                 = 0;
        ctl_wrdata_in               = 0;

        #100 ctl_write_in            = 1;
        ctl_addr_in                 = CTL_REG_ADDR;
        ctl_wrdata_in[63]           = 1;
        ctl_wrdata_in[55:50]        = port;
        ctl_wrdata_in[49:48]        = which_table;
        ctl_wrdata_in[47:32]        = index;
        ctl_wrdata_in[31:26]        = endpoint;
        ctl_wrdata_in[59]           = valid;

        #20 ctl_write_in            = 0;
        ctl_addr_in                 = 0;
        ctl_wrdata_in               = 0;
    endtask

    task table_entry_read;
        input integer port;
        input integer which_table;
        input integer index;

        ctl_write_in                = 1;
        ctl_addr_in                 = CTL_REG_ADDR;
        ctl_wrdata_in[61]           = 1;
        ctl_wrdata_in[55:50]        = port;
        ctl_wrdata_in[49:48]        = which_table;
        ctl_wrdata_in[47:32]        = index;

        #20 ctl_write_in            = 0;
        ctl_addr_in                 = 0;
        ctl_wrdata_in               = 0;

        #100 ctl_read_in             = 1;    //read read completion
        ctl_addr_in                 = CTL_REG_ADDR;
        #20 ctl_read_in             = 1;    //read key
        ctl_addr_in                 = CTL_REG_READ_KEY_ADDR;
        #20 ctl_read_in             = 1;    //read msk
        ctl_addr_in                 = CTL_REG_READ_MSK_ADDR;
        #20 ctl_read_in             = 1;    //read ep, valid
        ctl_addr_in                 = CTL_REG_READ_EP_ADDR;
        #20 ctl_read_in             = 0;    //read end
        ctl_addr_in                 = 0;
    endtask

    //////////////////////////////////////////////////////////////////////////////////////
    //counter request tasks
    //////////////////////////////////////////////////////////////////////////////////////
    task counter_read;
        input integer port;
        input integer index;

        ctl_write_in                = 1;
        ctl_addr_in                 = CTL_REG_ADDR;
        ctl_wrdata_in[58]           = 1;
        ctl_wrdata_in[55:50]        = port;
        ctl_wrdata_in[47:32]        = index;

        #20 ctl_write_in            = 0;
        ctl_addr_in                 = 0;
        ctl_wrdata_in               = 0;

        #100 ctl_read_in            = 1;    //read read completion
        ctl_addr_in                 = CTL_REG_ADDR;
        #20 ctl_read_in             = 1;    //read counter value
        ctl_addr_in                 = CTL_REG_COUNTER_VALUE_ADDR;
        #20 ctl_read_in             = 0;    //read end
        ctl_addr_in                 = 0;
    endtask

    //////////////////////////////////////////////////////////////////////////////////////
    //clock generation
    //////////////////////////////////////////////////////////////////////////////////////
    // main clock, do not change this
    always #10 clk    = ~clk;
    generate
        for (gen_i = 0; gen_i < NUM_PORTS; gen_i++) begin
            `ifdef STACK_IS_SLOWER
                always #60 sa_clk[gen_i] = ~sa_clk[gen_i];
            `else
                always #3  sa_clk[gen_i] = ~sa_clk[gen_i];
            `endif
        end
    endgenerate


    //////////////////////////////////////////////////////////////////////////////////////
    //run
    //////////////////////////////////////////////////////////////////////////////////////
    initial begin
        init;
        sub_test    = IDLE;
        #40
        for (i=0; i<NUM_PORTS; i++) begin
            sa_rst[i]   = 1'b1;
        end
        #10
        rst         = 1'b1;        
        #50
        rst         = 1'b0;
        for (i=0; i<NUM_PORTS; i++) begin
            sa_rst[i]   = 1'b0;
        end

        //store IP [port #0]        
        sub_test    = CFG;
        //input integer port;
        //input integer which_table;
        //input integer index;
        //input integer valid;
        //input integer k3, k2, k1, k0;
        //input integer m3, m2, m1, m0;
        //input integer endpoint;

        //config IP table [port #0-3]
        for (i=0; i<NUM_PORTS; i++) begin
            for (j=0; j<NUM_KEYS_HIGH; j++) begin
                #100 table_entry_write(i, HIGH_TABLE,   j,1,   0,0,0,100+j,    0,0,0,255,   7-j);
            end
        end
        //config IP table default endpoint [port #0-3]
        for (i=0; i<NUM_PORTS; i++) begin
            #200 table_entry_write(i, HIGH_TABLE,   NUM_KEYS_HIGH,1,   0,0,0,1,    0,0,0,255,   1);
        end        

        //config addr table [port #0-3]
        for (i=0; i<NUM_PORTS; i++) begin
            for (j=0; j<NUM_KEYS_LOW; j++) begin
                #20 table_entry_write(i, LOW_TABLE,    j,1,  0,0,0,10+j,  0,0,0,255,    j%4);
            end
        end
        //config addr table default endpoint [port #0-3]
/*        for (i=0; i<NUM_PORTS; i++) begin
            #20 table_entry_write(i, LOW_TABLE,   NUM_KEYS_LOW,1,   0,0,1,0,    0,0,255,0,   2);
        end */

        //read out stored high keys
        #7000
        for (i=0; i<NUM_PORTS; i++) begin
            for (j=0; j<NUM_KEYS_HIGH+1; j++) begin
                #20 table_entry_read(i, HIGH_TABLE,  j);
            end
        end

        //read out stored low keys
        #100
        for (i=0; i<NUM_PORTS; i++) begin
            for (j=0; j<NUM_KEYS_LOW+1; j++) begin
                #20 table_entry_read(i, LOW_TABLE,  j);
            end
        end

        #1700000
        //send msg count
        for (i=0; i<NUM_PORTS; i++) begin            
            #50 counter_read(i, 3'h3);
        end

        //send msg drop count
        #50
        for (i=0; i<NUM_PORTS; i++) begin            
            #50 counter_read(i, 3'h4);
        end
        //receive msg count
        #50
        for (i=0; i<NUM_PORTS; i++) begin            
            #50 counter_read(i, 3'h5);
        end
    end

    //generate cycles per clock domain
    always @ (posedge sa_clk[0]) begin
        if (sa_rst[0]) begin
            counter_sa         <= 0;
        end
        else if (counter > 750) begin  //50: connector test value, 750: wait for siliconswitch credit
            counter_sa         <= counter_sa + 1;
        end
    end
    always @ (posedge clk) begin
        if (rst) begin
            counter         <= 0;
        end
        else begin
            counter         <= counter + 1;
        end
    end


    //////////////////////////////////////////////////////////////////////////////////////
    //testing code generator, based on the value of TEST_MODE
    //////////////////////////////////////////////////////////////////////////////////////
 
    ///////
    // 1-1, 1-N
/*    always @ (posedge sa_clk[0]) begin
        if ((counter_sa > 0)&&(counter_sa < 9)) begin  //FirLas
            // show message
            if (displayflag1) begin
                $display("//////////test data batch 01//////////");
                displayflag1 <= 0;
                sub_test     <= SUB1;
            end
            // show message end
            if (sa_ready_out[0]) begin                
                make_SiliconNet_fistlast(0,  REQ_READ, 100, 1*32,  0,  0, counter);
            end
            else begin
                make_SiliconNet_end(0);
            end
        end
        else if ((counter_sa > 100) && (int_k < 8)) begin  //
            // show message
            if (displayflag2) begin
                $display("//////////test data batch 02//////////");
                displayflag2 <= 0;
                sub_test     <= SUB2;
            end
            // show message end
            if (sa_ready_out[0]) begin                
                if (int_j==0) begin
                    make_SiliconNet_first(0,  REQ_FLSH, 101, int_j_length*32,  0,  0, counter);
                    int_j = int_j + 1;                    
                end
                else if (int_j==(int_j_length-1)) begin
                    make_SiliconNet_last(0,  int_i+205);
                    int_i = int_i + 1;
                    int_j = 0;
                    int_k = int_k + 1;
                end
                else begin
                    make_SiliconNet_body(0,  int_i+205);
                    int_i = int_i + 1;
                    int_j = int_j + 1;
                end
            end
            else begin
                make_SiliconNet_end(0);
            end
        end        
        else if ((counter_sa > 150) && (int_m < 8)) begin  //
            // show message
            if (displayflag3) begin
                $display("//////////test data batch 03//////////");
                displayflag3 <= 0;
                sub_test     <= SUB3;
            end
            // show message end
            if (sa_ready_out[0]) begin
                if (int_l==0) begin
                    make_SiliconNet_first(0,  REQ_COPY, 102, int_l_length*32,  0,  0, counter);
                    int_l = int_l + 1;                    
                end
                else if (int_l==(int_l_length-1)) begin
                    make_SiliconNet_last(0,  int_i+1008);
                    int_i = int_i + 1;
                    int_l = 0;
                    int_m = int_m + 1;
                end
                else begin
                    make_SiliconNet_body(0,  int_i+1008);
                    int_i = int_i + 1;
                    int_l = int_l + 1;
                end
            end
            else begin
                make_SiliconNet_end(0);
            end
        end
        else if ((counter_sa > 200) && (int_o < 8)) begin  //
            // show message
            if (displayflag4) begin
                $display("//////////test data batch 04//////////");
                displayflag4 <= 0;
                sub_test     <= SUB4;
            end
            // show message end
            if (sa_ready_out[0]) begin
                if (int_n==0) begin
                    make_SiliconNet_first(0,  REQ_FWRD, 103, int_n_length*32,  0,  0, counter);                 
                    int_n = int_n + 1;                    
                end
                else if (int_n==(int_n_length-1)) begin
                    make_SiliconNet_last(0,  int_i+3000);
                    int_i = int_i + 1;
                    int_n = 0;
                    int_o = int_o + 1;
                end
                else begin
                    make_SiliconNet_body(0,  int_i+3000);
                    int_i = int_i + 1;
                    int_n = int_n + 1;
                end
            end
            else begin
                make_SiliconNet_end(0);
            end
        end
        else if ((counter_sa > 300) && (int_q < 8)) begin  //
            // show message
            if (displayflag5) begin
                $display("//////////test data batch 05//////////");
                displayflag5 <= 0;
                sub_test     <= SUB5;
            end
            // show message end
            if (sa_ready_out[0]) begin
                if (int_p==0) begin
                    make_SiliconNet_first(0,  REQ_FWRD, 103, int_p_length*32,  0,  0, counter);                 
                    int_p = int_p + 1;                    
                end
                else if (int_p==(int_p_length-1)) begin
                    make_SiliconNet_last(0,  int_i+2000);
                    int_i = int_i + 1;
                    int_p = 0;
                    int_q = int_q + 1;
                end
                else begin
                    make_SiliconNet_body(0,  int_i+2000);
                    int_i = int_i + 1;
                    int_p = int_p + 1;
                end
            end
            else begin
                make_SiliconNet_end(0);
            end
        end
        // long message
        else if ((counter_sa > 400) && (int_s < 16)) begin  //
            // show message
            if (displayflag6) begin
                $display("//////////test data batch 06//////////");
                displayflag6 <= 0;
                sub_test     <= SUB6;
            end
            // show message end
            if (sa_ready_out[0]) begin
                if (int_r==0) begin
                    //make_SiliconNet_first(0,  REQ_FWRD, 100+int_s, int_r_length*32,  0,  0);                 
                    make_SiliconNet_first(0,  REQ_FWRD, 1, int_r_length*32,  0,  10+int_s, counter);//serverIP matched, should adopt low table
                    int_r = int_r + 1;                    
                end
                else if (int_r==(int_r_length-1)) begin
                    make_SiliconNet_last(0,  int_r);
                    int_i = int_i + 1;
                    int_r = 0;
                    int_s = int_s + 1;
                end
                else begin
                    make_SiliconNet_body(0,  int_r);
                    int_i = int_i + 1;
                    int_r = int_r + 1;
                end
            end
            else begin
                make_SiliconNet_end(0);
            end
        end
        else begin
            make_SiliconNet_end(0);
        end
    end*/

    ///////
    // N-1 congestion test, and u-turn (Port#4-Port#4) and table-look-up miss (Port#1-Port#4)
/*    generate
        for (gen_i = 0; gen_i < NUM_PORTS; gen_i++) begin
            always @ (posedge sa_clk[gen_i]) begin
                if ((counter_sa > 1500) && (int_u[gen_i] < 400)) begin  //
                    // show message
                    if (displayflag7) begin
                        $display("//////////test data batch 07//////////");
                        displayflag7 <= 0;
                        sub_test     <= SUB7;
                    end
                    // show message end
                    if (sa_ready_out[gen_i]) begin
                        if (int_t[gen_i]==0) begin
                            if (gen_i < 4) begin // FT lookup miss
                                make_SiliconNet_first(gen_i,  REQ_CNFG, 103, int_t_length*32,  gen_i,  0, counter);//the last minus 1
                            end
                            else begin
                                make_SiliconNet_first(gen_i,  REQ_CNFG, 107, int_t_length*32,  gen_i,  0, counter);//the last minus 1
                            end
                            int_t[gen_i] = int_t[gen_i] + 1;                    
                        end
                        else if (int_t[gen_i]==(int_t_length-1)) begin
                            make_SiliconNet_last(gen_i,  gen_i*65536*65536 + int_u[gen_i]*65536+ int_t[gen_i]);
                            int_i = int_i + 1;
                            int_t[gen_i] = 0;
                            int_u[gen_i] = int_u[gen_i] + 1;
                        end
                        else begin
                            make_SiliconNet_body(gen_i,  gen_i*65536*65536 + int_u[gen_i]*65536+ int_t[gen_i]);
                            int_i = int_i + 1;
                            int_t[gen_i] = int_t[gen_i] + 1;
                        end
                    end
                    else begin
                        make_SiliconNet_end(gen_i);
                    end
                end
                else begin
                    make_SiliconNet_end(gen_i);
                end
            end
        end
    endgenerate*/

    ///////
    // N-N congestion test, tester can control whether to generate u-turn msg
    generate        
        for (gen_i = 0; gen_i < NUM_PORTS; gen_i++) begin
            always @ (posedge sa_clk[gen_i]) begin
                if ((counter_sa > 5000) && (int_w[gen_i] < 50)) begin  //
                    // show message
                    if (displayflag8) begin
                        $display("//////////test data batch 08//////////");
                        displayflag8 <= 0;
                        sub_test     <= SUB8;
                    end
                    // show message end
                    if (sa_ready_out[gen_i]) begin
                        if (int_v[gen_i]==0) begin
                            int_rand[gen_i] = $urandom%NUM_PORTS;
                            // u-turn control, comment these lines will generate u-turn msg
                            if (int_rand[gen_i] == (NUM_PORTS-1-gen_i)) begin
                                int_rand[gen_i] = gen_i;
                            end
                            //
                            make_SiliconNet_first(gen_i,  REQ_SEND, 100+int_rand[gen_i], int_v_length*32,  gen_i,  0, counter);                 
                            int_i = int_i + 1;
                            int_v[gen_i] = int_v[gen_i] + 1;                    
                        end
                        //else if (int_v[gen_i]==(int_v_length-1)) begin
                        else if (int_v[gen_i]==((int_v_length/(gen_i+1))-1)) begin
                            make_SiliconNet_last(gen_i,  gen_i*65536*65536 + int_w[gen_i]*65536+ int_v[gen_i]);
                            int_i = int_i + 1;
                            int_v[gen_i] = 0;
                            int_w[gen_i] = int_w[gen_i] + 1;
                        end
                        else begin
                            make_SiliconNet_body(gen_i,  gen_i*65536*65536 + int_w[gen_i]*65536+ int_v[gen_i]);
                            int_i = int_i + 1;
                            int_v[gen_i] = int_v[gen_i] + 1;
                        end
                    end
                    else begin
                        make_SiliconNet_end(gen_i);
                    end
                end
                else begin
                    make_SiliconNet_end(gen_i);
                end
            end
        end
    endgenerate
 
    //////////////////////////////////////////////////////////////////////////////////////
    //result checking
    //////////////////////////////////////////////////////////////////////////////////////   

    //////
    // check how many msgs are sent into port#0
    reg     [15:0]  counter_valid_sum;
    reg     [15:0]  counter_last_sum;
    reg     [15:0]  counter_valid   [NUM_PORTS-1:0];
    reg     [15:0]  counter_last    [NUM_PORTS-1:0];
    generate
        for (gen_i = 0; gen_i < NUM_PORTS; gen_i++) begin
            always @ (posedge sa_clk[0]) begin
                if (sa_rst[gen_i]) begin
                    counter_valid[gen_i]   <= 0;
                end
                else begin
                    if (sa_valid_in[gen_i] == 1) begin
                        counter_valid[gen_i]   <= counter_valid[gen_i] + 1;
                    end
                end
            end
            always @ (posedge sa_clk[gen_i]) begin
                if (sa_rst[gen_i]) begin
                    counter_last[gen_i]   <= 0;
                end
                else begin
                    if (sa_last_in[gen_i] == 1) begin
                        counter_last[gen_i] <= counter_last[gen_i] + 1;
                    end
                end
            end
        end
    endgenerate
    generate
        if (NUM_PORTS==4) begin
            assign counter_valid_sum    = counter_valid[0] 
                                        + counter_valid[1] 
                                        + counter_valid[2] 
                                        + counter_valid[3];
            assign counter_last_sum     = counter_last[0] 
                                        + counter_last[1] 
                                        + counter_last[2] 
                                        + counter_last[3];
        end
        else if (NUM_PORTS==8) begin
            assign counter_valid_sum    = counter_valid[0] 
                                        + counter_valid[1] 
                                        + counter_valid[2] 
                                        + counter_valid[3]
                                        + counter_valid[4]
                                        + counter_valid[5]
                                        + counter_valid[6]
                                        + counter_valid[7];
            assign counter_last_sum     = counter_last[0] 
                                        + counter_last[1] 
                                        + counter_last[2] 
                                        + counter_last[3]
                                        + counter_last[4]
                                        + counter_last[5]
                                        + counter_last[6]
                                        + counter_last[7];
        end
    endgenerate
    
    // check how many msgs are received through port#0-3
    reg     [15:0]  counter_valid_e_sum;
    reg     [15:0]  counter_last_e_sum;
    reg     [15:0]  counter_valid_e   [NUM_PORTS-1:0];
    reg     [15:0]  counter_last_e    [NUM_PORTS-1:0];
    generate
        for (gen_i = 0; gen_i < NUM_PORTS; gen_i++) begin
            always @ (posedge sa_clk[gen_i]) begin
                if (sa_rst[gen_i]) begin
                    counter_valid_e[gen_i]   <= 0;
                end
                else begin
                    if (sa_valid_out[gen_i] == 1) begin
                        counter_valid_e[gen_i]   <= counter_valid_e[gen_i] + 1;
                    end
                end
            end
            always @ (posedge sa_clk[gen_i]) begin
                if (sa_rst[gen_i]) begin
                    counter_last_e[gen_i]   <= 0;
                end
                else begin
                    if (sa_last_out[gen_i] == 1) begin
                        counter_last_e[gen_i] <= counter_last_e[gen_i] + 1;
                    end
                end
            end            
        end
    endgenerate
    generate
        if (NUM_PORTS==4) begin
            assign counter_valid_e_sum  = counter_valid_e[0] 
                                        + counter_valid_e[1] 
                                        + counter_valid_e[2] 
                                        + counter_valid_e[3];
            assign counter_last_e_sum   = counter_last_e[0] 
                                        + counter_last_e[1] 
                                        + counter_last_e[2] 
                                        + counter_last_e[3];
        end
        else if (NUM_PORTS==8) begin
            assign counter_valid_e_sum  = counter_valid_e[0] 
                                        + counter_valid_e[1] 
                                        + counter_valid_e[2] 
                                        + counter_valid_e[3]
                                        + counter_valid_e[4]
                                        + counter_valid_e[5]
                                        + counter_valid_e[6]
                                        + counter_valid_e[7];
            assign counter_last_e_sum   = counter_last_e[0] 
                                        + counter_last_e[1] 
                                        + counter_last_e[2] 
                                        + counter_last_e[3]
                                        + counter_last_e[4]
                                        + counter_last_e[5]
                                        + counter_last_e[6]
                                        + counter_last_e[7];
        end
    endgenerate
    
    // check received msg header    
    SiliconNetHead sa_head_receive     [NUM_PORTS-1:0];
    generate
        for (gen_i = 0; gen_i < NUM_PORTS; gen_i++) begin
            assign sa_head_receive[gen_i] = sa_first_out[gen_i] ? sa_data_out[gen_i] : {$bits(SiliconNetHead){1'bx}};
        end
    endgenerate

    // check received msg data
    SiliconData256 sa_data_receive     [NUM_PORTS-1:0];
    generate
        for (gen_i = 0; gen_i < NUM_PORTS; gen_i++) begin
            assign sa_data_receive[gen_i] = sa_valid_out[gen_i] ? (sa_first_out[gen_i] ? {{($bits(sa_data_out[gen_i])-1){1'bz}},1'b0} : sa_data_out[gen_i]) : {($bits(sa_data_out[gen_i])){1'bx}};
        end
    endgenerate

    //////////////////////////////////////////////////////////////////////////////////////
    //rx receive or not?
    //////////////////////////////////////////////////////////////////////////////////////
    // rx Stack/Application set to receive

    generate 
        for (gen_i = 0; gen_i < NUM_PORTS; gen_i++) begin
            always @ (posedge sa_clk[gen_i]) begin
                if (sa_rst[gen_i]) begin
                    sa_ready_in[gen_i] <= 0;
                end
                else begin
                    sa_ready_in[gen_i] <= 1;
                end
            end
        end
    endgenerate
    /*
    generate 
        for (gen_i = 0; gen_i < 4; gen_i++) begin
            always @ (posedge sa_clk[gen_i]) begin
                if (sa_rst[gen_i]) begin
                    sa_ready_in[gen_i] <= 0;
                end
                else if ((counter_sa > 50)&(counter_sa < 4999)) begin
                    sa_ready_in[gen_i] <= 1;
                end
                else if ((counter_sa > 4999)&(counter_sa < 10500)) begin
                    sa_ready_in[gen_i] <= 0;
                end
                else if (counter_sa > 10500) begin
                    sa_ready_in[gen_i] <= 1;
                end
            end
        end
    endgenerate
    generate 
        for (gen_i = 4; gen_i < NUM_PORTS; gen_i++) begin        
            always @ (posedge sa_clk[gen_i]) begin
                if (sa_rst[gen_i]) begin
                    sa_ready_in[gen_i] <= 0;
                end
                else if ((counter_sa > 50)&(counter_sa < 4999)) begin
                    sa_ready_in[gen_i] <= 1;
                end
                else if ((counter_sa > 4999)&(counter_sa < 8500)) begin
                    sa_ready_in[gen_i] <= 0;
                end
                else if (counter_sa > 8500) begin
                    sa_ready_in[gen_i] <= 1;
                end
            end
        end
    endgenerate
    */


endmodule