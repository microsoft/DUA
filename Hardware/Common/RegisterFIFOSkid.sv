///////////////////////////////////////////////////////////////
//
// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.
//
////////////////////////////////////////////////////////////////

module RegisterFIFOSkid
#(
	parameter WIDTH
)
(
	input  logic 				clock,
	input  logic 				reset_n,

	input  logic 				wrreq,
	input  logic [WIDTH-1:0] 	data,
	output logic 				full,

	input  logic 				rdreq,
	output logic                empty,
	output logic [WIDTH-1:0] 	q
);

	logic 				full_ff = 1'b0;
	logic 				overflow_ff = 1'b0;
	logic 				empty_ff = 1'b1;

	// Extra registers ensure that output signals have no load from internal logic
	// I am duplicating that approach which was in the Altera Synthesis Cookbook
	(*preserve*)logic 	internal_empty_ff = 1'b1;

	logic [WIDTH-1:0]	output_data_ff;
	logic [WIDTH-1:0]	overflow_data_ff;

	always_comb begin
		full  = full_ff;
		q  = output_data_ff;
		empty = empty_ff;
	end

	always_ff @(posedge clock) begin	
		// Sink
		if (rdreq) begin
			full_ff <= 1'b0;	// May get overridden below
			
			if (overflow_ff) begin
				// Overflow has data - send this to output
				overflow_ff <= 1'b0;
				output_data_ff <= overflow_data_ff;
			end
			else begin
				// May get overridden below
				empty_ff <= 1'b1;
				internal_empty_ff <= 1'b1;
			end
		end

		// Source
		if (wrreq) begin
			empty_ff <= 1'b0;
			internal_empty_ff <= 1'b0;
			overflow_data_ff <= data;

			if (rdreq || internal_empty_ff) begin
				// Write directly to output
				output_data_ff <= data;
			end
			else begin
				// Write to overflow
				overflow_ff <= 1'b1;
				full_ff <= 1'b1;
			end
		end

		if (~reset_n) begin
			full_ff <= 1'b0;
			overflow_ff <= 1'b0;
			empty_ff <= 1'b1;
			internal_empty_ff <= 1'b1;
		end
	end

endmodule
