///////////////////////////////////////////////////////////////
//
// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.
//
////////////////////////////////////////////////////////////////

package SiliconNetTypes;

import NetworkTypes::Phit;
import NetworkTypes::IP6Address;
import NetworkTypes::IP4Address;

//external use
parameter SN_DATA_WIDTH                          = $bits(Phit);

//for message header
//ipv4 length
parameter SN_DEVID_WIDTH                         = 16;
parameter SN_LENGTH_WIDTH                        = 16;
parameter SN_FLAG_WIDTH                          = 8;
parameter SN_SEQNUM_WIDTH                        = 32;

//for request
parameter SN_TYPE_WIDTH                          = 8;
parameter SN_PARAM_WIDTH                         = 96;

//for specific request parameters
parameter SN_ADDR_WIDTH                          = 64;

//max supported message length
parameter SN_MAX_MSG_LENGTH                      = 128; // limited by max msg length=4kB

//configuration reg addr
parameter SN_CTL_REG_WRITE_KEY_ADDR              = 16'h105;
parameter SN_CTL_REG_WRITE_MSK_ADDR              = 16'h104;
parameter SN_CTL_REG_READ_KEY_ADDR               = 16'h103;
parameter SN_CTL_REG_READ_MSK_ADDR               = 16'h102;
parameter SN_CTL_REG_READ_EP_ADDR                = 16'h101;
parameter SN_CTL_REG_ADDR                        = 16'h100;

//connector debugging reg addr
parameter SN_CTL_REG_COUNTER_VALUE_ADDR          = 16'h110;

parameter SN_NUM_PORTS                           = 8;
parameter SN_NUM_VCS                             = 4;
parameter SN_PHIT_WIDTH                          = $bits(Phit);
`ifdef DV_PHIT_SIZE_256b_FLIT_SIZE_256B
    parameter SN_FLIT_WIDTH                      = SN_PHIT_WIDTH * 8;
`elsif DV_PHIT_SIZE_512b_FLIT_SIZE_512B 
    parameter SN_FLIT_WIDTH                      = SN_PHIT_WIDTH * 8;
`elsif DV_PHIT_SIZE_512b_FLIT_SIZE_256B
    parameter SN_FLIT_WIDTH                      = SN_PHIT_WIDTH * 4; // the optimal number for LTL.
`else // PHIT SIZE=256b, FLIT_SIZE = 128B (default)
    parameter SN_FLIT_WIDTH                      = SN_PHIT_WIDTH * 4; // the optimal number for LTL.
