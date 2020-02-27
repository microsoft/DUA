///////////////////////////////////////////////////////////////
//
// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.
//
////////////////////////////////////////////////////////////////

import SiliconNetTypes::*;

module InputUnit
#(
    parameter NUM_PORTS,
              PORT_NUM,
              NUM_FLITS,
              FLITS_PER_MESSAGE,
              PHIT_WIDTH,
              FLIT_WIDTH,
              USE_LUTRAM
)
(    
    input                                 clk,
    input                                 rst,

    // Input port
    input SwitchInterface                 input_ifc_in,
    input                                 input_valid_in,

    // Credits from upstream
    output SwitchCredit                   credit_out,
    input                                 credack_in,

    // Intermediate
    output SwitchInterface                output_ifc_out,
    output logic                          output_valid_out,
    input  wire [NUM_PORTS-1:0]           output_stall_in,

    // Raise-Grant
    output SwitchRaise                    raise_out,
    input  SwitchGrant                    grant_in,

    // After-reset synchronization
    output wire                           sync_out
);

    localparam PHITS_PER_FLIT     = FLIT_WIDTH / PHIT_WIDTH;
    localparam PHIT_COUNT_WIDTH   = $clog2(PHITS_PER_FLIT + 1);
    localparam PHIT_ADDR          = $clog2(PHITS_PER_FLIT * NUM_FLITS);
    localparam FLIT_ADDR          = $clog2(NUM_FLITS);
    localparam PORT_WIDTH         = $clog2(NUM_PORTS);
    localparam FLIT_COUNT_WIDTH   = $clog2(FLITS_PER_MESSAGE + 1);
    localparam LOG_PHITS_PER_FLIT = $clog2(PHITS_PER_FLIT);
    localparam WAIT_CYCLES        = (PHITS_PER_FLIT < 4) ? 0 : (PHITS_PER_FLIT-4);

    localparam TRUE               = 1'b1;
    localparam FALSE              = 1'b0;
  
    ////////////////////////////////////////////////////////////////
    // The Unified Buffer stores all the flits for all the Ports.
    ////////////////////////////////////////////////////////////////
    
    logic [PHIT_ADDR-1:0]       input_addr_net;
    logic [PHIT_WIDTH-1:0]      input_data_net;
    logic [PHIT_ADDR-1:0]       output_addr_net;
    
    //replacing mram_dual with mram
    mram
    #(
        .DATA_WIDTH     ($bits(SwitchInterface)), // subtract 1 for unused valid bit
        .ADDR_WIDTH     (PHIT_ADDR)
    )
    UnifiedBuffer
    (        
        .clk            (clk),

        // Write Port
        .data_a         (input_ifc_in),
        .we_a           (input_valid_in),
        .addr_a         (input_addr_net),
        .q_a            (),

        // Read Port
        .data_b         ({($bits(SwitchInterface)){1'bx}}),
        .addr_b         (output_addr_net),
        .we_b           (1'b0),
        .q_b            (output_ifc_out)
    );


    ////////////////////////////////////////////////////////////////
    // The Freelist maintains a list of flit addresses that can
    // be popped off for use when flits arrive.
    //
    // It should never be allowed to over- or under-flow.
    ////////////////////////////////////////////////////////////////
 
    wire [FLIT_ADDR-1:0]        free_addr_net;
    reg                         free_rden_net;
    reg  [FLIT_ADDR-1:0]        free_data_net;
    reg                         free_wren_net;
    wire                        free_initd;

    Freelist
    #(
        .MAX_COUNT      (NUM_FLITS),
        .DATA_WIDTH     (FLIT_ADDR)
    ) 
    FreeListInst
    (
        .rst            (rst),

        // We restore flit addresses on the output clock
        .write_clk      (clk),
        .wren_in        (free_wren_net),
        .data_in        (free_data_net),

        // We borrow flit addresses on the input clock
        .read_clk       (clk),
        .data_out       (free_addr_net),
        .valid_out      (),
        .rden_in        (free_rden_net),
        .initd_out      (free_initd),

        .dbg_overflow   (),
        .dbg_underflow  ()
    );

    ////////////////////////////////////////////////////////////////
    // The CreditQ flows credits back to the sender
    //////////////////////////////////////////////////////////////// 

    reg                     creditQ_wren_net;
    reg  [PORT_WIDTH-1:0]   creditQ_data_net;
    wire [PORT_WIDTH-1:0]   creditQ_q_net;
    wire                    creditQ_empty_net;

    FIFO
    #(
        .LOG_DEPTH      ($clog2(NUM_FLITS)),
        .WIDTH          (PORT_WIDTH),
        .USE_LUTRAM     (1'b1)
    )
    CreditQ
    (
        .clock          (clk),
        .reset_n        (~rst),

        .wrreq          (creditQ_wren_net),
        .data           (creditQ_data_net),
        .full           (),
        .almost_full    (),
        .usedw          (),

        .rdreq          (credack_in & ~creditQ_empty_net),
        .empty          (creditQ_empty_net),
        .almost_empty   (),
        .q              (creditQ_q_net)
    );

    //
    // The following initialization logic populates the upstream sender with credits.
    // 
    logic [$clog2(NUM_FLITS):0]                init_credit_count_ff;
    logic [PORT_WIDTH:0]                        init_port_ff;
    logic                                       free_initd_cred;
    logic                                       input_rst_cred;

    sync_regs#(.WIDTH(1)) initdsync(.clk(clk),.din(free_initd),.dout(free_initd_cred));
    sync_regs#(.WIDTH(1)) crrstsync(.clk(clk),.din(rst),.dout(input_rst_cred));

    always@(posedge clk) begin
        if(input_rst_cred) begin
            init_credit_count_ff    <= 0;
            init_port_ff            <= 0;
        end 
        else begin
            if((init_credit_count_ff != NUM_FLITS) & credack_in) begin
                init_credit_count_ff    <= init_credit_count_ff + 1'b1;
                init_port_ff            <= init_port_ff + 1'b1;
            end
        end
    end

    // Return credit (credit clock domain)
    assign credit_out.valid = free_initd_cred & (~creditQ_empty_net | (init_credit_count_ff != NUM_FLITS));
    assign credit_out.port  = ~creditQ_empty_net ? creditQ_q_net : init_port_ff;

    ////////////////////////////////////////////////////////////////
    // The CrosserQ allows the input state machine to 
    // update the OrderQ in the output clock domain.
    ////////////////////////////////////////////////////////////////

    // Input clock domain
    reg                         crossQ_wren_net;

    // Output clock domain
    wire                        crossQ_empty_net;
    wire                        crossQ_rdreq_net;

    // Data passed from crossQ to orderQ
    struct packed {
        logic                            first;
        logic                            last;
        logic                            msg_last;
        logic [PHIT_COUNT_WIDTH-1:0]     num_phits;
        logic [FLIT_ADDR-1:0]            flitaddr;
        logic [PORT_WIDTH-1:0]           dst_port;
    } crossQ_in, crossQ_out, orderQ_out;

    FIFO
    #(
        .LOG_DEPTH      (FLIT_ADDR),
        .WIDTH          ($bits(crossQ_in)),
        .USE_LUTRAM     (1'b1)
    )
    CrosserQ
    (
        .clock          (clk),
        .reset_n        (~rst),

        .wrreq          (crossQ_wren_net),
        .data           (crossQ_in),
        .full           (),
        .almost_full    (),
        .usedw          (),

        .rdreq          (crossQ_rdreq_net),
        .empty          (crossQ_empty_net),
        .almost_empty   (),
        .q              (crossQ_out)
    );

    ////////////////////////////////////////////////////////////////
    // The OrderQ maintains per-Port head and tail pointers to
    // track per-FIFO occupancy and usage.
    //
    // It runs entirely on the output clock.
    ////////////////////////////////////////////////////////////////

    struct packed {
        logic                        rden;
        logic [PORT_WIDTH-1:0]       rdport;
        logic                        wren;
        logic [PORT_WIDTH-1:0]       wrport;
    } orderQ_ctrl;

    PORTFIFO
    #(
        .NUM_PORTS      (NUM_PORTS),
        .DATA_WIDTH     ($bits(crossQ_in)),
        .FIFO_DEPTH     (FLITS_PER_MESSAGE)
    )
    OrderQ
    (
        .clk            (clk),
        .rst            (rst),

        .wrport_in      (orderQ_ctrl.wrport),
        .wrreq_in       (orderQ_ctrl.wren),
        .data_in        (crossQ_out),

        .rdport_in      (orderQ_ctrl.rdport),
        .rdreq_in       (orderQ_ctrl.rden),
        .q_out          (orderQ_out)
    );

    assign crossQ_rdreq_net = orderQ_ctrl.wren;
    
    ///////////////////////////////////////////////////////////////
    // Round-Robin Arbiter Implemented as a FIFO
    ///////////////////////////////////////////////////////////////

    struct packed 
    {
        logic                   wren;
        Port                    dst_port;
    } arb_write;

    struct packed
    {
        logic                   rden;
        logic                   empty;
        logic [PORT_WIDTH:0]    used;
        Port                    dst_port;
    } arb_read;

    FIFOFast
    #(
        .LOG_DEPTH      (PORT_WIDTH),
        .WIDTH          (PORT_WIDTH)
    )
    RoundRobinArbiterQ
    (
        .clock          (clk),
        .reset_n        (~rst),
        
        .wrreq          (arb_write.wren),
        .data           ({arb_write.dst_port}),
        .full           (),
        .almost_full    (),
        .usedw          (arb_read.used),

        .rdreq          (arb_read.rden),
        .empty          (arb_read.empty),
        .almost_empty   (),
        .q              ({arb_read.dst_port})
    );

    ///////////////////////////////////////////////////////////////
    // Per-Port locks
    ///////////////////////////////////////////////////////////////
 
    struct packed {
        logic                           wren;
        // address 
        logic [PORT_WIDTH-1:0]          dst_port;
        // data
        logic                           valid;
    } lock_write;

    struct packed {
        // address 
        logic [PORT_WIDTH-1:0]          dst_port;
        // data
        logic                           valid;
    } lock_read;

    lutram_dual
    #(
        .WIDTH                  (1),
        .DEPTH                  (NUM_PORTS)
    )
    PortLockRAM
    (
        .CLK                    (clk),
        .CLR                    (rst),
        .wen                    (lock_write.wren),
        .waddr                  (lock_write.dst_port),
        .din                    (lock_write.valid),
        .raddr_0                (lock_read.dst_port),
        .dout_0                 (lock_read.valid),
        .raddr_1                (),
        .dout_1                 ()
    );

    ///////////////////////////////////////////////////////////////
    // The Head LUTRAM maintains the latest head entry of the 
    // orderQ for each Port. It spares us an extra read cycle.
    ///////////////////////////////////////////////////////////////
 
    // RAM Control
    struct packed {
        // RAM address and control
        logic                           wren;
        logic [PORT_WIDTH-1:0]          wraddr;
        logic [PORT_WIDTH-1:0]          rdaddr;
        logic [PORT_WIDTH-1:0]          rdaddr_1;

        // RAM write data
        logic [FLIT_ADDR-1:0]           flit_addr;
        logic [PHIT_COUNT_WIDTH-1:0]    num_phits;
        logic                           first;
        logic                           last;
    } hram_ctrl;

    // RAM Outputs
    struct packed {
        // RAM read data
        logic [FLIT_ADDR-1:0]        flit_addr;
        logic [PHIT_COUNT_WIDTH-1:0] num_phits;
        logic                        first;
        logic                        last;
    } hram_net, hram_net_1;

    lutram_dual
    #(
        .WIDTH                  ($bits(hram_net)),
        .DEPTH                  (NUM_PORTS)
    )
    HeadRam
    (
        .CLK                    (clk),
        .CLR                    (rst),
        .wen                    (hram_ctrl.wren),
        .waddr                  (hram_ctrl.wraddr),
        .din                    ({hram_ctrl.flit_addr,hram_ctrl.num_phits,hram_ctrl.first,hram_ctrl.last}),

        .raddr_0                (hram_ctrl.rdaddr),
        .dout_0                 (hram_net),
        .raddr_1                (hram_ctrl.rdaddr_1),
        .dout_1                 (hram_net_1)
    );

    ///////////////////////////////////////////////////////////////
    // The 'DST' LUTRAM Tracks Port Destination per Port.
    ///////////////////////////////////////////////////////////////
    
    // RAM Control
    struct packed {
        logic                   wren;
        logic [PORT_WIDTH-1:0]  wraddr;
        logic [PORT_WIDTH-1:0]  dst_port;
        logic [PORT_WIDTH-1:0]  rdaddr;
    } dst_ctrl;

    // RAM Outputs
    wire [PORT_WIDTH-1:0]       dst_net;

    lutram_dual
    #(
        .WIDTH                  (PORT_WIDTH),
        .DEPTH                  (NUM_PORTS)
    )
    DestRAM
    (
        .CLK                    (clk),
        .CLR                    (rst),
        .wen                    (dst_ctrl.wren),
        .waddr                  (dst_ctrl.wraddr),
        .din                    (dst_ctrl.dst_port),

        .raddr_0                (dst_ctrl.rdaddr),
        .dout_0                 (dst_net),
        .raddr_1                (),
        .dout_1                 ()
    );

    ///////////////////////////////////////////////////////////////
    // The 'used' LUTRAM tracks total number of flits per Port.
    ///////////////////////////////////////////////////////////////
    
    struct packed {
        logic                           wren;
        logic [PORT_WIDTH-1:0]          wraddr;
        logic [FLIT_COUNT_WIDTH-1:0]    used;
        logic [PORT_WIDTH-1:0]          rdaddr;
    } used_ctrl;

    wire [FLIT_COUNT_WIDTH-1:0] used_net;

    lutram_dual
    #(
        .WIDTH                  (FLIT_COUNT_WIDTH),
        .DEPTH                  (NUM_PORTS)
    )
    UsedRAM
    (
        .CLK                    (clk),
        .CLR                    (rst),
        .wen                    (used_ctrl.wren),
        .waddr                  (used_ctrl.wraddr),
        .din                    (used_ctrl.used),

        .raddr_0                (used_ctrl.rdaddr),
        .dout_0                 (used_net),
        .raddr_1                (),
        .dout_1                 ()
    ); 

    ///////////////////////////////////////////////////////////////
    // States for the Marshaling FSM
    ///////////////////////////////////////////////////////////////
    
    struct packed {
        logic                           busy;
        logic [PHIT_COUNT_WIDTH-1:0]    num_phits;
        logic [PHIT_COUNT_WIDTH-2:0]    phit_num;
        logic [FLIT_ADDR-1:0]           flit_addr;
        logic                           first;
        logic [PORT_WIDTH-1:0]          dst_port;
    } marshal_ff, marshal_nxt;

    /////////////////////////////////////////////////////////
    // Next-state logic for Registered Outputs
    /////////////////////////////////////////////////////////
 
    // Output States
    typedef enum logic [2:0]
    {
        kSync       = 3'd0,
        kArb        = 3'd1,
        kGrantWait  = 3'd2,
        kGrant      = 3'd3,
        kUpdateHead = 3'd4,
        kSendData   = 3'd5
    } RaiseState;
 
    logic                               output_wren_nxt;

    struct packed {
        RaiseState                      fsm;
        logic [PORT_WIDTH-1:0]          dst_port; // which port we are waiting on
        logic                           update_hram;
        logic [PHIT_COUNT_WIDTH-1:0]    phit_count;
        logic [FLIT_COUNT_WIDTH-1:0]    used_prefetch;
        logic [PHIT_ADDR-1:0]           output_addr_net_tmp;
    } raise_state_nxt, raise_state_ff;

    integer i;

    SwitchRaise    raise_out_nxt;

    // The sync counter must NEVER be reset after the FPGA is programmed.
    // This is used to force the input and output units to synchronize
    // even after the output unit is independently reset

    reg [3:0] sync_count_ff = 4'd0;
    logic [NUM_PORTS-1:0] in_arb_ff, in_arb_nxt;
    logic [NUM_PORTS-1:0] msg_last_ff, msg_last_nxt;  

    always@(posedge clk) begin
        sync_count_ff <= sync_count_ff + 1'b1;
    end

    assign sync_out = (raise_state_ff.fsm == kArb);

    always_comb begin

        // OrderQ control signal
        orderQ_ctrl             = '{FALSE,{PORT_WIDTH{1'bx}},FALSE,{PORT_WIDTH{1'bx}}};

        // Registered and Comb Outputs 
        output_wren_nxt         = FALSE;

        // Address Input to Shared Buffer
        output_addr_net         = {FLIT_ADDR{1'bx}};

        // Data transfer FSM
        marshal_nxt             = marshal_ff;
        
        // Arbiter control
        arb_read.rden           = FALSE;
        arb_write.wren          = FALSE;
        arb_write.dst_port        = {PORT_WIDTH{1'bx}};

        // Freelist return signals
        free_data_net           = {FLIT_ADDR{1'bx}};
        free_wren_net           = FALSE;

        // Credit return signals
        creditQ_wren_net        = FALSE;
        creditQ_data_net        = FALSE;

        // LUTRAMs
        hram_ctrl               = '{FALSE,{PORT_WIDTH{1'bx}},{PORT_WIDTH{1'bx}},{PORT_WIDTH{1'bx}},{FLIT_ADDR{1'bx}},{PHIT_COUNT_WIDTH{1'bx}},1'bx,1'bx};
        dst_ctrl                = '{FALSE,{PORT_WIDTH{1'bx}},{PORT_WIDTH{1'bx}},{PORT_WIDTH{1'bx}}};
        used_ctrl               = '{FALSE,{PORT_WIDTH{1'bx}},{FLIT_COUNT_WIDTH{1'bx}},{PORT_WIDTH{1'bx}}};


        // Default
        raise_state_nxt         = raise_state_ff;

        // Raise
        raise_out_nxt           = raise_out;

        // PORT Locking
        lock_write.wren         = FALSE;
        lock_write.dst_port     = {PORT_WIDTH{1'bx}};
        lock_write.valid        = 1'bx;
        lock_read.dst_port      = {PORT_WIDTH{1'bx}};
        
        in_arb_nxt = in_arb_ff;
        msg_last_nxt = msg_last_ff;

        case(raise_state_ff.fsm)

            kSync: begin
                if(sync_count_ff == {4{1'b1}}) begin
                    raise_state_nxt.fsm = kArb;
                end
            end

            ////////////////////////////////////////////////////////////////////////////////////
            // Two processes happen in this cycle: (1) handle injections, (2) update arbiter
            ////////////////////////////////////////////////////////////////////////////////////
            
            kArb: begin

                // A non-empty crossQ indicates the arrival
                // of a new flit. 
                
                if(~crossQ_empty_net) begin

                    // We first copy the crossQ contents
                    // into the orderQ, which stores the 
                    // allocated flit address order
                    orderQ_ctrl.wren          = TRUE; // Store the allocated address for this flit
                    orderQ_ctrl.wrport        = crossQ_out.dst_port;

                    // On an insertion, it is possible that we were not
                    // the first flit to arrive for this Port
                    // We first check the 'used' lutram, which tells
                    // us how many flits are queued up on this Port.
                    //
                    // The 'head' RAM is a lutram that stores
                    // the head of the orderQ per Port.  This is an optimization
                    // that avoids the extra cycle of having to read from
                    // the synchronous Order Q.
                    used_ctrl.rdaddr          = crossQ_out.dst_port;

                    // When 'used' is zero, we assume the head position
                    // in the queue. This requires updating the head ram
                    // immediately with the head of 'cross Q'
                    //
                    // The important information we save are:
                    // (1) flit address
                    // (2) number of valid phits in this flit
                    // (3) whether this is the head phit of the packet stream
                    if(used_net == 1'b0) begin


                        // We also update the head RAM
                        hram_ctrl.wren        = TRUE;
                        hram_ctrl.wraddr      = crossQ_out.dst_port;
                        hram_ctrl.flit_addr   = crossQ_out.flitaddr;
                        hram_ctrl.num_phits   = crossQ_out.num_phits;
                        hram_ctrl.first       = crossQ_out.first;
                        hram_ctrl.last        = crossQ_out.last;
                        
                        // It's a hram property, insesrt it hram write appears
                        // only when we want to send it this cycle we can insert this.
                        msg_last_nxt[crossQ_out.dst_port] = crossQ_out.msg_last;

                        // If this is a head flit, set
                        // the destination port
                        if(crossQ_out.first == TRUE) begin 
                        // QQ note: crossQ_out.first is from input_ifc.first, which indicates the first phit of a logical message
                            dst_ctrl.wren     = TRUE;
                            dst_ctrl.wraddr   = crossQ_out.dst_port;
                            dst_ctrl.dst_port = crossQ_out.dst_port;
                        end
                        
                        
                    end
                    
                    if (crossQ_out.msg_last && ~in_arb_ff[crossQ_out.dst_port]) begin
                        // On an insertion, we enqueue to the arbiter FIFO
                        in_arb_nxt[crossQ_out.dst_port] = TRUE;
                        // msg_last_nxt[crossQ_out.dst_port] = crossQ_out.msg_last;
                        
                        arb_write.wren        = TRUE;
                        arb_write.dst_port    = crossQ_out.dst_port;
                    end
  
                    // Increment the 'used' count by 1 flit
                    // Note: 'used' write commands are 1-cycle delayed
                    used_ctrl.wren   = TRUE;
                    used_ctrl.wraddr = crossQ_out.dst_port;
                    used_ctrl.used   = used_net + 1'b1;
                end
 
                // If the arbiter has something to present, raise it!
                if(~arb_read.empty) begin
                    hram_ctrl.rdaddr_1  = arb_read.dst_port;
                    dst_ctrl.rdaddr     = arb_read.dst_port;
                    lock_read.dst_port  = dst_net;

                    if(~output_stall_in[dst_net] & (~lock_read.valid | (lock_read.valid & (lock_read.dst_port == arb_read.dst_port)))) begin    
                        // Send out raise requests to output units
                        raise_out_nxt.valid    = TRUE;
                        raise_out_nxt.dst_port = dst_net;
                        raise_out_nxt.last     = hram_net_1.last;
                        raise_out_nxt.msg_last = msg_last_ff[arb_read.dst_port];
                        raise_out_nxt.dst_port_one_hot[dst_net] = 1'b1;
                    end
                end

                // Move to the next state
                raise_state_nxt.fsm = kGrantWait;
            end

            kGrantWait: begin

                // Clear the raise
                raise_out_nxt.valid = 1'b0;
                raise_out_nxt.dst_port_one_hot = {NUM_PORTS{1'b0}};

                raise_state_nxt.fsm            = kGrant;
                used_ctrl.rdaddr               = raise_out.dst_port;
                raise_state_nxt.used_prefetch  = used_net;
                // merged from
                hram_ctrl.rdaddr               = raise_out.dst_port;
                raise_state_nxt.output_addr_net_tmp = {hram_net.flit_addr, {(PHIT_COUNT_WIDTH-1){1'b0}}};
                // merge end
            end
  
    
            ////////////////////////////////////////////////////////////////////////////////////
            // Monitor for valid grant signals.
            // Our job is to monitor any pending matches returned from the output unit. 
            ////////////////////////////////////////////////////////////////////////////////////
            
            kGrant: begin

                // Clear the raise
                raise_out_nxt = '{FALSE,{PORT_WIDTH{1'bx}},{NUM_PORTS{1'b0}},1'bx,1'bx};

                if(grant_in.valid) begin

                    // Combinational read of LUTRAMs
                    hram_ctrl.rdaddr          = raise_out.dst_port;

                    // Start up the FSM responsible for marshalling data
                    marshal_nxt.busy          = TRUE;
                    marshal_nxt.num_phits     = hram_net.num_phits;
                    marshal_nxt.phit_num      = 1'b1;
                    marshal_nxt.flit_addr     = hram_net.flit_addr;
                    marshal_nxt.first         = hram_net.first;
                    marshal_nxt.dst_port      = raise_out.dst_port;

                    // Read the first phit out of Unified Buffer (available next cycle)
					output_addr_net           = raise_state_ff.output_addr_net_tmp;

                    // Assert readiness of data on next clock
                    output_wren_nxt           = TRUE;

                    // Pop head of the order Q
                    orderQ_ctrl.rden          = TRUE; // this will immediately prefetch data for next cycle assuming Port doesn't change
                    orderQ_ctrl.rdport        = raise_out.dst_port;


                    // We are the last flit for this Port
                    if(raise_state_ff.used_prefetch == 1'b1) begin
                        // Take us off the Arbiter round-robin queue
                        arb_read.rden                  = TRUE;
                        raise_state_nxt.update_hram    = FALSE;
                        in_arb_nxt[raise_out.dst_port] = FALSE;
                    end
                    // If 'used' > 1, then we should prefetch the control
                    // information for the next flit of this Port
                    // into the 'head' RAM
                    else begin
                        raise_state_nxt.update_hram  = TRUE;
                        raise_state_nxt.dst_port     = raise_out.dst_port;
                    end

                    // Decrement 'used' for this Port
                    used_ctrl.rdaddr          = raise_out.dst_port;
                    used_ctrl.wren            = TRUE;
                    used_ctrl.wraddr          = raise_out.dst_port;
                    used_ctrl.used            = raise_state_ff.used_prefetch - 1'b1;

                    // Return flit address to the freelist
                    free_wren_net             = TRUE;
                    free_data_net             = hram_net.flit_addr;

                    // Lock or unlock
                    // Note, there is a 1-cycle write delay for timing closure reasons
                    if(hram_net.last) begin
                        lock_write.wren       = TRUE;
                        lock_write.valid      = FALSE;
                        lock_write.dst_port   = raise_out.dst_port; //grant_in.dst_port;
                    end
                    else if(hram_net.first) begin
                        lock_write.wren       = TRUE;
                        lock_write.valid      = TRUE;
                        lock_write.dst_port   = raise_out.dst_port; //grant_in.dst_port;
                    end
                end

                else begin
                    // Use last spare cycle to rotate the arbiter
                    if(~arb_read.empty) begin
                        arb_read.rden      = TRUE;
                        arb_write.wren     = TRUE;
                        arb_write.dst_port = arb_read.dst_port;
                    end  
                end

                raise_state_nxt.fsm = kUpdateHead;
            end


            ////////////////////////////////////////////////////////////////////////////////////
            // Update the head RAM
            ////////////////////////////////////////////////////////////////////////////////////
            
            kUpdateHead: begin

                if(raise_state_ff.update_hram) begin
                    // Determine which Port in orderQ we are reading
                    orderQ_ctrl.rdport      = raise_state_ff.dst_port;

                    // Update the head ram
                    hram_ctrl.wren        = TRUE;
                    hram_ctrl.wraddr      = raise_state_ff.dst_port;
                    hram_ctrl.flit_addr   = orderQ_out.flitaddr;
                    hram_ctrl.num_phits   = orderQ_out.num_phits;
                    hram_ctrl.first       = orderQ_out.first;
                    hram_ctrl.last        = orderQ_out.last;
                    
                    msg_last_nxt[orderQ_out.dst_port] = orderQ_out.msg_last;

                    if(orderQ_out.first) begin
                        dst_ctrl.wren     = TRUE;
                        dst_ctrl.wraddr   = raise_state_ff.dst_port;
                        dst_ctrl.dst_port = orderQ_out.dst_port;
                    end
                end

                // Introduce wait cycles for data before we re-arbitrate
                raise_state_nxt.fsm        = kSendData;
                raise_state_nxt.phit_count = WAIT_CYCLES[PHIT_COUNT_WIDTH-1:0]; // subtract 4 for overlapped data transfer cycles, and overlapping arbitration with last word of data

                if(raise_state_nxt.phit_count == 1'b0) begin
                    raise_state_nxt.fsm = kArb;
                end

                raise_state_nxt.update_hram = FALSE;

            end

            ////////////////////////////////////////////////////////////////////////////////////
            // Extra wait for long flits
            ////////////////////////////////////////////////////////////////////////////////////
            
            kSendData: begin
                raise_state_nxt.phit_count = raise_state_ff.phit_count - 1'b1;
                if(raise_state_ff.phit_count == 1'b1) begin
                    raise_state_nxt.fsm = kArb;
                end
            end
 
        endcase


        /////////////////////////////////////////////////////////
        // A parallel FSM for marshaling flits to the output
        // unit after a grant was given.
        //
        // When the marshalling FSM finishes, it then sends
        // the grant ack (GRACK) directly to the output unit.
        /////////////////////////////////////////////////////////
        
        if(marshal_ff.busy) begin
            output_addr_net      = {marshal_ff.flit_addr, marshal_ff.phit_num};
            output_wren_nxt      = TRUE;
            marshal_nxt.phit_num = marshal_ff.phit_num + 1'b1;
            if(marshal_ff.phit_num == (PHITS_PER_FLIT-1)) begin
                marshal_nxt.busy = FALSE;
                // Send return credit back to source
                creditQ_wren_net = TRUE;
                creditQ_data_net = marshal_ff.dst_port;
            end
        end

    end
    
    always@(posedge clk) begin
        if(rst) begin
            output_valid_out        <= FALSE;
            marshal_ff              <= '{FALSE,{PHIT_COUNT_WIDTH{1'bx}},{(PHIT_COUNT_WIDTH-1){1'bx}},{FLIT_ADDR{1'bx}},1'bx,{NUM_PORTS{1'bx}}};
            raise_state_ff          <= {kSync,{PORT_WIDTH{1'bx}},FALSE,{PHIT_COUNT_WIDTH{1'bx}}, {FLIT_COUNT_WIDTH{1'bx}}, {PHIT_ADDR{1'bx}}};
            raise_out               <= '{FALSE,{PORT_WIDTH{1'bx}},{NUM_PORTS{1'b0}},1'bx,1'bx};
            in_arb_ff               <= 0;
            msg_last_ff             <= 0;
        end
        else begin
            output_valid_out        <= output_wren_nxt;
            marshal_ff              <= marshal_nxt;
            raise_state_ff          <= raise_state_nxt;
            raise_out               <= raise_out_nxt;
            in_arb_ff               <= in_arb_nxt;
            msg_last_ff             <= msg_last_nxt;
        end
    end

    ///////////////////////////////////////////////////////////////
    // The Input FSM handles writing of flits into the
    // unified input buffer and is responsible for updating
    // the OrderQ that tracks per-Port queue occupancy.
    //
    // We also store the routing decision here.
    ///////////////////////////////////////////////////////////////
    
    // Input States
    typedef enum logic [1:0]
    {
        kInputIdle  = 2'd0,
        kInputBusy  = 2'd1
    } InputState;
 
    struct packed {
        InputState                    fsm;
        logic [PHIT_COUNT_WIDTH-1:0]  phit_num; // phit count
        logic                         first;
        logic                         last;
        logic                         msg_last;
    } istate_ff, istate_nxt;

    assign input_addr_net     = {free_addr_net, istate_ff.phit_num[PHIT_COUNT_WIDTH-2:0]}; // construct the input address from the head of the freelist

    integer j; 
    always_comb begin
        istate_nxt       = istate_ff;
        free_rden_net    = FALSE;
        crossQ_in        = '{FALSE,FALSE,FALSE,{PHIT_COUNT_WIDTH{1'bx}},{FLIT_ADDR{1'bx}},{PORT_WIDTH{1'bx}}};
        crossQ_wren_net  = FALSE;
       
        case(istate_ff.fsm)
            kInputIdle: begin
                if(input_valid_in) begin
                    istate_nxt.fsm       = kInputBusy;
                    istate_nxt.phit_num  = 1'b1;
                    istate_nxt.first     = input_ifc_in.first;
                    istate_nxt.last      = input_ifc_in.last;
                    istate_nxt.msg_last  = input_ifc_in.msg_last;
                end
            end

            kInputBusy: begin
                if(input_valid_in) begin
                    istate_nxt.phit_num  = istate_ff.phit_num + 1'b1;
                    istate_nxt.last      = istate_ff.last | input_ifc_in.last;
                    istate_nxt.msg_last  = istate_ff.msg_last | input_ifc_in.msg_last;

                    // We are transmitting the last phit
                    if(istate_ff.phit_num == (PHITS_PER_FLIT-1)) begin
                        free_rden_net       = TRUE;
                        crossQ_in           = '{istate_ff.first,
                                                istate_nxt.last,
                                                istate_nxt.msg_last,
                                                istate_ff.phit_num,
                                                free_addr_net,
                                                input_ifc_in.dst_port};
                        crossQ_wren_net     = TRUE;
                        istate_nxt.fsm      = kInputIdle;
                        istate_nxt.phit_num = 1'b0;
                    end
                end
            end
        endcase
    end

    always@(posedge clk) begin
        if(rst) begin
            istate_ff.fsm       <= kInputIdle;
            istate_ff.phit_num  <= {PHIT_COUNT_WIDTH{1'b0}};
            istate_ff.first     <= FALSE;
            istate_ff.last      <= FALSE;
            istate_ff.msg_last  <= FALSE;
        end
        else begin
            istate_ff           <= istate_nxt;
        end
    end 

endmodule 