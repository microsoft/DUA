///////////////////////////////////////////////////////////////
//
// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.
//
////////////////////////////////////////////////////////////////

module Arbiter_v2 
    #(
        parameter N = 4
    )
    (
        input   wire          clk,
        input   wire          rst,
        input   wire          stall,
        input   wire  [N-1:0] raises,
        output  reg   [N-1:0] grant,
        output  reg           valid
    );

    function [1:0] gen_grant_carry;
        input c;    //whether no-one has been granted.
        input r;
        input p;    //whether I was granted before.
        begin
            gen_grant_carry[1] = (~r & c) | p;
            gen_grant_carry[0] = r & c;
        end
    endfunction

    reg [N-1:0] prior;
    reg [N-1:0] grantA;
    reg [N-1:0] grantB;
    reg carry;
    reg [1:0] grantC;

    integer i;

    always @(*) begin
        valid = 1'b0;
        grant = 0;
        carry = 0;

        // Arbiter 1
        for(i=0; i < N; i=i+1) begin
            grantC      = gen_grant_carry(carry, raises[i], prior[i]);
            grantA[i]   = grantC[0];
            carry       = grantC[1];
        end

        // Arbiter 2 - shares carry from 1, redoes all positions, ignores previous grant.
        for(i=0; i < N; i=i+1) begin
            grantC      = gen_grant_carry(carry, raises[i], 0);
            grantB[i]   = grantC[0];
            carry       = grantC[1];
        end

        for(i=0; i < N; i=i+1) begin
            grant[i]    = grantA[i] | grantB[i];
            valid       = valid | grant[i];
        end
    end

    always@(posedge clk) begin
        if (rst) begin
            prior <= 1;
        end
        else if (stall | ~valid) begin
            prior <= prior;
        end
        else begin
            prior <= grant; // Remember who I granted, so I can pick next in round-robin order.
        end
    end

endmodule
