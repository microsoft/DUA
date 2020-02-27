///////////////////////////////////////////////////////////////
//
// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.
//
////////////////////////////////////////////////////////////////

import SiliconNetTypes::*;
import NetworkTypes::IP4Address;

module Connector
#(
    parameter                   DATA_WIDTH,
    parameter                   UID_WIDTH,
    parameter                   LENGTH_WIDTH,
    parameter                   FLAG_WIDTH,
    parameter                   SEQNUM_WIDTH,
    parameter                   TYPE_WIDTH,    
    parameter                   PARAM_WIDTH,
    parameter                   NUM_PORTS,
    parameter                   MAX_MSG_LENGTH,
    parameter                   THIS_ID_PORT,
    parameter                   THIS_ID_VC,
    // ForwardingTable related
    parameter                   NUM_TABLES = 2,
    parameter                   NUM_KEYS_HIGH,
    parameter                   NUM_KEYS_LOW,
    parameter                   WIDTH_HIGH,
    parameter                   WIDTH_LOW
)
(
    input                                                 clk,
    input                                                 rst,

    ///////////////
    // DATA PATH //
    ///////////////
    // Stack/App side
    input                                                 sa_clk,
    input                                                 sa_rst,

    // Full Switch Side - (RX: ShimInterface -> Connector) 
    input  SwitchInterface                                fs_ifc_in,
    input  wire                                           fs_wren_in,
    output reg                                            fs_full_out,

    // Full Switch Side - (TX: Connctor -> ShimInterface) 
    output SwitchInterface                                fs_ifc_out,
    output reg                                            fs_wren_out,
    input  wire             [NUM_PORTS-1:0]               fs_full_in,

    // Stack/App Side - (RX: Connector -> Stack/App)
    output reg              [DATA_WIDTH-1:0]              sa_data_out,
    output reg                                            sa_valid_out,
    output reg                                            sa_first_out,
    output reg                                            sa_last_out,
    input                                                 sa_ready_in,

    // Stack/App Side - (TX: Stack/App -> Connector)
    input                   [DATA_WIDTH-1:0]              sa_data_in,
    input                                                 sa_valid_in,
    input                                                 sa_first_in,
    input                                                 sa_last_in,
    output                                                sa_ready_out,

    //////////////////
    // CONTROL PATH //
    //////////////////
    // Address high field configure
    input                                                 high_cfg_in,
    input                   [$clog2(NUM_KEYS_HIGH):0]     high_cfg_index_in,  // index [NUM_KEYS] is used for set and load the default endpoint
    input                                                 high_cfg_valid_in,
    input                   [WIDTH_HIGH-1:0]              high_cfg_key_in,
    input                   [WIDTH_HIGH-1:0]              high_cfg_msk_in,
    input                   [$clog2(NUM_PORTS)-1:0]       high_cfg_endpoint_in,
    //
    input                                                 high_cfg_read_in,
    output reg                                            high_cfg_read_valid_out,
    output reg                                            high_cfg_valid_out,
    output reg              [WIDTH_HIGH-1:0]              high_cfg_key_out,
    output reg              [WIDTH_HIGH-1:0]              high_cfg_msk_out,
    output reg              [$clog2(NUM_PORTS)-1:0]       high_cfg_endpoint_out,

    // Address low field onfigure
    input                                                 low_cfg_in,    
    input                   [$clog2(NUM_KEYS_LOW):0]      low_cfg_index_in,   // index [NUM_KEYS] is used for set and load the default endpoint
    input                                                 low_cfg_valid_in,
    input                   [WIDTH_LOW-1:0]               low_cfg_key_in,
    input                   [WIDTH_LOW-1:0]               low_cfg_msk_in,
    input                   [$clog2(NUM_PORTS)-1:0]       low_cfg_endpoint_in,
    //
    input                                                 low_cfg_read_in,
    output reg                                            low_cfg_read_valid_out,
    output reg                                            low_cfg_valid_out,
    output reg              [WIDTH_LOW-1:0]               low_cfg_key_out,
    output reg              [WIDTH_LOW-1:0]               low_cfg_msk_out,
    output reg              [$clog2(NUM_PORTS)-1:0]       low_cfg_endpoint_out,

    // counter related
    input                                                 counter_read_in,
    input                   [2:0]                         counter_index_in,
    output reg                                            counter_value_valid_out,
    output reg              [63:0]                        counter_value_out
);

    localparam PHITS_PER_FLIT     = SN_FLIT_WIDTH / SN_PHIT_WIDTH;

    /////////////////////////////////////////////////////////////////////////////////////////////
    // Connector configuration
    /////////////////////////////////////////////////////////////////////////////////////////////
    reg                     [SN_PORT_WIDTH-1:0]           this_id_port;
    reg                     [SN_VC_WIDTH-1:0]             this_id_vc;
    assign this_id_port = (!rst) ? THIS_ID_PORT : {SN_PORT_WIDTH{1'b0}};
    assign this_id_vc   = (!rst) ? THIS_ID_VC   : {SN_VC_WIDTH{1'b0}};

    /////////////////////////////////////////////////////////////////////////////////////////////
    // SiliconNet as master TX (Stack/App -> Connector -> ShimInterface)
    /////////////////////////////////////////////////////////////////////////////////////////////

    // CrossBuff write
    wire [$clog2(MAX_MSG_LENGTH):0]  tx_sa_write_used;
    wire                             tx_sa_write_full;

    // CrossBuff read
    wire                             tx_cross_buff_empty;
    reg                              tx_cross_buff_read;
    reg                              tx_cross_buff_read_tmp;
    reg                              tx_cross_buff_read_tmp2;
    reg                              tx_cross_buff_read_tmp3;
    wire [DATA_WIDTH-1:0]            tx_cross_buff_data;
    wire                             tx_cross_buff_valid;
    wire                             tx_cross_buff_first;
    wire                             tx_cross_buff_last;
    reg  [DATA_WIDTH-1:0]            msg_data;
    reg                              msg_valid;
    reg                              msg_first;
    reg                              msg_last;
    
    UID                              msg_src_uid;
    UID                              msg_dst_uid;
    SN_MSG_LENGTH                    msg_length;
    SN_MSG_FLAG                      msg_flag;
    SN_MSG_SEQNUM                    msg_seqnum;
    SN_REQ_TYPE                      req_type;
    SN_REQ_PARAM                     req_param;

    UID                              tmp_src_uid;
    UID                              tmp_dst_uid;
    SN_MSG_LENGTH                    tmp_length;
    SN_MSG_FLAG                      tmp_flag;
    SN_MSG_SEQNUM                    tmp_seqnum;
    SN_REQ_TYPE                      tmp_type;
    SN_REQ_PARAM                     tmp_param;

    SiliconNetHead tx_msg_head;

    // CrossBuff
    AsyncFIFO
    #(
        .LOG_DEPTH      ($clog2(MAX_MSG_LENGTH)),      
        .WIDTH          (DATA_WIDTH + 3),
        .USE_LUTRAM     (1'b1)
    )
    TX_CrossBuff
    (
        .aclr           (sa_rst),

        .wrclk          (sa_clk),
        .wrreq          (sa_valid_in),
        .wrempty        (),
        .wrfull         (tx_sa_write_full),
        .wrusedw        (tx_sa_write_used),
        .data           ({sa_valid_in, sa_first_in, sa_last_in, sa_data_in}),

        .rdclk          (clk),
        .rdempty        (tx_cross_buff_empty),
        .rdfull         (),
        .rdusedw        (),
        .rdreq          (tx_cross_buff_read),
        .q              ({tx_cross_buff_valid, tx_cross_buff_first, tx_cross_buff_last, tx_cross_buff_data}),

        .dbg_overflow   (),
        .dbg_underflow  ()
    );

    // Generate Stack/Application side ready
    assign sa_ready_out = ((tx_sa_write_used<MAX_MSG_LENGTH-2) ? 1 : 0) & (!tx_sa_write_full);

    // Generate CrossBuff read request
    always @ (posedge clk) begin
        if(rst) begin
            tx_cross_buff_read_tmp     <= 0;
        end
        else begin
            tx_cross_buff_read_tmp     <=~tx_cross_buff_empty;
        end
    end    
    assign tx_cross_buff_read = (~tx_cross_buff_empty)&tx_cross_buff_read_tmp&tx_cross_buff_read_tmp2&tx_cross_buff_read_tmp3;

    // pre store SiliconNet Head
    assign tx_msg_head = rst ? {DATA_WIDTH{1'bx}} : ((tx_cross_buff_read && tx_cross_buff_first) ? tx_cross_buff_data : {DATA_WIDTH{1'bx}});

    // Read CrossBuff and do the step 1 of fragmentation: dividing into different data fields
    always @ (posedge clk) begin
        if(rst) begin
            msg_data                <= {DATA_WIDTH{1'bx}};
            msg_valid               <= 1'b0;
            msg_first               <= 1'b0;
            msg_last                <= 1'b0;
            
            msg_src_uid             <= {UID_WIDTH{1'bx}};
            msg_dst_uid             <= {UID_WIDTH{1'bx}};
            msg_length              <= {LENGTH_WIDTH{1'bx}};
            msg_flag                <= {FLAG_WIDTH{1'bx}};
            msg_seqnum              <= {SEQNUM_WIDTH{1'bx}};
            req_type                <= REQ_IDLE;
            req_param               <= {PARAM_WIDTH{1'bx}};
        end
        else if (tx_cross_buff_read) begin
            //msg_data                <= tx_cross_buff_data;
            msg_valid               <= tx_cross_buff_valid;
            msg_first               <= tx_cross_buff_first;
            msg_last                <= tx_cross_buff_last;
            if (tx_cross_buff_first) begin
                msg_data                <= {DATA_WIDTH{1'bx}};
                
                msg_src_uid             <= tx_msg_head.src_uid;
                msg_dst_uid             <= tx_msg_head.dst_uid;
                msg_length              <= tx_msg_head.msg_length;
                msg_flag                <= tx_msg_head.msg_flag;
                msg_seqnum              <= tx_msg_head.msg_seqnum;
                req_type                <= tx_msg_head.req_type;
                req_param               <= tx_msg_head.req_param;
                
                tmp_src_uid             <= tx_msg_head.src_uid;
                tmp_dst_uid             <= tx_msg_head.dst_uid;
                tmp_length              <= tx_msg_head.msg_length;
                tmp_flag                <= tx_msg_head.msg_flag;
                tmp_seqnum              <= tx_msg_head.msg_seqnum;
                tmp_type                <= tx_msg_head.req_type;
                tmp_param               <= tx_msg_head.req_param;
            end
            else begin
                msg_data                <= tx_cross_buff_data;                
                msg_src_uid             <= tmp_src_uid;
                msg_dst_uid             <= tmp_dst_uid;
                msg_length              <= tmp_length;
                msg_flag                <= tmp_flag;
                msg_seqnum              <= tmp_seqnum;
                req_type                <= tmp_type;
                req_param               <= tmp_param;
            end
        end
        else begin
            msg_data                <= {DATA_WIDTH{1'bx}};
            msg_valid               <= 1'b0;
            msg_first               <= 1'b0;
            msg_last                <= 1'b0;
            
            msg_src_uid             <= {UID_WIDTH{1'bx}};
            msg_dst_uid             <= {UID_WIDTH{1'bx}};
            msg_length              <= {LENGTH_WIDTH{1'bx}};
            msg_flag                <= {FLAG_WIDTH{1'bx}};
            msg_seqnum              <= {SEQNUM_WIDTH{1'bx}};

            req_type                <= REQ_IDLE;
            req_param               <= {PARAM_WIDTH{1'bx}};
        end
    end

    // Packet generation FSM
    SwitchInterface                  fs_ifc_tmp1;
    reg                              fs_wren_tmp1;

    typedef enum logic [2:0]
    {
        sIdle       = 3'd0,     // idle state
        sFrst       = 3'd1,     // mseeage first state
        sData       = 3'd2,     // message middle (last) state
        sEmpt       = 3'd3,     // packet padding state
        sFrLs       = 3'd4      // message first&last state
    } MsgFragmentationState;

    struct packed
    {
        MsgFragmentationState                    fsm;
        logic       [$clog2(PHITS_PER_FLIT):0]   rem_phits;     // store how many phits are remaining inside a packet
        logic       [LENGTH_WIDTH-1:0]           rem_length;
    } sainput_state_nxt, sainput_state_ff;

    // phit count decrease task
    task PhitDecrease;
        sainput_state_nxt.rem_phits = sainput_state_nxt.rem_phits - 1;
    endtask

    // phit count increase task
    task PhitReset;
        sainput_state_nxt.rem_phits = PHITS_PER_FLIT;
    endtask

    // pack header phit (the first phit of one packet) function
    function SiliconNetHead PackHeadPhit;        
        input UID               msg_src_uid;
        input UID               msg_dst_uid;
        input SN_MSG_LENGTH     msg_length;
        input SN_MSG_FLAG       msg_flag;
        input SN_MSG_SEQNUM     msg_seqnum;
        input SN_REQ_TYPE       req_type;
        input SN_REQ_PARAM      req_param;
        PackHeadPhit            = {DATA_WIDTH{1'b0}};        
        PackHeadPhit.src_uid    = msg_src_uid;
        PackHeadPhit.dst_uid    = msg_dst_uid;
        PackHeadPhit.msg_length = msg_length;
        PackHeadPhit.msg_flag   = msg_flag;
        PackHeadPhit.msg_seqnum = msg_seqnum;
        PackHeadPhit.req_type   = req_type;
        PackHeadPhit.req_param  = req_param;
    endfunction    
    
    // state machine runs...
    always @ (*) begin
        sainput_state_nxt        = sainput_state_ff;
        tx_cross_buff_read_tmp2  = 1;
        fs_wren_tmp1             = 0;
        fs_ifc_tmp1              = {$bits(fs_ifc_tmp1){1'b0}};
        fs_ifc_tmp1.data         = {$bits(fs_ifc_tmp1.data){1'bx}};
        //fs_ifc_tmp1.src_vc       = {$bits(fs_ifc_tmp1.src_vc){1'bx}};
        //fs_ifc_tmp1.src_port     = {$bits(fs_ifc_tmp1.src_port){1'bx}};
        //fs_ifc_tmp1.dst_vc       = {$bits(fs_ifc_tmp1.dst_vc){1'bx}};
        //fs_ifc_tmp1.dst_port     = {$bits(fs_ifc_tmp1.dst_port){1'bx}};
        //fs_ifc_tmp1.pad_bytes    = {$bits(fs_ifc_tmp1.pad_bytes){1'bx}};

        case(sainput_state_ff.fsm)
            // sIdle: before any available msg arrives
            sIdle: begin
                if (msg_valid && msg_first) begin
                    fs_ifc_tmp1.first           = 1;
                    fs_ifc_tmp1.msg_first       = msg_first;
                    fs_ifc_tmp1.data            = PackHeadPhit(msg_src_uid,msg_dst_uid,msg_length,msg_flag,msg_seqnum,req_type,req_param);
                    fs_wren_tmp1                = 1;
                    PhitDecrease;                    
                    if (msg_last) begin
                        sainput_state_nxt.fsm        = sFrLs;
                        tx_cross_buff_read_tmp2      = 0;                                            
                        fs_ifc_tmp1.pad_bytes        = msg_length - 1;
                        fs_ifc_tmp1.msg_last         = msg_last;
                        sainput_state_nxt.rem_length = 0;
                    end
                    else if (~msg_last) begin
                        sainput_state_nxt.fsm        = sFrst;
                        fs_ifc_tmp1.pad_bytes        = 32-1;
                        sainput_state_nxt.rem_length = msg_length-32;                        
                    end
                end
            end

            // sFrst: the first of a message
            sFrst: begin
                if (msg_valid) begin
                    PhitDecrease;
                    fs_ifc_tmp1.data            = msg_data;
                    fs_wren_tmp1                = 1;
                    if (msg_last) begin
                        sainput_state_nxt.fsm        = sEmpt;
                        fs_ifc_tmp1.pad_bytes        = sainput_state_ff.rem_length - 1;
                        sainput_state_nxt.rem_length = 0;
                        fs_ifc_tmp1.msg_last         = msg_last;
                        if (sainput_state_ff.rem_phits != 1) begin
                            tx_cross_buff_read_tmp2     = 0;
                        end
                    end
                    else if (~msg_last) begin
                        sainput_state_nxt.fsm        = sData;
                        fs_ifc_tmp1.pad_bytes        = 32-1;
                        sainput_state_nxt.rem_length = sainput_state_ff.rem_length-32;
                    end
                end
            end

            // sData: after the first and before the last of the message
            sData: begin
                if (msg_valid) begin
                    fs_ifc_tmp1.data            = msg_data;
                    fs_wren_tmp1                = 1;
                    if (msg_last) begin // met the msg last
                        if (sainput_state_ff.rem_phits == 1) begin // the msg last is exactly the last phit
                            sainput_state_nxt.fsm       = sIdle;
                            PhitReset;
                            fs_ifc_tmp1.last            = 1;
                            fs_ifc_tmp1.msg_last        = msg_last;
                        end
                        else if (sainput_state_ff.rem_phits != 1) begin // the msg last is not the last phit
                            sainput_state_nxt.fsm       = sEmpt;
                            PhitDecrease;
                            tx_cross_buff_read_tmp2     = 0;
                            fs_ifc_tmp1.msg_last        = msg_last;
                            if (sainput_state_ff.rem_phits == PHITS_PER_FLIT) begin
                                fs_ifc_tmp1.first           = 1;
                            end
                        end
                        fs_ifc_tmp1.pad_bytes        = sainput_state_ff.rem_length - 1;
                        sainput_state_nxt.rem_length = 0;
                    end
                    else if (~msg_last) begin // not the msg last
                        if (sainput_state_ff.rem_phits == PHITS_PER_FLIT) begin // meet the max phit_per_flit, initial another flit within msg
                            sainput_state_nxt.fsm       = sFrst;
                            PhitDecrease;
                            fs_ifc_tmp1.first           = 1;                            
                        end
                        else if (sainput_state_ff.rem_phits == 1) begin // meet the last phit, generate a last indicator
                            PhitReset;
                            fs_ifc_tmp1.last            = 1;
                        end
                        else begin // within a msg
                            PhitDecrease;
                        end
                        fs_ifc_tmp1.pad_bytes        = 32-1;
                        sainput_state_nxt.rem_length = sainput_state_ff.rem_length-32;
                    end
                end
            end

            // sEmpt: padding empty phits to meet the requirement of PHITS_PER_FLIT setting
            sEmpt: begin
                fs_wren_tmp1                = 1;
                fs_ifc_tmp1.data            = {1'bx,32'hee};
                //fs_ifc_tmp1.data            = {DATA_WIDTH{1'bx}};
                fs_ifc_tmp1.pad_bytes       = 0;
                if (sainput_state_ff.rem_phits == 1) begin
                    sainput_state_nxt.fsm       = sIdle;
                    PhitReset;
                    fs_ifc_tmp1.last            = 1;                    
                end
                else begin
                    PhitDecrease;
                    tx_cross_buff_read_tmp2     = 0;
                end
            end

            // sFrst: the first&last (message length = 1)
            sFrLs: begin
                sainput_state_nxt.fsm       = sEmpt;
                PhitDecrease;
                tx_cross_buff_read_tmp2     = 0;
                fs_wren_tmp1                = 1;
                fs_ifc_tmp1.data            = {1'bx,32'hee};
                //fs_ifc_tmp1.data            = {DATA_WIDTH{1'bx}};
                fs_ifc_tmp1.pad_bytes       = 0;
            end

            default: begin
                sainput_state_nxt.fsm       = sIdle;
                PhitReset;
            end

        endcase
    end

    always @ (posedge clk) begin
        if(rst) begin
            sainput_state_ff         <= {sIdle, PHITS_PER_FLIT, {LENGTH_WIDTH{1'b0}}};
        end
        else begin
            sainput_state_ff         <= sainput_state_nxt;
        end
    end

    // Shif several clocks, to wait for the ForwardingTable lookup result
    SwitchInterface                  fs_ifc_tmp2;
    reg                              fs_wren_tmp2;
    shift_reg
    #(
        .WIDTH       ($bits(fs_ifc_tmp1)+1),
        .DELAY       (PHITS_PER_FLIT)
    )
    ShifReg_ins
    (
        .CLK         (clk),
        .in          ({fs_ifc_tmp1,fs_wren_tmp1}),
        .out         ({fs_ifc_tmp2,fs_wren_tmp2})
    );

    // Lookup forwarding table
    wire                            endpoint_valid_out;
    wire  [$clog2(NUM_PORTS)-1:0]   endpoint_out;
    reg   [$clog2(NUM_PORTS)-1:0]   endpoint_out_tmp;
    wire                            endpoint_missed_out;
    reg                             endpoint_missed_out_tmp;
    ForwardingTableDual
    #(
        .NUM_KEYS_HIGH          (NUM_KEYS_HIGH),
        .NUM_KEYS_LOW           (NUM_KEYS_LOW),
        .NUM_PORTS              (NUM_PORTS),
        .WIDTH_HIGH             (WIDTH_HIGH),
        .WIDTH_LOW              (WIDTH_LOW)
    )
    ForwardingTableDual_ins
    (
        .clk                    (clk),
        .rst                    (rst),

        .dst_UID_valid_in       (msg_valid),
        .dst_UID_check_in       (msg_dst_uid),

        .high_cfg_in            (high_cfg_in),        
        .high_cfg_index_in      (high_cfg_index_in),
        .high_cfg_valid_in      (high_cfg_valid_in),
        .high_cfg_key_in        (high_cfg_key_in),
        .high_cfg_msk_in        (high_cfg_msk_in),
        .high_cfg_endpoint_in   (high_cfg_endpoint_in),

        .high_cfg_read_in       (high_cfg_read_in),
        .high_cfg_read_valid_out(high_cfg_read_valid_out),
        .high_cfg_valid_out     (high_cfg_valid_out),
        .high_cfg_key_out       (high_cfg_key_out),
        .high_cfg_msk_out       (high_cfg_msk_out),
        .high_cfg_endpoint_out  (high_cfg_endpoint_out),

        .low_cfg_in             (low_cfg_in),        
        .low_cfg_index_in       (low_cfg_index_in),
        .low_cfg_valid_in       (low_cfg_valid_in),
        .low_cfg_key_in         (low_cfg_key_in),
        .low_cfg_msk_in         (low_cfg_msk_in),
        .low_cfg_endpoint_in    (low_cfg_endpoint_in),

        .low_cfg_read_in        (low_cfg_read_in),
        .low_cfg_read_valid_out (low_cfg_read_valid_out),
        .low_cfg_valid_out      (low_cfg_valid_out),
        .low_cfg_key_out        (low_cfg_key_out),
        .low_cfg_msk_out        (low_cfg_msk_out),
        .low_cfg_endpoint_out   (low_cfg_endpoint_out),

        .endpoint_valid_out     (endpoint_valid_out),
        .endpoint_out           (endpoint_out),
        .endpoint_missed_out    (endpoint_missed_out)
    );

    // FIFO for output
    // 1: extra phit
    // 2: buff depth
    localparam FIFO_DEPTH = PHITS_PER_FLIT * (2+1);
    reg [$clog2(FIFO_DEPTH):0]       tx_fifo_counter;
    SwitchInterface                  fs_ifc_tmp3;
    reg                              fs_wren_tmp3;
    wire                             tx_fifo_empty;
    wire                             tx_fifo_full;
    reg                              tx_fifo_read;
    reg                              tx_fifo_write; 
    wire                             tx_output_full;
    // fifo output prefetch
    SwitchInterface                  fs_ifc_pref;
    wire                             fs_wren_pref;

    // generate packets from CrossBuff & ForwardingTable's output, and then push in to the output buff
    assign fs_ifc_tmp3.src_vc     = this_id_vc;
    assign fs_ifc_tmp3.src_port   = this_id_port;
    assign fs_ifc_tmp3.dst_vc     = 0; // future: from forwarding table output
    assign fs_ifc_tmp3.dst_port   = (fs_ifc_tmp2.first)? endpoint_out : endpoint_out_tmp;
    assign fs_ifc_tmp3.data       = fs_ifc_tmp2.data;
    assign fs_ifc_tmp3.msg_first  = fs_ifc_tmp2.msg_first;
    assign fs_ifc_tmp3.msg_last   = fs_ifc_tmp2.msg_last;
    assign fs_ifc_tmp3.first      = fs_ifc_tmp2.first;
    assign fs_ifc_tmp3.last       = fs_ifc_tmp2.last;
    assign fs_ifc_tmp3.pad_bytes  = fs_ifc_tmp2.pad_bytes;
    assign fs_wren_tmp3           = rst ? 1'b0 : fs_wren_tmp2;

    // assign tx_fifo_write based on features, u-turn disable, table lookup failure msg drop 
    always @ (*) begin
        if (rst) begin
            tx_fifo_write   = 1'b0;
        end
        else if (fs_wren_tmp2) begin
            if (endpoint_valid_out) begin
                if ((endpoint_out==this_id_port)||endpoint_missed_out) begin
                    tx_fifo_write   = 1'b0;
                end
                else begin
                    tx_fifo_write   = fs_wren_tmp2;
                end
            end
            else begin
                if ((endpoint_out_tmp==this_id_port)||endpoint_missed_out_tmp) begin
                    tx_fifo_write   = 1'b0;
                end
                else begin
                    tx_fifo_write   = fs_wren_tmp2;
                end
            end
        end
        else begin
            tx_fifo_write   = 1'b0;
        end
    end
    
    always @ (posedge clk) begin
        if (rst) begin
            endpoint_out_tmp        <= {$bits(endpoint_out_tmp){1'b0}};
            endpoint_missed_out_tmp <= 1'b0;
        end
        else if (endpoint_valid_out) begin
            endpoint_out_tmp        <= endpoint_out;
            endpoint_missed_out_tmp <= endpoint_missed_out;
        end
    end

    // Output buff
    FIFOCounter
    #(
        .DATA_WIDTH                 ($bits(fs_ifc_tmp3)+1),
        .DEPTH                      (FIFO_DEPTH)
    )
    TX_Buffer_to_SiliconSwitch
    (
        .clk                        (clk),
        .rst                        (rst),
        .rd_req                     (tx_fifo_read),
        .wr_req                     (tx_fifo_write),
        .data_in                    ({fs_ifc_tmp3,fs_wren_tmp3}),
        .data_out                   ({fs_ifc_out,fs_wren_out}),
        .data_prefetch              ({fs_ifc_pref,fs_wren_pref}),
        .empty                      (tx_fifo_empty),
        .half_full                  (),
        .full                       (tx_fifo_full),
        .counter                    (tx_fifo_counter)
    );

    //4: to meet the forwarding table read delay (3 cycles)
    //PHITS_PER_FLIT: add one extra buff (depth=PHITS_PER_FLIT)
    assign tx_cross_buff_read_tmp3 = ((FIFO_DEPTH - tx_fifo_counter) < (4+PHITS_PER_FLIT)) ? 1'b0 : 1'b1;

    // generate fifo read stall based on SiliconSwitch's full_in signals
    assign tx_output_full  = fs_wren_pref ? fs_full_in[fs_ifc_pref.dst_port] : 1'b0;
    assign tx_fifo_read    = (~tx_fifo_empty) && (~tx_output_full);


    /////////////////////////////////////////////////////////////////////////////////////////////
    // SiliconNet as slave RX (ShimInterface -> Connector -> Stack/App)
    /////////////////////////////////////////////////////////////////////////////////////////////



    localparam RX_FIFO_DEPTH = PHITS_PER_FLIT * (4);
    // Input buff
    wire                               rx_fifo_full;
    wire                               rx_fifo_empty;
    wire                               rx_fifo_read;
    reg [$clog2(RX_FIFO_DEPTH):0]      rx_fifo_counter;
    SwitchInterface                    fs_ifc_tmp5;
    wire                               fs_wren_tmp5;
    SwitchInterface                    fs_ifc_tmp6;
    wire                               fs_wren_tmp6;

    // CrossBuff write    
    wire                             rx_sa_write_full;
    wire [$clog2(MAX_MSG_LENGTH):0]  rx_sa_write_used;
    wire                             rx_cross_buff_empty;
    wire                             rx_cross_buff_read;


    // Input buff
    FIFOCounter
    #(
        .DATA_WIDTH                 ($bits(fs_ifc_in)+1),
        .DEPTH                      (RX_FIFO_DEPTH)
    )
    RX_Buffer_from_SiliconSwitch
    (
        .clk                        (clk),
        .rst                        (rst),
        .rd_req                     (rx_fifo_read),
        .wr_req                     (fs_wren_in),
        .data_in                    ({fs_ifc_in,fs_wren_in}),
        .data_out                   ({fs_ifc_tmp6,fs_wren_tmp6}),
        .data_prefetch              ({fs_ifc_tmp5,fs_wren_tmp5}),
        .empty                      (rx_fifo_empty),
        .half_full                  (),
        .full                       (rx_fifo_full),
        .counter                    (rx_fifo_counter)
    );

    assign fs_full_out = (rx_fifo_counter > (RX_FIFO_DEPTH - 5))? 1'b1 : 1'b0;

    assign rx_fifo_read = (~rx_fifo_empty) & (rx_sa_write_used < (MAX_MSG_LENGTH-2));

    reg    [DATA_WIDTH-1:0]              sa_data_tmp1;
    reg                                  sa_valid_tmp1;
    reg                                  sa_first_tmp1;
    reg                                  sa_last_tmp1;
    wire   [DATA_WIDTH-1:0]              sa_data_tmp2;
    wire                                 sa_valid_tmp2;
    wire                                 sa_first_tmp2;
    wire                                 sa_last_tmp2;

    // for debugging only
    SiliconNetHead rx_debug_tmp;
    // for debugging only end

    typedef enum logic [2:0]
    {
        rIdle       = 3'd0,     // idle state
        rFrst       = 3'd1,     // mseeage first state
        rData       = 3'd2,     // message middle state
        rFrLs       = 3'd3      // message first&last state
    } MsgReassemblyState;

    struct packed
    {
        MsgReassemblyState                       fsm;
    } saoutput_state_nxt, saoutput_state_ff;

    always @ (*) begin
        saoutput_state_nxt        = saoutput_state_ff;
        sa_data_tmp1              = {DATA_WIDTH{1'bx}};
        sa_valid_tmp1             = 1'b0;
        sa_first_tmp1             = 1'b0;
        sa_last_tmp1              = 1'b0;
        case(saoutput_state_ff.fsm)
            // rIdle: 
            rIdle: begin
                if (fs_wren_tmp6 & fs_ifc_tmp6.msg_first & ~fs_ifc_tmp6.msg_last) begin
                    saoutput_state_nxt.fsm          = rFrst;
                    sa_data_tmp1                    = fs_ifc_tmp6.data;
                    sa_valid_tmp1                   = 1'b1;
                    sa_first_tmp1                   = 1'b1;
                    // for debugging only
                    rx_debug_tmp                    = fs_ifc_tmp6.data;
                    // for debugging only end
                end
                else if (fs_wren_tmp6 & fs_ifc_tmp6.msg_first & fs_ifc_tmp6.msg_last) begin
                    saoutput_state_nxt.fsm          = rFrLs;
                    sa_data_tmp1                    = fs_ifc_tmp6.data;
                    sa_valid_tmp1                   = 1'b1;
                    sa_first_tmp1                   = 1'b1;
                    sa_last_tmp1                    = 1'b1;
                    // for debugging only
                    rx_debug_tmp                    = fs_ifc_tmp6.data;
                    // for debugging only end
                end
                else if (fs_wren_tmp6) begin

                end
            end

            // rFrst: 
            rFrst: begin
                if (fs_wren_tmp6 & ~fs_ifc_tmp6.msg_last) begin
                    saoutput_state_nxt.fsm          = rData;
                    sa_data_tmp1                    = fs_ifc_tmp6.data;
                    sa_valid_tmp1                   = 1'b1;
                end
                else if (fs_wren_tmp6 & fs_ifc_tmp6.msg_last) begin
                    saoutput_state_nxt.fsm          = rIdle;
                    sa_data_tmp1                    = fs_ifc_tmp6.data;
                    sa_valid_tmp1                   = 1'b1;
                    sa_last_tmp1                    = 1'b1;
                end
            end

            // rData: 
            rData: begin
                if (fs_wren_tmp6 & ~fs_ifc_tmp6.msg_last) begin
                    saoutput_state_nxt.fsm          = rData;
                    sa_data_tmp1                    = fs_ifc_tmp6.data;
                    sa_valid_tmp1                   = 1'b1;
                end
                else if (fs_wren_tmp6 & fs_ifc_tmp6.msg_last) begin
                    saoutput_state_nxt.fsm          = rIdle;
                    sa_data_tmp1                    = fs_ifc_tmp6.data;
                    sa_valid_tmp1                   = 1'b1;
                    sa_last_tmp1                    = 1'b1;
                end
            end

            // rFrLs: 
            rFrLs: begin
                if (fs_wren_tmp6) begin
                    saoutput_state_nxt.fsm          = rIdle;
                end
            end

            // default:
            default: begin

            end
        endcase
    end

    always @ (posedge clk) begin
        if(rst) begin
            saoutput_state_ff         <= {rIdle};
        end
        else begin
            saoutput_state_ff         <= saoutput_state_nxt;
        end
    end

    // CrossBuff
    AsyncFIFO
    #(
        .LOG_DEPTH      ($clog2(MAX_MSG_LENGTH)),      
        .WIDTH          (DATA_WIDTH + 3),
        .USE_LUTRAM     (1'b1)
    )
    RX_CrossBuff
    (
        .aclr           (rst),

        .wrclk          (clk),
        .wrreq          (sa_valid_tmp1),
        .wrempty        (),
        .wrfull         (rx_sa_write_full),
        .wrusedw        (rx_sa_write_used),
        .data           ({sa_valid_tmp1,sa_data_tmp1,sa_first_tmp1,sa_last_tmp1}),

        .rdclk          (sa_clk),
        .rdempty        (rx_cross_buff_empty),
        .rdfull         (),
        .rdusedw        (),
        .rdreq          (rx_cross_buff_read),
        .q              ({sa_valid_tmp2,sa_data_tmp2,sa_first_tmp2,sa_last_tmp2}),

        .dbg_overflow   (),
        .dbg_underflow  ()
    );

    assign rx_cross_buff_read = (~rx_cross_buff_empty) & sa_ready_in;

    //assign {sa_valid_out,sa_data_out,sa_first_out,sa_last_out} = (~rx_cross_buff_read) ? {(DATA_WIDTH+1+1+1){1'b0}} : {sa_valid_tmp2,sa_data_tmp2,sa_first_tmp2,sa_last_tmp2};
    always @ (posedge sa_clk) begin
        if (sa_rst | ~rx_cross_buff_read) begin
            {sa_valid_out,sa_data_out,sa_first_out,sa_last_out} <= {(DATA_WIDTH+1+1+1){1'b0}};
        end
        else if (rx_cross_buff_read) begin
            {sa_valid_out,sa_data_out,sa_first_out,sa_last_out} <= {sa_valid_tmp2,sa_data_tmp2,sa_first_tmp2,sa_last_tmp2};
        end
    end

    ///////////////////////////////////////////////////////
    // for debugging
    ///////////////////////////////////////////////////////

    // tx pkt msg counter
    SiliconNetHead  tx_data_head;
    reg [63:0]      tx_byte_counter;
    reg [63:0]      tx_msg_counter;
    always @ (posedge clk) begin
        if (rst) begin
            tx_data_head   <= 256'b0;
        end
        else begin
            if (tx_cross_buff_read && tx_cross_buff_first) begin
                tx_data_head   <= tx_cross_buff_data;
            end
        end
    end
    
    // for timing
    always @ (posedge clk) begin
        if (rst) begin
            tx_msg_counter   <= 64'b0;
            tx_byte_counter  <= 64'b0;
        end
        else begin
            if (msg_last) begin
                tx_msg_counter   <= tx_msg_counter + 1'b1;
                tx_byte_counter  <= tx_byte_counter + msg_length; //32: head
            end
        end
    end

    // tx msg drop counter
    SiliconNetHead  tx_data_drop_head;
    reg [63:0]      tx_byte_drop_counter;
    reg [63:0]      tx_msg_drop_counter;
    always @ (posedge clk) begin
        if (rst) begin
            tx_data_drop_head   <= 256'b0;
        end
        else begin
            if ((~tx_fifo_write)&&(fs_ifc_tmp3.msg_first)) begin
                tx_data_drop_head   <= fs_ifc_tmp3.data;
            end
        end
    end
    always @ (posedge clk) begin
        if (rst) begin
            tx_msg_drop_counter   <= 64'b0;
            tx_byte_drop_counter  <= 64'b0;
        end
        else begin
            if ((~tx_fifo_write)&&(fs_ifc_tmp3.msg_last)) begin
                tx_msg_drop_counter   <= tx_msg_drop_counter + 1'b1;
                tx_byte_drop_counter  <= tx_byte_drop_counter + tx_data_drop_head.msg_length; //32: head
            end
        end
    end

    // rx pkt msg counter
    SiliconNetHead  rx_data_head;
    reg [63:0]      rx_byte_counter;
    reg [63:0]      rx_msg_counter;
    reg             sa_last_tmp1_delay;
    always @ (posedge clk) begin
        if (rst) begin
            rx_data_head   <= 256'b0;
        end
        else begin
            if (sa_first_tmp1) begin
                rx_data_head   <= sa_data_tmp1;
            end
        end
    end
    always @ (posedge clk) begin
        if (rst) begin
            sa_last_tmp1_delay   <= 1'b0;
        end
        else begin
            sa_last_tmp1_delay   <= sa_last_tmp1;
        end
    end
    always @ (posedge clk) begin
        if (rst) begin
            rx_msg_counter   <= 64'b0;
            rx_byte_counter  <= 64'b0;
        end
        else begin
            if (sa_last_tmp1_delay) begin
                rx_msg_counter   <= rx_msg_counter + 1'b1;
                rx_byte_counter  <= rx_byte_counter + rx_data_head.msg_length; //32: head
            end
        end
    end

    always @ (posedge clk) begin
        if (rst) begin
            counter_value_out       <= 64'h0;
            counter_value_valid_out <= 1'b0;
        end
        else if (counter_read_in) begin
            case (counter_index_in)
                3'h0: begin // tx counter, in byte
                    counter_value_out       <= tx_byte_counter;
                    counter_value_valid_out <= 1'b1;
                end
                3'h1: begin // tx drop counter, in byte
                    counter_value_out       <= tx_byte_drop_counter;
                    counter_value_valid_out <= 1'b1;
                end
                3'h2: begin // rx counter, in byte
                    counter_value_out       <= rx_byte_counter;
                    counter_value_valid_out <= 1'b1;
                end
                3'h3: begin // tx counter, in message
                    counter_value_out       <= tx_msg_counter;
                    counter_value_valid_out <= 1'b1;
                end
                3'h4: begin // tx drop counter, in message
                    counter_value_out       <= tx_msg_drop_counter;
                    counter_value_valid_out <= 1'b1;
                end
                3'h5: begin // rx counter, in message
                    counter_value_out       <= rx_msg_counter;
                    counter_value_valid_out <= 1'b1;
                end
                default: begin
                    counter_value_out       <= 64'h0;
                    counter_value_valid_out <= 1'b0;
                end
            endcase
        end
        else begin
            counter_value_out       <= 64'h0;
            counter_value_valid_out <= 1'b0;
        end
    end

endmodule
