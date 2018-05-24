module adv_drc_axi_pusher #(
	parameter p_paths = 2,
	parameter p_id_bits = 1
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
		output reg [p_id_bits-1:0] awid,
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
assign awsize = 3'b100;

// INCR Burst
assign awburst = 2'b01;

// Fixed xilinx
assign awcache = 4'b0011;
assign awproto = 3'b000;
assign wstrb = 16'hFFFF;

integer j;

reg [p_paths-1:0] addr_path_active, data_path_active;
reg [p_paths-1:0] addr_path_active_next, data_path_active_next;

//address and burst len mux
always @(*) begin
	//awaddr = awaddr;
	//awlen = awlen;
	//wdata = wdata;
	awaddr = 0;
	awlen = 0;
	wdata = 0;
	for (j=0; j<p_paths; j=j+1) begin
		if(addr_path_active[j]) begin
			awaddr = paths_burst_in[j*40+8 +:32];
			awlen = paths_burst_in[j*40 +:8] - 1'b1;
		end
		if(data_path_active[j]) begin
			wdata = paths_data_in[j*132 +:128];
		end
	end
end

//Path priority selector
reg [p_paths-1:0] path_sel;
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

//Data state machine
localparam 
	lp_data_state_bits = 32,
	lp_data_state_idle = 0,
	lp_data_state_burst = 1;
reg start_data;
reg [lp_data_state_bits-1:0] data_state, data_state_next;
reg wvalid_next, awvalid_next;

reg	[7:0] burst_ctr;
assign wlast = burst_ctr == 0;

always @(*) begin
	data_state_next = data_state;
	data_path_active_next = data_path_active;
	paths_data_rd = 0;
	wvalid_next = 0;

	case(data_state)
		lp_data_state_idle: begin
			if(start_data) begin
				data_path_active_next = addr_path_active;
				paths_data_rd = addr_path_active;
				data_state_next = lp_data_state_burst; 			
			end
		end

		lp_data_state_burst: begin
			wvalid_next = 1;
			if(wvalid && wready && burst_ctr != 0) begin
				paths_data_rd = data_path_active;
			end else if (wvalid && wready && burst_ctr == 0) begin
				wvalid_next = 0;
				data_state_next = lp_data_state_idle;
			end
		end
	endcase
end

//Addressing state machine
localparam 
	lp_addr_state_bits = 32,
	lp_addr_state_idle = 0,
	lp_addr_state_address = 1,
	lp_addr_state_start_data = 2;

reg [lp_addr_state_bits-1:0] addr_state, addr_state_next;

always @(*) begin
	addr_state_next = addr_state;
	addr_path_active_next = addr_path_active;
	paths_burst_rd = 0;
	awvalid_next = 0;
	start_data = 0;

	case(addr_state)
		lp_addr_state_idle: begin
			if(|path_sel) begin
				addr_path_active_next = path_sel;
				paths_burst_rd = path_sel;

				awvalid_next = 1;
				addr_state_next = lp_addr_state_address;
			end
		end

		lp_addr_state_address: begin
			awvalid_next = 1;
			if(awvalid && awready) begin
				awvalid_next = 0;
				addr_state_next = lp_addr_state_start_data;
			end
		end

		lp_addr_state_start_data: begin
			start_data = 1;
			if(data_state == lp_data_state_idle) begin
				addr_state_next = lp_addr_state_idle;
			end
		end
	endcase
end

always @(posedge i_clk) begin
	if (i_rst) begin
		addr_state <= lp_addr_state_idle;
		data_state <= lp_data_state_idle;
		addr_path_active <= 0;
		data_path_active <= 0;

		wvalid <= 0;
		awvalid <= 0;
		bready <= 0;
	end else begin
		addr_state <= addr_state_next;
		data_state <= data_state_next;

		addr_path_active <= addr_path_active_next;
		data_path_active <= data_path_active_next;

		wvalid <= wvalid_next;
		awvalid <= awvalid_next;

		if(wlast)
			bready <= 1;
		else if(bready && bvalid)
			bready <= 0;

		if(start_data && data_state == lp_data_state_idle)
			burst_ctr <= awlen;
		if(wvalid && wready)
			burst_ctr <= burst_ctr - 1'b1;
	end
end

endmodule