///////////////////////////////////////////////////////////////
//
// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.
//
////////////////////////////////////////////////////////////////

package NetworkTypes;

typedef struct packed
{
    logic [15:0]    x5;
    logic [15:0]    x4;
    logic [15:0]    x3;
    logic [15:0]    x2;
    logic [15:0]    x1;
    logic [15:0]    x0;
    logic [7:0]     d3;
    logic [7:0]     d2;
    logic [7:0]     d1;
    logic [7:0]     d0;
} IP6Address;

typedef struct packed
{
    logic [7:0]     d3;
    logic [7:0]     d2;
    logic [7:0]     d1;
    logic [7:0]     d0;
} IP4Address;

`ifdef DV_PHIT_SIZE_512b_FLIT_SIZE_256B
   typedef logic [511:0]   Phit;
`elsif DV_PHIT_SIZE_512b_FLIT_SIZE_512B   
   typedef logic [511:0]   Phit;
`else   
  typedef logic [255:0]   Phit;
`endif

endpackage
