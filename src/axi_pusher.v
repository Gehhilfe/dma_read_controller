module drc_axi_pusher#(
		parameter p_paths = 2
	)(
		input wire i_clk,
		input wire i_rst,

		output reg [p_paths-1:0] paths_burst_rd,
		output reg [p_paths-1:0] paths_data_rd,
		input wire [p_paths*132-1:0] paths_data_in,
		input wire [p_paths-1:0] paths_burst_empty,
		input wire [p_paths*40-1:0] paths_burst_in,

		output reg	[31:0] 		awaddr,
		output reg	[7:0] 		awlen,
		output wire [2:0] 		awsize,
		output wire [1:0]		awburst,
		output wire [3:0]		awcache,
		output wire [2:0]		awproto,
		output reg				awvalid,
		input wire				awready,

		output reg [127:0]		wdata,
		output wire [15:0]		wstrb,
		output wire 			wlast,
		output reg				wvalid,
		input wire				wready,

		input wire [1:0]		bresp,
		input wire				bvalid,
		output reg				bready
	);


// 128bits in each data transfer
assign awsize = 3'b111;

// INCR Burst
assign awburst = 2'b01;

// Fixed xilinx
assign awcache = 4'b0011;
assign awproto = 3'b000;
assign wstrb = 16'hFF;

localparam 
	lp_state_bits = 32,
	lp_state_idle = 0,
	lp_state_address = 1,
	lp_state_burst_data = 2,
	lp_state_resp = 3;

reg [lp_state_bits-1:0] state, state_next;

reg	[7:0] burst_ctr;
assign wlast = burst_ctr == 0;

reg [p_paths-1:0] path_sel;

integer j;
generate
	genvar i;
	for (i=0; i<p_paths; i=i+1) begin
		reg all_null;
		always @(*) begin
			all_null = ~paths_burst_empty[i];
			for (j=0; j<i;j=j+1) begin
				if(paths_burst_empty[j] == 1'b0)
					all_null = 0;
			end
		end

		always @(*) begin
			path_sel[i] = all_null;
		end
	end
endgenerate

reg [p_paths-1:0] path_active;
reg [p_paths-1:0] path_active_next;
reg awvalid_next, wvalid_next, bready_next;

always @(*) begin
	state_next = state;

	path_active_next = path_active;
	paths_burst_rd = 0;
	paths_data_rd = 0;

	awvalid_next = 0;
	wvalid_next = 0;
	bready_next = 0;

	case(state)
		lp_state_idle: begin
			if (|path_sel) begin
				path_active_next = path_sel;
				paths_burst_rd = path_sel;
				paths_data_rd = path_sel;

				awvalid_next = 1;
				state_next = lp_state_address;
			end
		end

		lp_state_address: begin
			awvalid_next = 1;
			if(awvalid && awready) begin
				awvalid_next = 0;
				wvalid_next = 1;
				state_next = lp_state_burst_data;
			end
		end

		lp_state_burst_data: begin
			wvalid_next = 1;
			if(wvalid && wready && burst_ctr != 0) begin
				paths_data_rd = path_active;
			end else if (wvalid && wready && burst_ctr == 0) begin
				wvalid_next = 0;
				bready_next = 1;
				state_next = lp_state_resp;
			end
		end

		lp_state_resp: begin
			bready_next = 1;
			if(bvalid && bready) begin
				bready_next = 0;
				state_next = lp_state_idle;
			end
		end
	endcase
end


//address and burst len mux
always @(*) begin
	awaddr = awaddr;
	awlen = awlen;
	wdata = wdata;
	for (j=0; j<p_paths; j=j+1) begin
		if(path_active[j]) begin
			awaddr = paths_burst_in[j*40+8 +:32];
			awlen = paths_burst_in[j*40 +:7] - 1'b1;
			wdata = paths_data_in[j*132 +:128];
		end
	end
end

always @(posedge i_clk) begin
	if (i_rst) begin
		state <= lp_state_idle;
		path_active <= 0;
		paths_burst_rd <= 0;
		paths_data_rd <= 0;

		awvalid <= 0;
		wvalid <= 0;
		bready <= 0;
	end else begin
		state <= state_next;

		awvalid <= awvalid_next;
		wvalid <= wvalid_next;
		bready <= bready_next;

		if(awvalid)
			burst_ctr <= awlen;
		if(wvalid && wready)
			burst_ctr <= burst_ctr - 1'b1;


		path_active <= path_active_next;
	end
end

endmodule