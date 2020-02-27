///////////////////////////////////////////////////////////////
//
// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.
//
////////////////////////////////////////////////////////////////

import SiliconNetTypes::*;

module ShimInterface1toN
#(
    parameter FLIT_WIDTH,
              PHIT_WIDTH,
              NUM_VCS,
              NUM_PORTS,
              MAX_CREDIT_WIDTH,
              ENABLE_FAIR_SHARING,
              DISABLE_FULL_PIPE         // Disables pipelining of the full signal. If set to '0', a client can only send a flit when there are at least 2 or more credits available.
                                        // Note: do not set to 1, since usr_full_out is modified
)
(
    input                                 clk,
    input                                 rst,

    // User Injection Port
    input  SwitchInterface                [NUM_VCS-1:0]       usr_ifc_in,
    input  wire                           [NUM_VCS-1:0]       usr_wren_in,
    output wire                           [NUM_PORTS-1:0]     usr_full_out,
    input  logic                          [NUM_VCS-1:0]       usr_raise_in,    
    output logic                          [NUM_VCS-1:0]       usr_grant_out,    //used to grand input request among vc

    // User Receive Port
    output SwitchInterface                [NUM_VCS-1:0]       usr_ifc_out,
    output logic                          [NUM_VCS-1:0]       usr_wren_out,
    input  wire                           [NUM_VCS-1:0]       usr_full_in,

    // SiliconSwitch Injection
    output SwitchInterface                rtr_ifc_out,
    output logic                          rtr_valid_out,
    input  SwitchCredit                   rtr_credit_in,
    output logic                          rtr_credack_out,

    // SiliconSwitch Ejection
    input  SwitchInterface                rtr_ifc_in,
    input  wire                           rtr_valid_in,
    output logic                          rtr_output_stall_out,
    output SwitchCredit                   rtr_credit_out,
    input  wire                           rtr_credack_in
);

    localparam PHITS_PER_FLIT             = FLIT_WIDTH / PHIT_WIDTH;
    localparam PHIT_COUNT_WIDTH           = $clog2(PHITS_PER_FLIT);
    localparam PAD_WIDTH                  = $clog2(PHIT_WIDTH/8);

    // This parameter affects how many credits are provided to the ER interface
    // on startup. Since we are using 'rtr_output_stall_out' for actual flow
    // control, we just pick a sufficiently large number to keep the link busy.
    localparam CREDITS_PER_PORT           = 16; // must be power of 2
    localparam TOTAL_CREDITS              = NUM_PORTS * CREDITS_PER_PORT; // must be power of 2

    localparam FLITS_PER_PORT_DOWNSTREAM  = SN_FLITS_PER_PORT_DOWNSTREAM;// for buffer outputs from out unit

    localparam TRUE                       = 1'b1;
    localparam FALSE                      = 1'b0;

    integer j;

    typedef logic [NUM_VCS-1:0] VCDecision;

    function VCDecision VCroute(input VC dst_vc);
        begin
            VCroute         = {NUM_PORTS{FALSE}};
            VCroute[dst_vc] = TRUE;
        end
    endfunction

    //generate a clock to sync out among the vcs
    reg clk_out;
    CounterDiv 
    #(
        .N          (PHITS_PER_FLIT+1),  
        .WIDTH      (8) 
    )
    CounterDiv5
    (
        .clk        (clk),
        .rst        (rst),
        .clk_out    (clk_out)
    );
    
    struct packed {
        logic                             wren;
        logic                             full;
        logic [$clog2(NUM_PORTS)-1:0]     data;
        logic                             rden;
        logic                             empty;
        logic [$clog2(NUM_PORTS)-1:0]     q;
    } creditQ;

    RegisterFIFOSkid#(.WIDTH($clog2(NUM_PORTS))) CreditOutQ
    (
        .clock                            (clk),
        .reset_n                          (~rst),
        .wrreq                            (creditQ.wren),
        .data                             (creditQ.data),
        .full                             (creditQ.full),
        .rdreq                            (creditQ.rden),
        .empty                            (creditQ.empty),
        .q                                (creditQ.q)
    );

    ///////////////////////////////////////////////////////////
    // On startup, provide an initial pool of credits to SiliconSwitch.
    ///////////////////////////////////////////////////////////

    logic                                 credit_initd_ff  = 1'b0;
    logic [$clog2(NUM_PORTS)-1:0]         which_port_ff    = 0;
    logic [$clog2(TOTAL_CREDITS)-1:0]     total_credits_ff = 0;

    always_ff@(posedge clk) begin
        if(rst) begin
            credit_initd_ff      <= 1'b0;
            which_port_ff        <= 0;
            total_credits_ff     <= 0;
        end
        else begin
            if(~credit_initd_ff & ~rtr_credack_in) begin
                which_port_ff    <= (which_port_ff == {$bits(which_port_ff){1'b1}}) ? 0 : which_port_ff + 1'b1;
                total_credits_ff <= total_credits_ff + 1'b1;
                if(total_credits_ff == {$bits(total_credits_ff){1'b1}}) begin
                    credit_initd_ff <= 1'b1;
                end
            end
        end
    end

    assign rtr_credit_out.port      = ~credit_initd_ff ? which_port_ff : creditQ.q;
    assign rtr_output_stall_out     = creditQ.full;

    // change to FIFOCounter output, only write credits if actually read out from FIFOCouter
    // output buffer
    wire                                                        rd_req                  [NUM_VCS-1:0];
    reg                                                         wr_req                  [NUM_VCS-1:0];
    wire                                                        empty                   [NUM_VCS-1:0];              
    wire                                                        full                    [NUM_VCS-1:0];
    reg  [$clog2(FLITS_PER_PORT_DOWNSTREAM*PHITS_PER_FLIT):0]   CreditUsedCounter       [NUM_VCS-1:0];
    wire [$clog2(FLITS_PER_PORT_DOWNSTREAM*PHITS_PER_FLIT):0]   CreditUsedCounter_phit  [NUM_VCS-1:0];  // max vc count is 4
    SwitchInterface                                             rtr_ifc_tmp             [NUM_VCS-1:0];
    reg                                                         rtr_valid_tmp           [NUM_VCS-1:0];
    SwitchInterface                                             rtr_ifc_delayed1c;
    reg                                                         rtr_valid_delayed1c;

    reg  [$clog2(FLITS_PER_PORT_DOWNSTREAM*PHITS_PER_FLIT):0]   CreditUsedCounter_phit_total;

    genvar n;
    assign CreditUsedCounter_phit_total = (NUM_VCS==4) ? CreditUsedCounter_phit[0]+CreditUsedCounter_phit[1]+CreditUsedCounter_phit[2]+CreditUsedCounter_phit[3] :
                                          (NUM_VCS==3) ? CreditUsedCounter_phit[0]+CreditUsedCounter_phit[1]+CreditUsedCounter_phit[2] :
                                          (NUM_VCS==2) ? CreditUsedCounter_phit[0]+CreditUsedCounter_phit[1] :
                                          (NUM_VCS==1) ? CreditUsedCounter_phit[0] : 0;
    always@(posedge clk) begin
        rtr_ifc_delayed1c <= rtr_ifc_in;
        rtr_valid_delayed1c <= rtr_valid_in;                
    end

    generate
        for (n=0; n<NUM_VCS; n++) begin: genOutputBuffer
            always@(posedge clk) begin
                //assign wr_req[n] = (CreditUsedCounter[n]==FLITS_PER_PORT_DOWNSTREAM*PHITS_PER_FLIT)|(rtr_ifc_in.dst_vc!=n) ? 1'b0 : rtr_valid_in;
                wr_req[n] <= (CreditUsedCounter[n]==FLITS_PER_PORT_DOWNSTREAM*PHITS_PER_FLIT)|(rtr_ifc_in.dst_vc!=n) ? 1'b0 : rtr_valid_in;
                //rtr_ifc_delayed1c <= rtr_ifc_in;
                //rtr_valid_delayed1c <= rtr_valid_in;                
            end
            assign rd_req[n] = (usr_full_in[n]) ? 1'b0 : ~empty[n];
            assign CreditUsedCounter_phit[n] = (CreditUsedCounter[n]/PHITS_PER_FLIT);

            FIFOCounter
            #(
                .DATA_WIDTH     ($bits(rtr_ifc_in)+$bits(rtr_valid_in)),
                .DEPTH          (FLITS_PER_PORT_DOWNSTREAM*PHITS_PER_FLIT)
            )
            FIFOCounter_ins
            (
                .clk            (clk),
                .rst            (rst),
                .rd_req         (rd_req[n]),
                .wr_req         (wr_req[n]),
                .data_in        ({rtr_ifc_delayed1c,rtr_valid_delayed1c}),
                .data_out       ({rtr_ifc_tmp[n],rtr_valid_tmp[n]}),
                .empty          (empty[n]),
                .half_full      (),
                .full           (full[n]),
                .counter        (CreditUsedCounter[n])
            );
        end
    endgenerate    

    assign creditQ.wren             = rtr_valid_in & rtr_ifc_in.last & ~creditQ.full;
    assign creditQ.data             = rtr_ifc_in.src_port;
    assign creditQ.rden             = ~creditQ.empty & rtr_credack_in & credit_initd_ff;
    assign rtr_credit_out.valid     = ~credit_initd_ff | (~creditQ.empty & (CreditUsedCounter_phit_total==0));
 
    ///////////////////////////////////////////////////////////
    // FSMs at each of the input ports are used to pad
    // empty phits.
    /////////////////////////////////////////////////////////// 

    typedef enum logic [1:0] 
    {
        kIdle    = 2'd0,
        kBusy    = 2'd1,
        kPadPhit = 2'd2
    } InputState;

    struct {
        InputState                          fsm;
        logic [PHIT_COUNT_WIDTH-1:0]        phit_count;
        VC                                  src_vc;
        Port                                src_port;
        VC                                  dst_vc;
        Port                                dst_port;
    } istate_ff, istate_nxt;

    logic [MAX_CREDIT_WIDTH-1:0]            credits [NUM_PORTS-1:0];
    logic [NUM_PORTS-1:0]                   credinc;
    logic [NUM_PORTS-1:0]                   creddec;

    genvar i;
    generate
        for(i=0; i < NUM_PORTS; i=i+1) begin : genCreditCounters  //note: store SiliconSwitch input unit credits 20180327
            logic credinc_d1;
            logic creddec_d1;

            shift_reg_clr
            #(
                .WIDTH      (2),
                .DELAY      (1)
            )
            pipe
            (
                .CLK        (clk),
                .CLR        (rst),
                .in         ({credinc[i],creddec[i]}),
                .out        ({credinc_d1,creddec_d1})
            );

            Counter
            #(
                .WIDTH      (MAX_CREDIT_WIDTH)
            )
            creditCounter
            (
                .clk        (clk),
                .rst        (rst),
                .inc_in     (credinc[i]),
                .dec_in     (creddec[i]),
                .value      (credits[i])
            );
        end
    endgenerate

    logic [NUM_PORTS-1:0]                   fullbits_ff;
    logic                                   full_ff;
    logic                                   full_net;

    generate
        for(i=0; i < NUM_PORTS; i=i+1) begin : genUserFullOut
            assign usr_full_out[i] = (DISABLE_FULL_PIPE ? (credits[i] == 0) : (credits[i] <= 2)) | (istate_ff.fsm == kPadPhit) | ~credit_initd_ff | (!clk_out);
        end
    endgenerate

    integer k, m;

    always_ff@(posedge clk) begin
        if(rst) begin
            full_ff     <= 1'b0;
            fullbits_ff <= 0;
        end
        else begin
            full_ff     <= |fullbits_ff;
            for(k=0; k < NUM_PORTS; k=k+1)
                fullbits_ff[k] <= (credits[k] <= 2);
        end
    end

    always_comb begin
        full_net = 1'b0;
        m = 0;
        for(m=0; m < NUM_PORTS; m=m+1) begin
            full_net = full_net | (credits[m] == 0);
        end
    end

    // arbiter of vc inputs (max vc is 4)
    logic [15:0] lfsr_value;
    lfsrN#(.WIDTH(16)) lfsr16
    (
        .CLK                     (clk),
        .clear                   (rst),
        .en                      (1'b1),
        .poly                    (16'b101101), // maximal length poly x^16 + x^14 + x^13 + x^11 + 1
        .value                   (lfsr_value)
    );

    reg [1:0]           update_in; 
    reg [1:0]           update_in_tmp;
    reg                 usr_grant_valid_out;
    assign update_in_tmp = ENABLE_FAIR_SHARING? ({lfsr_value[1]&usr_grant_valid_out&clk_out,lfsr_value[0]&usr_grant_valid_out&clk_out}) : {1'b0,usr_grant_valid_out&clk_out};

    DelayOutput_1b 
    #(
        .N(PHITS_PER_FLIT)
    ) 
    DelayOutput_1b_ins1
    (
        .clk                    (clk),  
        .rst                    (rst),
        .data_in                (update_in_tmp[1]),
        .data_out               (update_in[1])
    );

    DelayOutput_1b 
    #(
        .N(PHITS_PER_FLIT)
    ) 
    DelayOutput_1b_ins0
    (
        .clk                    (clk),  
        .rst                    (rst),
        .data_in                (update_in_tmp[0]),
        .data_out               (update_in[0])
    );

    FastArbiterRandUpdate4 FastArbiterRandUpdate4_ins
    (
        .clk        (clk),
        .rst        (rst),
        .clear_in   (rst),
        .update_in  (update_in),
        .raises_in  (usr_raise_in),
        .grant_out  (usr_grant_out),
        .valid_out  (usr_grant_valid_out)
    );
   
    // mux out among vc input (max vc is 4)
    //mux in
    SwitchInterface                  usr_ifc_in_internal      [NUM_VCS-1:0];
    logic           [NUM_VCS-1:0]    usr_wren_in_internal;
    //mux out
    SwitchInterface                  usr_ifc_in_mux;
    logic                            usr_wren_in_mux;

    //generate a synced fsm
    typedef enum logic [2:0] 
    {
        sIdel    = 3'd0,
        sTick    = 3'd1
    } syncState;
    struct packed {
        syncState                          fsm;
        logic          [7:0]               ticks;
    } sstate_ff, sstate_nxt;

    always_comb begin
        sstate_nxt              = sstate_ff;        
        case(sstate_ff.fsm)
            sIdel: begin
                if (clk_out) begin
                    sstate_nxt.fsm   = sTick;
                    sstate_nxt.ticks = PHITS_PER_FLIT - 1;
                end
            end
            sTick: begin
                if (sstate_ff.ticks == 0) begin
                    sstate_nxt.fsm   = sIdel;
                    sstate_nxt.ticks = PHITS_PER_FLIT;
                end
                else begin
                    sstate_nxt.fsm   = sTick;
                    sstate_nxt.ticks = sstate_ff.ticks - 1;
                end
            end
        endcase
    end

    always_ff@(posedge clk) begin
        if(rst) begin
            sstate_ff         <= {sIdel,8'b0};
        end
        else begin
            sstate_ff         <= sstate_nxt;
        end
    end

    //generage
    genvar l;
    generate
        for (l=0; l<NUM_VCS; l++) begin: generate_grant
            assign usr_ifc_in_internal[l]   =   usr_ifc_in[l];
            assign usr_wren_in_internal[l]  =   usr_grant_out[l];
        end
    endgenerate

    treemux_prim
    #(
        .WIDTH      ($bits(usr_ifc_in_mux)),
        .N          (NUM_VCS)
    )
    treemux_prim_ifc_ins
    (
        .CLK        (clk),
        .RST_N      (!rst),
        .data_in    (usr_ifc_in_internal),
        .valid_in   (usr_wren_in_internal),
        .data_out   (usr_ifc_in_mux),
        .valid_out  (usr_wren_in_mux)
    );

    always_comb begin

        istate_nxt             = istate_ff;

        rtr_valid_out          = FALSE;
        rtr_ifc_out            = {$bits(rtr_ifc_out){1'b0}};
        rtr_ifc_out.data       = {$bits(rtr_ifc_out.data){1'bx}};
        rtr_ifc_out.src_vc     = {$bits(rtr_ifc_out.src_vc){1'bx}};
        rtr_ifc_out.src_port   = {$bits(rtr_ifc_out.src_port){1'bx}};
        rtr_ifc_out.dst_vc     = {$bits(rtr_ifc_out.dst_vc){1'bx}};
        rtr_ifc_out.dst_port   = {$bits(rtr_ifc_out.dst_port){1'bx}};
        rtr_ifc_out.pad_bytes  = {$bits(rtr_ifc_out.pad_bytes){1'bx}};
        rtr_credack_out        = FALSE;

        credinc                = {NUM_PORTS{1'b0}};
        creddec                = {NUM_PORTS{1'b0}};
         
        case(istate_ff.fsm)

            kIdle: begin
                if(usr_wren_in_mux) begin
                    istate_nxt.fsm                      = kBusy;
                    istate_nxt.phit_count               = 1'b1;
                    istate_nxt.src_vc                   = usr_ifc_in_mux.src_vc;
                    istate_nxt.src_port                 = usr_ifc_in_mux.src_port;
                    istate_nxt.dst_vc                   = usr_ifc_in_mux.dst_vc;
                    istate_nxt.dst_port                 = usr_ifc_in_mux.dst_port;

                    rtr_valid_out                       = TRUE;
                    rtr_ifc_out                         = usr_ifc_in_mux;
                    
                    if(usr_ifc_in_mux.last) 
                        istate_nxt.fsm = kPadPhit;                
                end                
            end

            kBusy: begin
                if(usr_wren_in_mux) begin
                    istate_nxt.phit_count               = (istate_ff.phit_count == PHITS_PER_FLIT-1) ? 1'b0 : istate_ff.phit_count + 1'b1;

                    rtr_valid_out                       = 1'b1;
                    rtr_ifc_out                         = usr_ifc_in_mux;
                    
                    // Decrement a credit once we finish transmitting a full flit
                    if(istate_nxt.phit_count == 1'b0) begin
                        creddec[rtr_ifc_out.dst_port]     = TRUE;
                    end

                    // If we're on the last user phit, check if we need to
                    // pad with extra phits.
                    if(usr_ifc_in_mux.last) begin
                        if(istate_nxt.phit_count == 1'b0) begin
                            istate_nxt.fsm = kIdle;
                        end
                        else begin
                            istate_nxt.fsm = kPadPhit;
                        end
                    end
                end
            end

            kPadPhit: begin
                
                istate_nxt.phit_count                   = (istate_ff.phit_count == PHITS_PER_FLIT-1) ? 1'b0 : istate_ff.phit_count + 1'b1;
                
                rtr_valid_out                           = TRUE;
                rtr_ifc_out.dst_vc                      = istate_ff.dst_vc;
                rtr_ifc_out.dst_port                    = istate_ff.dst_port;
                rtr_ifc_out.src_vc                      = istate_ff.src_vc;
                rtr_ifc_out.src_port                    = istate_ff.src_port;
                rtr_ifc_out.data                        = {PHIT_WIDTH/2{2'b10}};
                rtr_ifc_out.first                       = FALSE;
                rtr_ifc_out.last                        = FALSE;
                rtr_ifc_out.pad_bytes                   = 0;

                if(istate_nxt.phit_count == 1'b0) begin
                    istate_nxt.fsm                      = kIdle;
                    creddec[rtr_ifc_out.dst_port]       = TRUE;
                end
            end

        endcase

        if(rtr_credit_in.valid) begin
            credinc[rtr_credit_in.port] = TRUE;
            rtr_credack_out             = TRUE;
        end

    end

    integer c;
    always_ff@(posedge clk) begin
        if(rst) begin
            istate_ff.fsm     <= kIdle;
        end
        else begin
            istate_ff         <= istate_nxt;
        end
    end

    ///////////////////////////////////////////////////////////
    // FSMs at each of the output ports are used to filter
    // padded phits.
    ///////////////////////////////////////////////////////////

    typedef enum logic [1:0] {
        kDataIdle   = 2'd0,
        kDataBusy   = 2'd1,
        kDataFilter = 2'd2
    } DataOutputState;
    
    genvar p;
    generate
        for(p=0; p < NUM_VCS; p=p+1) begin : genUsrIfcOut

            struct packed {
                DataOutputState                 data_fsm;
                logic [PHIT_COUNT_WIDTH-1:0]    phit_count;
            } ostate_ff, ostate_nxt;

            //always_comb begin
            always@(posedge clk) begin
                ostate_nxt              = ostate_ff;
                
                usr_wren_out[p]            = FALSE;
                usr_ifc_out[p]             = {$bits(SwitchInterface){1'bx}};
               
                // Data FSM
                case(ostate_ff.data_fsm)
                    kDataIdle: begin
                        if(rtr_valid_tmp[p]) begin
                            usr_wren_out[p]          = TRUE;
                            usr_ifc_out[p]           = rtr_ifc_tmp[p];
                            ostate_nxt.phit_count = 1'b1;
                            if(rtr_ifc_tmp[p].last)
                                ostate_nxt.data_fsm = kDataFilter;
                            else
                                ostate_nxt.data_fsm = kDataBusy;
                        end
                    end

                    kDataBusy: begin
                        if(rtr_valid_tmp[p]) begin
                            ostate_nxt.phit_count = (ostate_ff.phit_count == PHITS_PER_FLIT-1) ? 1'b0 : ostate_ff.phit_count + 1'b1;
                            usr_wren_out[p]          = TRUE;
                            usr_ifc_out[p]           = rtr_ifc_tmp[p];

                            if(rtr_ifc_tmp[p].last) begin
                                if(ostate_nxt.phit_count == 1'b0) begin
                                    ostate_nxt.data_fsm = kDataIdle;
                                end
                                else begin
                                    ostate_nxt.data_fsm = kDataFilter;
                                end
                            end  
                        end
                    end

                    kDataFilter: begin
                        if(rtr_valid_tmp[p]) begin
                            ostate_nxt.phit_count = (ostate_ff.phit_count == PHITS_PER_FLIT-1) ? 1'b0 : ostate_ff.phit_count + 1'b1;
                        end

                        if(ostate_nxt.phit_count == 1'b0) begin
                            ostate_nxt.data_fsm = kDataIdle;
                        end 
                    end

                    default: begin
                        usr_wren_out[p]            = FALSE;
                        usr_ifc_out[p]             = {$bits(SwitchInterface){1'bx}};
                    end
                endcase
            end
            
            always@(posedge clk) begin
                if(rst) begin
                    ostate_ff <= '{kDataIdle,{PHIT_COUNT_WIDTH{1'b0}}};
                end
                else begin
                    ostate_ff <= ostate_nxt;
                end
            end

        end
    endgenerate

endmodule
