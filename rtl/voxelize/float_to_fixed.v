`timescale 1ps / 1ps

module float_to_fixed (
	float_in,
	fixed_sign,
	true_fixed_value
);

parameter FIXED_WIDTH = 16; // must not be > 32
parameter FIXED_FRACTIONAL = 8;

input [31:0] float_in;
output fixed_sign;
output [FIXED_WIDTH-1:0] true_fixed_value;
	
	wire [7:0] float_exp;
	wire [22:0] float_mantissa;
	assign {fixed_sign, float_exp, float_mantissa} = float_in;

	wire [31:0] working_out = {1'b1,float_mantissa,8'h0};
	
	wire [7:0] shift_dist = 8'd127 + (FIXED_WIDTH-FIXED_FRACTIONAL) - 1
					- float_exp;
	wire [4:0] trunc_shift_dist = (|shift_dist[7:5]) ? 5'b11111 : shift_dist[4:0];

	wire [31:0] shifted_out = working_out >> trunc_shift_dist;
	
	assign fixed_mag = 	shifted_out[31:32-FIXED_WIDTH];

    assign true_fixed_value = fixed_sign ? -fixed_mag : fixed_mag;
	
endmodule
