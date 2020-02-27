///////////////////////////////////////////////////////////////
//
// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.
//
////////////////////////////////////////////////////////////////

import SiliconNetTypes::*;

module OutputUnit
#(
    parameter NUM_PORTS,
              PORT_NUM,
              MAX_FLITS_PER_PORT_DOWNSTREAM,
              PHIT_WIDTH,
              FLIT_WIDTH,
              USE_LUTRAM,
              MAX_CREDIT_WIDTH
)
(
    input                                 clk,
    input                                 rst,

    // Input port
    input  [NUM_PORTS-1:0]                input_valid_in,
    input  SwitchInterface                input_ifc_in [NUM_PORTS-1:0],
    output logic                          input_stall_out,

    // Raise-Response to Input Units
    input  SwitchRaise                    raise_in  [NUM_PORTS-1:0],
    output SwitchGrant                    grant_out,
    input  wire                           sync_in,

    // Output port
    output SwitchInterface                output_ifc_out,
    output                                output_valid_out,
    input                                 output_stall_in,

    // Credits from downstream
    input  SwitchCredit                   credit_in,
    output logic                          credack_out
);

    localparam PHITS_PER_FLIT             = FLIT_WIDTH / PHIT_WIDTH;
    localparam PHIT_COUNT_WIDTH           = $clog2(PHITS_PER_FLIT + 1);
    localparam PORT_WIDTH                 = $clog2(NUM_PORTS);
    localparam FLIT_COUNT_WIDTH           = $clog2(MAX_FLITS_PER_PORT_DOWNSTREAM + 1); // number of bits to count flits per Port
    localparam LOG_PHITS_PER_FLIT         = $clog2(PHITS_PER_FLIT);
    localparam WAIT_CYCLES                = (PHITS_PER_FLIT < 3) ? 0 : (PHITS_PER_FLIT - 3);

    localparam TRUE                       = 1'b1;
    localparam FALSE                      = 1'b0;
    localparam VERB                       = FALSE;

    ////////////////////////////////////////////////////////
    // Async FIFO that crosses in credits from the output
    //////////////////////////////////////////////////////// 

    struct packed {
        logic [PORT_WIDTH-1:0]  q;
        logic                   empty;
        logic                   rden;
        logic                   full;
    } creditQ;

    FIFO
    #(
        .LOG_DEPTH      (5),
        .WIDTH          (PORT_WIDTH),
        .USE_LUTRAM     (1'b1)
    )
    CreditQ
    (
        .clock          (clk),
        .reset_n        (~rst),

        .wrreq          (credit_in.valid & ~creditQ.full),
        .data           (credit_in.port),
        .full           (creditQ.full),
        .almost_full    (),
        .usedw          (),

        .rdreq          (creditQ.rden),
        .empty          (creditQ.empty),
        .almost_empty   (),
        .q              (creditQ.q)
    );
 
    assign credack_out = credit_in.valid & ~creditQ.full;

    ////////////////////////////////////////////////////////
    // Tracks how many credits issued per Port
    //////////////////////////////////////////////////////// 
 
    struct packed {
        logic                        wren;
        logic [PORT_WIDTH-1:0]       waddr;
        logic [PORT_WIDTH-1:0]       raddr;
        logic [FLIT_COUNT_WIDTH-1:0] din;
        logic [FLIT_COUNT_WIDTH-1:0] dout;
    } used_ram;

    lutram_dual
    #(
        .WIDTH                  (FLIT_COUNT_WIDTH),
        .DEPTH                  (NUM_PORTS)
    )
    UsedRAM
    (
        .CLK                    (clk),
        .CLR                    (rst),
        .wen                    (used_ram.wren),
        .waddr                  (used_ram.waddr),
        .din                    (used_ram.din),
        .raddr_0                (used_ram.raddr),
        .dout_0                 (used_ram.dout),
        .raddr_1                (),
        .dout_1                 ()
    );

    ////////////////////////////////////////////////////////
    // Arbiter that selects from Input Units
    ////////////////////////////////////////////////////////
    
    struct packed {
        logic [NUM_PORTS-1:0]    raise;
        logic [NUM_PORTS-1:0]    grant;
        logic                    valid;

        // Granted signals
        logic [PORT_WIDTH-1:0]   src_port;
        logic                    last;
    } arbiter;

    Arbiter_v2 #(.N(NUM_PORTS)) InputArbiter
    (
        .clk                    (clk), 
        .rst                    (rst), 
        .stall                  (0), 
        .raises                 (arbiter.raise), 
        .grant                  (arbiter.grant), 
        .valid                  (arbiter.valid)
    );

    ////////////////////////////////////////////////////////
    // LUTRAM for locking a single Port to a given port
    //////////////////////////////////////////////////////// 

    struct 
    {
        // Writes
        logic                   wren;
        Port                    wrpt;
        logic                   wrlock;
        Port                    wrport;
        
        // Reads
        logic                   rdlock [NUM_PORTS-1:0];
        Port                    rdpt   [NUM_PORTS-1:0];
        Port                    rdport [NUM_PORTS-1:0];
    } lock_ram;

    reg [31:0] cycles = 32'd0;

    // Global lock
    lutram_dual
    #(
        .WIDTH                  (1+PORT_WIDTH),
        .DEPTH                  (NUM_PORTS)
    )
    LockRam
    (
        .CLK                    (clk),
        .CLR                    (rst),
        .wen                    (lock_ram.wren),
        .waddr                  (lock_ram.wrpt),
        .din                    ({lock_ram.wrlock,lock_ram.wrport}),
        .raddr_0                (lock_ram.rdpt[0]),
        .dout_0                 ({lock_ram.rdlock[0],lock_ram.rdport[0]}),
        .raddr_1                ({PORT_WIDTH{1'bx}}),
        .dout_1                 ()
    );
    
    assign lock_ram.rdpt[0] = 0;
    
    genvar i;
    generate
        for(i=0; i < NUM_PORTS; i=i+1) begin : gen_arbiter_inputs

            // The lock RAM lets us lock a particular input port per Port
            // assign lock_ram.rdpt[i] = i[PORT_WIDTH-1:0];
            wire suppress           = lock_ram.rdlock[0] & (lock_ram.rdport[0] != i[PORT_WIDTH-1:0]);
            assign arbiter.raise[i] = raise_in[i].dst_port_one_hot[PORT_NUM] & ~suppress;

        end
    endgenerate

    ////////////////////////////////////////////////////////
    // This FSM processes responses
    ////////////////////////////////////////////////////////

    typedef enum logic [2:0] {
        kSync       = 3'd0,
        kGrant      = 3'd1,
        kGrant2     = 3'd2,
        kCredit     = 3'd3,
        kRecvData   = 3'd4
    } GrantState;

    struct packed {
        GrantState                      fsm;
        SwitchGrant                     grant;
        logic [MAX_CREDIT_WIDTH-1:0]    shared_credits;
        logic                           shared_credits_avail;
        logic                           shared_credits_maxed;
        logic                           shared_credits_inc;
        logic                           shared_credits_dec;
        logic [PHIT_COUNT_WIDTH-1:0]    phit_count;
        logic [FLIT_COUNT_WIDTH-1:0]    used;

        // Remember from the arbiter
        logic                           arb_valid;
        logic [PORT_WIDTH-1:0]          arb_src_port;
        logic                           arb_last; 

        // Remember first stage decisions
        logic                           grant_valid;
		  
		// Remember for used
		logic                           used_dec;
		logic [PORT_WIDTH-1:0]          used_dec_addr;
		logic [FLIT_COUNT_WIDTH-1:0]    used_dec_data;
    } grant_state_ff, grant_state_nxt;

    assign grant_out = grant_state_ff.grant; // To Input Units

    integer k;
    always@(*) begin

        // Grant state
        grant_state_nxt             = grant_state_ff;
        grant_state_nxt.grant       = '{FALSE,{PORT_WIDTH{1'bx}},{PORT_WIDTH{1'bx}}};
        grant_state_nxt.grant_valid = FALSE;

        // Credit management
        creditQ.rden                = FALSE;

        // Track credits used per Port
        used_ram.wren               = FALSE;
        used_ram.waddr              = {PORT_WIDTH{1'bx}};
        used_ram.raddr              = {PORT_WIDTH{1'bx}};
        used_ram.din                = {FLIT_COUNT_WIDTH{1'bx}};

        // Selected Port and port from arbiter
        arbiter.src_port            = {PORT_WIDTH{1'bx}};
        arbiter.last                = 1'bx;
        
        // Default lock RAM control
        lock_ram.wren               = FALSE;
        lock_ram.wrpt               = {PORT_WIDTH{1'bx}};
        lock_ram.wrlock             = 1'bx;
        lock_ram.wrport             = {PORT_WIDTH{1'bx}};

        // Force output units to synchronize with input units on resets
 
        // Select the 'port' from the arbiter
        for(k=0; k < NUM_PORTS; k=k+1) begin
            if(arbiter.grant[k]) begin
                arbiter.last     = raise_in[k].msg_last;
                arbiter.src_port = k[PORT_WIDTH-1:0];
            end
        end

        case(grant_state_ff.fsm)

            // Wait here after reset until we sync up with input units
            kSync: begin
                if(sync_in) begin
                    grant_state_nxt.fsm = kGrant;
                end
            end

            // Grant to a single input unit
            kGrant: begin

                // merged from
                // Save the arbiter result
                grant_state_nxt.arb_valid    = arbiter.valid;
                grant_state_nxt.arb_src_port = arbiter.src_port;
                grant_state_nxt.arb_last     = arbiter.last;
                // Update available shared credits
                grant_state_nxt.shared_credits_avail = (grant_state_ff.shared_credits > 0);
                grant_state_nxt.shared_credits_maxed = (grant_state_ff.shared_credits == {MAX_CREDIT_WIDTH{1'b1}});
                // merge end
                
                // Look up memories that track how many flits
                // are used for the target Port, and whether
                // the private flit per Port is available.
                used_ram.raddr               = arbiter.src_port;
                grant_state_nxt.used         = used_ram.dout;
                grant_state_nxt.grant_valid  = FALSE;

                // We granted an input port
                if(arbiter.valid) begin
                    // issue a shared credit
                    if((used_ram.dout < MAX_FLITS_PER_PORT_DOWNSTREAM) & (grant_state_ff.shared_credits > 0)) begin //(grant_state_ff.shared_credits > 0)) begin
                        grant_state_nxt.grant_valid = TRUE;
                        grant_state_nxt.grant.valid = TRUE;
                    end
                end 
              
                // Okay to remember regardless of whether we granted or not
                grant_state_nxt.grant.src_port  = arbiter.src_port;//arbiter.src_port;
                grant_state_nxt.grant.dst_port  = PORT_NUM[PORT_WIDTH-1:0]; 

                // Move to second grant stage
                grant_state_nxt.fsm             = kGrant2; 
            end

            // Update internal state about the grant
            kGrant2: begin

                if(grant_state_ff.grant_valid) begin

                    used_ram.waddr          = grant_state_ff.arb_src_port;

                    // update the shared credit count
                    grant_state_nxt.shared_credits_dec = 1'b1;

                    // Update how many flits were used for the dst Port
                    used_ram.din      = grant_state_ff.used + 1'b1;
                    used_ram.wren     = TRUE;

                    // Lock the destination port and destination Port
                    // to a particular input source port to avoid
                    // interleaving.
                    lock_ram.wren     = TRUE;
                    // global
                    lock_ram.wrpt     = 0;
                    lock_ram.wrlock   = ~grant_state_ff.arb_last;
                    lock_ram.wrport   = grant_state_ff.arb_src_port;
                end
          
                // Process any pending credit returns
                grant_state_nxt.fsm = kCredit;
            end

            kCredit: begin

                if(~creditQ.empty & ~grant_state_ff.shared_credits_maxed) begin
                    used_ram.raddr           = creditQ.q;                    

                    creditQ.rden = TRUE;

                    // Decrement used count in next cycle
						  // FIXIT: async used write
						  
                    grant_state_nxt.used_dec_data = used_ram.dout;
                    grant_state_nxt.used_dec_addr = creditQ.q; // update used RAM
                    grant_state_nxt.used_dec      = TRUE;      // update used RAM

                    // restore to shared credit
                    grant_state_nxt.shared_credits_inc = 1'b1;
                end 

                // Now wait a few extra cycles for data to flow through
                // before checking for another 'raise'
					 // XXX: Notice that we have a mininum PHIT_COUNT = 4 for output FSM in input unit
                grant_state_nxt.fsm        = kRecvData;
                grant_state_nxt.phit_count = WAIT_CYCLES[PHIT_COUNT_WIDTH-1:0];


                if(grant_state_nxt.phit_count == 1'b0) begin
                    grant_state_nxt.fsm = kGrant;
                end
            end

            kRecvData: begin
				
				// Update used here
				if (grant_state_ff.used_dec == TRUE) begin
					used_ram.waddr    = grant_state_ff.used_dec_addr;
					used_ram.din      = grant_state_ff.used_dec_data - 1'b1;
                    used_ram.wren     = grant_state_ff.used_dec_data == 0 ? FALSE : TRUE;
						  
                    grant_state_nxt.used_dec = FALSE;
				end
				
                grant_state_nxt.phit_count = grant_state_ff.phit_count - 1'b1;
                if(grant_state_ff.phit_count == 1'b1) begin
                    grant_state_nxt.fsm = kGrant;
                end

                // Re-arm to 0
                grant_state_nxt.shared_credits_inc = 1'b0;
                grant_state_nxt.shared_credits_dec = 1'b0;

                // Update shared credits from previous round
                if(grant_state_ff.shared_credits_inc & ~grant_state_ff.shared_credits_dec) begin
                    grant_state_nxt.shared_credits = grant_state_ff.shared_credits + 1'b1;
                end
                else if(grant_state_ff.shared_credits_dec & ~grant_state_ff.shared_credits_inc) begin
                    grant_state_nxt.shared_credits = grant_state_ff.shared_credits - 1'b1;
                end 
            end

        endcase
    end

    always@(posedge clk) begin
        if(rst) begin
            grant_state_ff      <= '{kSync,
                                    {$bits(SwitchGrant){1'b0}},
                                    {MAX_CREDIT_WIDTH{1'b0}},
                                    1'b0, // shared credit avail
                                    1'b0, // shared credit maxed
                                    1'b0, // increment shared credit
                                    1'b0, // decrement shared credit
                                    {PHIT_COUNT_WIDTH{1'bx}},
                                    {FLIT_COUNT_WIDTH{1'bx}},
                                    FALSE,
                                    {PORT_WIDTH{1'bx}},
                                    1'bx,
                                    FALSE,
                                    // used mem
                                    FALSE,
                                    {PORT_WIDTH{1'bx}},
                                    {FLIT_COUNT_WIDTH{1'bx}}}; 
        end
        else begin
            grant_state_ff       <= grant_state_nxt;
        end
    end

    ////////////////////////////////////////////////////////
    // Pipelined muxes to the output port
    ////////////////////////////////////////////////////////
    
    wire [NUM_PORTS-1:0] mux_valid_net;

    generate
        for(i=0; i < NUM_PORTS; i=i+1) begin : gen_mux_valid
            assign mux_valid_net[i] = input_valid_in[i] & (input_ifc_in[i].dst_port == PORT_NUM);
        end
    endgenerate

    SwitchInterface         mux_out_piped_net;
    wire                    mux_out_valid_piped_net;

    OutputMux
    #(
        .N(NUM_PORTS),
        .WIDTH($bits(SwitchInterface))
    )
    OutputMuxInst
    (
        .CLK                (clk),
        .RST_N              (~rst),
        .data_in            (input_ifc_in),
        .valid_in           (mux_valid_net),
        .data_out           (mux_out_piped_net),
        .valid_out          (mux_out_valid_piped_net)
    );

    logic                   outQ_empty_net;
    SwitchInterface         output_ifc_net;

    //wire [$clog2(8*PHITS_PER_FLIT):0] outQ_wrused_net;
    wire [7:0] outQ_wrused_net;

    always@(posedge clk) begin
        if(rst) input_stall_out <= FALSE;
        else          input_stall_out <= (outQ_wrused_net > 16);
    end
 
    FIFO
    #(
        .LOG_DEPTH      (7),
        .WIDTH          ($bits(output_ifc_out)),
        .USE_LUTRAM     (1'b1)
    )
    OutputQ
    (
        .clock          (clk),
        .reset_n        (~rst),

        .wrreq          (mux_out_valid_piped_net),
        .data           (mux_out_piped_net),
        .full           (),
        .almost_full    (),
        .usedw          (outQ_wrused_net),

        .rdreq          (output_valid_out),
        .empty          (outQ_empty_net),
        .almost_empty   (),
        .q              (output_ifc_out)
    );

    assign output_valid_out = ~outQ_empty_net & ~output_stall_in;    

endmodule