`endif

parameter SN_FLITS_PER_PORT                      = 32'd64;
parameter SN_NUM_FLITS                           = SN_FLITS_PER_PORT*SN_NUM_PORTS;
parameter SN_FLITS_PER_MESSAGE                   = SN_FLITS_PER_PORT;
parameter SN_FLITS_PER_PORT_DOWNSTREAM           = 32'd32;
parameter SN_MAX_CREDIT_WIDTH                    = 32;

// Optimization/debug/status
parameter SN_DISABLE_UTURN                       = 0;
parameter SN_USE_LUTRAM                          = 0;

// Derived types
parameter SN_PORT_WIDTH                          = $clog2(SN_NUM_PORTS);
parameter SN_PAD_WIDTH                           = $clog2(SN_PHIT_WIDTH/8);
parameter SN_VC_WIDTH                            = (SN_NUM_VCS==1) ? 1 : $clog2(SN_NUM_VCS);

typedef logic [SN_VC_WIDTH-1:0]       VC;
typedef logic [SN_PHIT_WIDTH-1:0]     Data;
typedef logic [SN_PORT_WIDTH-1:0]     Port;
typedef logic [SN_PAD_WIDTH-1:0]      PadBytes;

//internal use
typedef enum logic [SN_TYPE_WIDTH-1:0] {
    REQ_IDLE            = 8'hx,
    REQ_SEND            = 8'h01,
    REQ_SEND_CMPL       = 8'h02,
    REQ_RECV            = 8'h03,
    REQ_RECV_CMPL       = 8'h04,
    REQ_WRTE            = 8'h05,
    REQ_WRTE_CMPL       = 8'h06,
    REQ_READ            = 8'h07,
    REQ_READ_CMPL       = 8'h08,
    REQ_FLSH            = 8'h09,
    REQ_FLSH_CMPL       = 8'h0a,
    REQ_COPY            = 8'h0b,
    REQ_COPY_WRTE       = 8'h0c,
    REQ_COPY_CMPL       = 8'h0d,
    REQ_CNFG            = 8'h0e,
    REQ_CNFG_CMPL       = 8'h0f,
    REQ_FWRD            = 8'h10,
    REQ_PUSH            = 8'h11,
    REQ_PUSH_CMPL       = 8'h12,
    REQ_UPDT            = 8'h13
    //REQ_RESERVED      = 8'h40-8'h7f
    //REQ_RESERVED_UIE  = 8'h80-8'hff
} SN_REQ_TYPE;

typedef logic   [SN_DEVID_WIDTH-1:0]           SN_devID;

typedef struct packed 
{
    IP4Address          ipv4;
    SN_devID            devID;   
} UID;
parameter SN_UID_WIDTH                          = $bits(UID);

typedef logic   [SN_LENGTH_WIDTH-1:0]            SN_MSG_LENGTH;
typedef logic   [SN_FLAG_WIDTH-1:0]              SN_MSG_FLAG;
typedef logic   [SN_SEQNUM_WIDTH-1:0]            SN_MSG_SEQNUM;

//REG Parameters

//SENDRECEIVE
typedef struct packed 
{
    logic [ 7:0]    req_flag;
    logic [15:0]    src_port;
    logic [15:0]    dst_port;
    logic [55:0]    reserved;
} SN_REQ_SDRC_PARAM;

//WRITE
typedef struct packed 
{
    logic [ 7:0]    req_flag;
    logic [15:0]    req_length;
    logic [63:0]    dst_addr;
    logic [ 7:0]    reserved;
} SN_REQ_WRTE_PARAM;

//FLUSH
typedef struct packed 
{
    logic [ 7:0]    req_flag;
    logic [87:0]    reserved;
} SN_REQ_FLSH_PARAM;

//READ
typedef struct packed 
{
    logic [ 7:0]    req_flag;
    logic [15:0]    req_length;
    logic [71:0]    reserved;
} SN_REQ_READ_PARAM_SEG1;
typedef struct packed 
{
    logic [63:0]    src_addr;
    logic [63:0]    dst_addr;
    logic [127:0]   reserved;
} SN_REQ_READ_PARAM_SEG2;

//COPY
typedef struct packed 
{
    logic [ 7:0]    req_flag;
    logic [15:0]    req_length;
    logic [47:0]    req_UID;
    logic [23:0]    reserved;
} SN_REQ_COPY_PARAM_SEG1;
typedef struct packed 
{
    logic [63:0]    src_addr;
    logic [63:0]    dst_addr;
    logic [127:0]   reserved;
} SN_REQ_COPY_PARAM_SEG2;

// default
typedef struct packed 
{
    shortint      p5;
    shortint      p4;
    shortint      p3;
    shortint      p2;
    shortint      p1;
    shortint      p0;
} SN_REQ_PARAM;

//Legacy_READ
typedef struct packed 
{
    logic [ 7:0]    req_flag;
    logic [15:0]    req_length;
    logic [63:0]    dst_addr;
    logic [ 7:0]    reserved;
} SN_REQ_LEG_READ_PARAM;

typedef struct packed
{    
    UID                 src_uid;
    UID                 dst_uid;
    SN_MSG_LENGTH       msg_length;
    SN_MSG_FLAG         msg_flag;
    SN_MSG_SEQNUM       msg_seqnum;
    SN_REQ_TYPE         req_type;    
    SN_REQ_PARAM        req_param;
} SiliconNetHead;

typedef struct packed 
{
    shortint    d15;
    shortint    d14;
    shortint    d13;
    shortint    d12;
    shortint    d11;
    shortint    d10;
    shortint    d09;
    shortint    d08;
    shortint    d07;
    shortint    d06;
    shortint    d05;
    shortint    d04;
    shortint    d03;
    shortint    d02;
    shortint    d01;
    shortint    d00;
} SiliconData256;

//SiliconSwitch
typedef struct packed 
{
    VC                  src_vc;
    Port                src_port;
    VC                  dst_vc;
    Port                dst_port;
    Data                data;
    logic               msg_first;
    logic               msg_last;
    logic               first;
    logic               last;
    PadBytes            pad_bytes;
} SwitchInterface;

typedef struct packed
{
    logic               valid;
    Port                port;
} SwitchCredit;

typedef struct packed
{
    logic                       valid;              // valid raise
    Port                        dst_port;           // which destination port we are asking
    logic   [SN_NUM_PORTS-1:0]  dst_port_one_hot;   // which destination port, one hot coding
    logic                       last;               // last phit of a packet
    logic                       msg_last;           // last flit of message
} SwitchRaise;

typedef struct packed
{
    logic               valid;    // valid grant
    Port                src_port; // which source port this grant belongs to
    Port                dst_port; // which output port provided this grant
} SwitchGrant;

endpackage