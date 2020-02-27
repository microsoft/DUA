///////////////////////////////////////////////////////////////
//
// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.
//
////////////////////////////////////////////////////////////////

import SiliconNetTypes::*;

module ShimInterface
#(
    parameter FLIT_WIDTH,
              PHIT_WIDTH,
              NUM_VCS,
              NUM_PORTS,
              MAX_CREDIT_WIDTH,
              DISABLE_FULL_PIPE = 0     // Disables pipelining of the full signal. If set to '0', a client can only send a flit when there are at least 2 or more credits available.
                                        // Note: do not set to 1, since usr_full_out is modified
)
(
    input                                 clk,
    input                                 rst,

    // User Injection Port
    input  SwitchInterface                usr_ifc_in,
    input  wire                           usr_wren_in,
    output logic  [NUM_PORTS-1:0]         usr_full_out,

    // User Receive Port
    output SwitchInterface                usr_ifc_out,
    output logic                          usr_wren_out,
    input  wire                           usr_full_in,

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

    // This parameter affects how many credits are provided to the ER interface
    // on startup. Since we are using 'rtr_output_stall_out' for actual flow
    // control, we just pick a sufficiently large number to keep the link busy.
    localparam CREDITS_PER_PORT           = 128; // must be power of 2
    localparam TOTAL_CREDITS              = NUM_PORTS * CREDITS_PER_PORT; // must be power of 2

    localparam FLITS_PER_PORT_DOWNSTREAM  = SN_FLITS_PER_PORT_DOWNSTREAM;// for buffer outputs from out unit

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
    // On startup, provide an initial pool of credits to SiliconSwitch OutputUnit.
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
    // add an output buffer
    reg                                                         rd_req;
    wire                                                        wr_req;
    wire                                                        empty;
    wire                                                        full;
    reg  [$clog2(FLITS_PER_PORT_DOWNSTREAM*PHITS_PER_FLIT):0]   CreditUsedCounter;
    wire [$clog2(FLITS_PER_PORT_DOWNSTREAM*PHITS_PER_FLIT):0]   CreditUsedCounter_phit;
    SwitchInterface                                             rtr_ifc_tmp;
    reg                                                         rtr_valid_tmp;

    assign wr_req = (CreditUsedCounter==FLITS_PER_PORT_DOWNSTREAM*PHITS_PER_FLIT) ? 1'b0 : rtr_valid_in;
    assign rd_req = (usr_full_in) ? 1'b0 : ~empty;
    assign CreditUsedCounter_phit = (CreditUsedCounter/PHITS_PER_FLIT);

    FIFOCounter
    #(
        .DATA_WIDTH     ($bits(rtr_ifc_in)+$bits(rtr_valid_in)),
        .DEPTH          (FLITS_PER_PORT_DOWNSTREAM*PHITS_PER_FLIT)
    )
    FIFOCounter_ins
    (
        .clk            (clk),
        .rst            (rst),
        .rd_req         (rd_req),
        .wr_req         (wr_req),
        .data_in        ({rtr_ifc_in,rtr_valid_in}),
        .data_out       ({rtr_ifc_tmp,rtr_valid_tmp}),
        .empty          (empty),
        .half_full      (),
        .full           (full),
        .counter        (CreditUsedCounter)
    );

    assign creditQ.wren             = rtr_valid_in & rtr_ifc_in.last & ~creditQ.full;
    assign creditQ.data             = rtr_ifc_in.src_port;
    assign creditQ.rden             = ~creditQ.empty & rtr_credack_in & credit_initd_ff;
    assign rtr_credit_out.valid     = ~credit_initd_ff | (~creditQ.empty & (CreditUsedCounter_phit==0));
 
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
        for(i=0; i < NUM_PORTS; i=i+1) begin : genCreditCounters  // store credits from SiliconSwitch InputUnit
            logic credinc_d1;
            logic creddec_d1;

            shift_reg_clr
            #(
                .WIDTH  (2),
                .DELAY  (1)
            )
            pipe
            (
                .CLK    (clk),
                .CLR    (rst),
                .in     ({credinc[i],creddec[i]}),
                .out    ({credinc_d1,creddec_d1})
            );

            Counter
            #(
                .WIDTH  (MAX_CREDIT_WIDTH)
            )
            creditCounter
            (
                .clk    (clk),
                .rst    (rst),
                .inc_in (credinc[i]),
                .dec_in (creddec[i]),
                .value  (credits[i])
            );
        end
    endgenerate

    logic [NUM_PORTS-1:0]                   fullbits_ff;
    logic                                   full_ff;
    logic                                   full_net;

    generate
        for(i=0; i < NUM_PORTS; i=i+1) begin : genUserFullOut
            always @ (posedge clk) begin
                usr_full_out[i] <= (credits[i] <= 2) | (istate_ff.fsm == kPadPhit) | ~credit_initd_ff;
            end
        end
    endgenerate

    integer k, m;

    always_ff@(posedge clk) begin
        if(rst) begin
            full_ff     <= 1'b0;
            fullbits_ff <= 0;
        end
        else begin
            full_ff <= |fullbits_ff;
            for(k=0; k < NUM_PORTS; k=k+1) begin
                fullbits_ff[k] <= (credits[k] <= 2);
            end
        end
    end

    always_comb begin
        full_net = 1'b0;
        m = 0;
        for(m=0; m < NUM_PORTS; m=m+1) begin
            full_net = full_net | (credits[m] == 0);
        end
    end

    // maintain credits
    always_comb begin
        istate_nxt             = istate_ff;
        rtr_valid_out          = 1'b0;
        rtr_ifc_out            = {$bits(rtr_ifc_out){1'b0}};
        rtr_ifc_out.data       = {$bits(rtr_ifc_out.data){1'bx}};
        rtr_credack_out        = 1'b0;
        credinc                = {NUM_PORTS{1'b0}};
        creddec                = {NUM_PORTS{1'b0}};
         
        case(istate_ff.fsm)

            kIdle: begin
                if(usr_wren_in) begin
                    istate_nxt.fsm                      = kBusy;
                    istate_nxt.phit_count               = 1'b1;
                    istate_nxt.src_vc                   = usr_ifc_in.src_vc;
                    istate_nxt.src_port                 = usr_ifc_in.src_port;
                    istate_nxt.dst_vc                   = usr_ifc_in.dst_vc;
                    istate_nxt.dst_port                 = usr_ifc_in.dst_port;
                    rtr_valid_out                       = 1'b1;
                    rtr_ifc_out                         = usr_ifc_in;

                    if(usr_ifc_in.last) 
                        istate_nxt.fsm = kPadPhit;
                end
            end

            kBusy: begin
                if(usr_wren_in) begin
                    istate_nxt.phit_count               = (istate_ff.phit_count == PHITS_PER_FLIT-1) ? 1'b0 : istate_ff.phit_count + 1'b1;
                    
                    rtr_valid_out                       = 1'b1;
                    rtr_ifc_out                         = usr_ifc_in;

                    // Decrement a credit once we finish transmitting a full flit
                    if(istate_nxt.phit_count == 1'b0) begin
                        creddec[istate_ff.dst_port]         = 1'b1;
                    end

                    // If we're on the last user phit, check if we need to pad with extra phits.
                    if(usr_ifc_in.last) begin
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

                rtr_valid_out                           = 1'b1;
                rtr_ifc_out.dst_vc                      = istate_ff.dst_vc;
                rtr_ifc_out.dst_port                    = istate_ff.dst_port;
                rtr_ifc_out.src_vc                      = istate_ff.src_vc;
                rtr_ifc_out.src_port                    = istate_ff.src_port;                    
                rtr_ifc_out.data                        = {PHIT_WIDTH/2{2'b10}};
                rtr_ifc_out.first                       = 1'b0;
                rtr_ifc_out.last                        = 1'b0;
                rtr_ifc_out.pad_bytes                   = 0;

                if(istate_nxt.phit_count == 1'b0) begin
                    istate_nxt.fsm                      = kIdle;
                    creddec[istate_ff.dst_port]         = 1'b1;
                end
            end
        endcase

        if(rtr_credit_in.valid) begin
            credinc[rtr_credit_in.port] = 1'b1;
            rtr_credack_out             = 1'b1;
        end
    end

    always_ff@(posedge clk) begin
        if(rst) begin
            istate_ff               <= '{kIdle,{PHIT_COUNT_WIDTH{1'b0}},{$bits(VC){1'b0}},{$bits(Port){1'b0}},{$bits(VC){1'b0}},{$bits(Port){1'b0}}};
        end
        else begin
            istate_ff               <= istate_nxt;
        end
    end

    ///////////////////////////////////////////////////////////
    // FSMs at each of the output ports are used to filter
    // padded phits.
    ///////////////////////////////////////////////////////////

    assign usr_wren_out          = rtr_valid_tmp;
    assign usr_ifc_out           = rtr_ifc_tmp;

endmodule