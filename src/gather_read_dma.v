module gather_read_dma#(
    parameter p_paths = 2
    )(
    input wire              i_clk,
    input wire              i_rst,

    input wire [15:0]       pcie_dcommand,

    input wire [31:0]       dma_read_host_address,
    input wire [31:0]       dma_read_device_address,
    input wire [31:0]       dma_read_length,
    input wire              dma_read_start,

    // Packer
    input wire [7:0]        packer_tag,
    input wire [127:0]      packer_dout,
    input wire [3:0]        packer_dout_dwen,
    input wire              packer_valid,
    input wire              packer_done,

    // DMA Read Request
    output reg [31:0]       dma_read_addr,
    output reg [9:0]        dma_read_len,
    output wire             dma_read_valid,
    input wire              dma_read_done,
    input wire [7:0]        current_tag,

    // Interrupt
    output reg              int_valid,
    input wire              int_done,

    output wire  [31:0]     awaddr,
    output wire  [7:0]      awlen,
    output wire [2:0]       awsize,
    output wire [1:0]       awburst,
    output wire [3:0]       awcache,
    output wire [2:0]       awproto,
    output wire             awvalid,
    input wire              awready,

    output wire [127:0]     wdata,
    output wire [15:0]      wstrb,
    output wire             wlast,
    output wire             wvalid,
    input wire              wready,

    input wire [1:0]        bresp,
    input wire              bvalid,
    output wire             bready
	);


	wire dma_read_int_valid;
	wire dma_read_int_done = 1;

	reg [7:0]  r_block_tag;
	reg 	   r_block_hot;
	reg 	   read_block;

	reg [31:0] r_dma_read_host_address;
	reg [31:0] r_dma_read_device_address;
	reg [31:0] r_dma_read_length;
	reg [7:0]  r_sub_dma_pairs;
	reg        r_dma_read_start;

	reg [31:0] r_dma_read_addr;
	reg [9:0] r_dma_read_len;
	reg r_dma_read_valid;

	wire [31:0] sub_dma_read_addr;
	wire [9:0] sub_dma_read_length;
	wire sub_dma_read_valid;

	assign dma_read_valid = r_dma_read_valid || sub_dma_read_valid;

	always @(*) begin
		if(r_dma_read_valid) begin
			dma_read_addr = r_dma_read_addr;
			dma_read_len = r_dma_read_len;
		end else begin
			dma_read_addr = sub_dma_read_addr;
			dma_read_len = sub_dma_read_length;
		end
	end

	wire all_empty;

	adv_dma_read_controller #(
      .p_paths(p_paths)
    ) dma_read_controller (
      .i_clk ( i_clk ),
      .i_rst ( i_rst ),

      .pcie_dcommand(pcie_dcommand),

      .dma_read_host_address(r_dma_read_host_address),
      .dma_read_device_address(r_dma_read_device_address),
      .dma_read_length(r_dma_read_length),
      .dma_read_start(r_dma_read_start),


      // Packer
      .packer_tag(packer_tag),
      .packer_dout(packer_dout),
      .packer_dout_dwen(packer_dout_dwen),
      .packer_valid(packer_valid),
      .packer_done(packer_done),

      // Interrupt
      .int_valid(dma_read_int_valid),
      .int_done(dma_read_int_done),
      .all_empty(all_empty),

      // DMA Read Request
      .dma_read_addr(sub_dma_read_addr),
      .dma_read_len(sub_dma_read_length),
      .dma_read_valid(sub_dma_read_valid),
      .dma_read_done(dma_read_done),
      .current_tag(current_tag),

	  .awaddr(awaddr),
	  .awlen(awlen),
	  .awsize(awsize),
	  .awburst(awburst),
	  .awcache(awcache),
	  .awproto(awproto),
	  .awvalid(awvalid),
	  .awready(awready),


	  .wdata(wdata),
	  .wstrb(wstrb),
	  .wlast(wlast),
	  .wvalid(wvalid),
	  .wready(wready),

	  .bresp(bresp),
	  .bvalid(bvalid),
	  .bready(bready)
    );

	wire block_fifo_full;
	wire block_fifo_empty;
	wire [127:0] block_fifo_dout;

	wire [31:0] block_fifo_dout_a = block_fifo_dout[31:0];
	wire [31:0] block_fifo_dout_b = block_fifo_dout[63:32];
	wire [31:0] block_fifo_dout_c = block_fifo_dout[95:64];
	wire [31:0] block_fifo_dout_d = block_fifo_dout[127:96];

	wire [31:0] path_a_address = {block_fifo_dout_a[7:0], block_fifo_dout_a[15:8], block_fifo_dout_a[23:16], block_fifo_dout_a[31:24]};
	wire [31:0] path_b_address = {block_fifo_dout_c[7:0], block_fifo_dout_c[15:8], block_fifo_dout_c[23:16], block_fifo_dout_c[31:24]};

	wire [31:0] path_a_length = {block_fifo_dout_b[7:0], block_fifo_dout_b[15:8], block_fifo_dout_b[23:16], block_fifo_dout_b[31:24]};
	wire [31:0] path_b_length = {block_fifo_dout_d[7:0], block_fifo_dout_d[15:8], block_fifo_dout_d[23:16], block_fifo_dout_d[31:24]};

	wire path_a_non_zero_length;
	wire path_b_non_zero_length;

	fifo #(
        .BITS_DEPTH($clog2(128/4)),
        .BITS_WIDTH(130)
    ) block_fifo (
        .i_clk(i_clk),
        .i_rst(i_rst),
        .din({|packer_dout[127:96], |packer_dout[63:32], packer_dout}),
        .wr_en(packer_valid && r_block_tag == packer_tag && r_block_hot),
        .rd_en(read_block),
        .dout({path_b_non_zero_length, path_a_non_zero_length, block_fifo_dout}),
        .empty(block_fifo_empty),
        .full(block_fifo_full)
    );

	localparam lp_state_bits = 32,
		lp_state_idle = 0,
		lp_state_wait_block = 1,
		lp_state_work_a = 2,
		lp_state_work_b = 3,
		lp_state_work_wait = 4,
		lp_state_work_wait_q = 5,
		lp_state_int = 9;

	reg [lp_state_bits-1:0] r_state, state_next;

    reg r_was_not_all_empty;

	reg set_dma_read_block;
	reg reset_dma;

	reg set_path_a, set_path_b;
	reg incr_address;
	reg decr_pairs;

	reg set_int;

	always @(*) begin
		state_next = r_state;
		set_dma_read_block = 0;
		reset_dma = 0;
		read_block = 0;
		set_path_a = 0;
		set_path_b = 0;
		incr_address = 0;
		decr_pairs = 0;
		set_int = 0;

		case(r_state)
			lp_state_idle: begin
				if(dma_read_start) begin
					// Read block with dma descriptions
					set_dma_read_block = 1;
					state_next = lp_state_wait_block;
				end
			end

			lp_state_wait_block: begin
				if(dma_read_done) begin
					reset_dma = 1;
					state_next = lp_state_work_wait;
				end
			end

			lp_state_work_wait: begin
				if (!block_fifo_empty) begin
					read_block = 1;
					state_next = lp_state_work_wait_q;
				end else if(r_sub_dma_pairs == 0) begin
					state_next = lp_state_int;
				end
			end

			lp_state_work_wait_q: begin
				if(path_a_non_zero_length) begin
					set_path_a = 1;
					state_next = lp_state_work_a;
				end else begin
					if(path_b_non_zero_length) begin
						set_path_b = 1;
						state_next = lp_state_work_b;
					end else begin
						state_next = lp_state_work_wait;
						decr_pairs = 1;
					end
				end
			end

			lp_state_work_a: begin
				if(dma_read_int_valid) begin
					//sub dma is done
					incr_address = 1;
					if(path_b_non_zero_length) begin
						set_path_b = 1;
						state_next = lp_state_work_b;
					end else begin
						state_next = lp_state_work_wait;
						decr_pairs = 1;
					end
				end
			end

			lp_state_work_b: begin
				if(dma_read_int_valid) begin
					incr_address = 1;
					state_next = lp_state_work_wait;
					decr_pairs = 1;
				end
			end

			lp_state_int: begin
				if(all_empty && r_was_not_all_empty) set_int = 1;
				if(int_done) begin
					state_next = lp_state_idle;
				end
			end
		endcase
	end

	always @(posedge i_clk) begin
		if (i_rst) begin
			r_state <= lp_state_idle;
			r_dma_read_start <= 0;
			r_dma_read_valid <= 0;
			r_block_tag <= 0;
			r_block_hot <= 0;

			int_valid <= 0;
            r_was_not_all_empty <= 0;
		end
		else begin
			r_state <= state_next;

			if(set_dma_read_block) begin
				r_dma_read_device_address <= dma_read_device_address;
				r_dma_read_addr <= dma_read_host_address;
				r_dma_read_len <= dma_read_length[11:2];
				r_sub_dma_pairs <= dma_read_length[11:4];

				r_block_tag <= current_tag;
				r_dma_read_valid <= 1;
				r_block_hot <= 1;
			end else if(reset_dma) begin
				r_dma_read_valid <= 0;
			end else begin
				if(r_sub_dma_pairs == 0) r_block_hot <= 0;
			end

			if(r_dma_read_start) r_dma_read_start <= 0;
			if(set_int) int_valid <= 1;
			if(int_done) int_valid <= 0;

			if(decr_pairs) r_sub_dma_pairs <= r_sub_dma_pairs - 1;

            if(!all_empty) r_was_not_all_empty <= 1;
            else if(set_int) r_was_not_all_empty <= 0;

			if(set_path_a) begin
				r_dma_read_host_address <= path_a_address;
				r_dma_read_length <= path_a_length;
				r_dma_read_start <= 1;
			end 

			if(set_path_b) begin
				r_dma_read_host_address <= path_b_address;
				r_dma_read_length <= path_b_length;
				r_dma_read_start <= 1;
			end

			if(incr_address) begin
				r_dma_read_device_address <= r_dma_read_device_address + r_dma_read_length;
			end
		end
	end

endmodule