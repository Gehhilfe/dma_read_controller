module dma_read_controller(
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
    output wire [31:0]      dma_read_addr,
    output wire [9:0]       dma_read_len,
    output reg              dma_read_valid,
    input wire              dma_read_done,
    input wire [7:0]        current_tag,


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

reg splitter_dma_done;
(* dont_touch = "true" *) wire splitter_dma_pending;

wire [31:0] req_address_host;
wire [31:0] req_address_device;
wire [31:0] req_size;

wire [31:0]  splitter_dma_address_host;
wire [31:0]  splitter_dma_address_device;
wire [9:0]  splitter_dma_size;

assign dma_read_addr = splitter_dma_address_host;
assign dma_read_len = splitter_dma_size;

transmission_spliter splitter(
    .i_clk(i_clk),
    .i_rst(i_rst),
    .pcie_dcommand(pcie_dcommand),

    .conf_start_address_host(dma_read_host_address),
    .conf_start_address_device(dma_read_device_address),
    .conf_size(dma_read_length),
    .conf_dir_write(0),
    .conf_valid(dma_read_start),

    .dma_pending(splitter_dma_pending),
    .dma_done(splitter_dma_done),

    .dma_address_host(splitter_dma_address_host),
    .dma_address_device(splitter_dma_address_device),
    .dma_size(splitter_dma_size)
);


localparam
    lp_state_bits = 32,
    lp_state_idle = 0,
    lp_state_request_done = 1;

reg [lp_state_bits-1:0] state, state_next;

reg dma_read_valid_next;

(* dont_touch = "true" *) reg         set_path_a;
(* dont_touch = "true" *) reg         dma_request_a_hot;
(* dont_touch = "true" *) reg [7:0]   dma_request_a_tag;
(* dont_touch = "true" *) reg [31:0]  dma_request_a_device_addr, dma_request_a_device_addr_next_burst_start;
(* dont_touch = "true" *) reg [9:0]  dma_request_a_size;
(* dont_touch = "true" *) reg [7:0]  dma_request_a_burst_ctr;
(* dont_touch = "true" *) reg dma_request_a_add_burst;



wire [127:0] path_a_data_dout;
wire [3:0] path_a_data_dout_dwen;
wire [31:0] path_a_burst_addr, path_a_elements;
wire [7:0] path_a_burst_ctr;
wire path_a_data_empty, path_a_burst_empty;
wire path_a_data_full, path_a_burst_full;
wire path_a_data_half_full, path_a_burst_half_full;
wire path_a_data_rd, path_a_burst_rd;

fifo #(
    .BITS_DEPTH($clog2(64)),
    .BITS_WIDTH(132)
) path_a_data_fifo(
    .i_clk(i_clk),
    .i_rst(i_rst),
    .din({packer_dout_dwen, packer_dout}),
    .wr_en(packer_valid && dma_request_a_tag == packer_tag),
    .rd_en(path_a_data_rd),
    .dout({path_a_data_dout_dwen, path_a_data_dout}),
    .full(path_a_data_full),
    .empty(path_a_data_empty),
    .half_full(path_a_data_half_full),
    .elements (path_a_elements)
);

(* dont_touch = "true" *) fifo #(
   .BITS_DEPTH($clog2(64)),
   .BITS_WIDTH(40)
) path_a_burst_fifo(
    .i_clk(i_clk),
    .i_rst(i_rst),
    .din({dma_request_a_device_addr, dma_request_a_burst_ctr}),
    .wr_en(dma_request_a_add_burst),
    .rd_en(path_a_burst_rd),
    .dout({path_a_burst_addr, path_a_burst_ctr}),
    .full(path_a_burst_full),
    .empty(path_a_burst_empty),
    .half_full(path_a_burst_half_full)
);




reg         set_path_b;
reg         dma_request_b_hot;
reg [7:0]   dma_request_b_tag;
reg [31:0]  dma_request_b_device_addr, dma_request_b_device_addr_next_burst_start;
reg [9:0]   dma_request_b_size;
reg [7:0]   dma_request_b_burst_ctr;
reg dma_request_b_add_burst;


wire [127:0] path_b_data_dout;
wire [3:0] path_b_data_dout_dwen;
wire [31:0] path_b_burst_addr, path_b_elements;
wire [7:0] path_b_burst_ctr;
wire path_b_data_empty, path_b_burst_empty;
wire path_b_data_full, path_b_burst_full;
wire path_b_data_half_full, path_b_burst_half_full;
wire path_b_data_rd, path_b_burst_rd;

fifo #(
    .BITS_DEPTH($clog2(64)),
    .BITS_WIDTH(132)
) path_b_data_fifo(
    .i_clk(i_clk),
    .i_rst(i_rst),
    .din({packer_dout_dwen, packer_dout}),
    .wr_en(packer_valid && dma_request_b_tag == packer_tag),
    .rd_en(path_b_data_rd),
    .dout({path_b_data_dout_dwen, path_b_data_dout}),
    .full(path_b_data_full),
    .empty(path_b_data_empty),
    .half_full(path_b_data_half_full),
    .elements (path_b_elements)
);

fifo #(
   .BITS_DEPTH($clog2(64)),
   .BITS_WIDTH(40)
) path_b_burst_fifo(
    .i_clk(i_clk),
    .i_rst(i_rst),
    .din({dma_request_b_device_addr, dma_request_b_burst_ctr}),
    .wr_en(dma_request_b_add_burst),
    .rd_en(path_b_burst_rd),
    .dout({path_b_burst_addr, path_b_burst_ctr}),
    .full(path_b_burst_full),
    .empty(path_b_burst_empty),
    .half_full(path_b_burst_half_full)
);


(* dont_touch = "true" *) drc_axi_pusher #(
    .p_paths(2)
) pusher (
    .i_clk(i_clk),
    .i_rst(i_rst),

    .paths_burst_rd({path_b_burst_rd, path_a_burst_rd}),
    .paths_data_rd({path_b_data_rd, path_a_data_rd}),
    .paths_data_in({path_b_data_dout, path_a_data_dout}),
    .paths_burst_empty({path_b_burst_empty, path_a_burst_empty}),
    .paths_burst_in({path_b_burst_addr, path_b_burst_ctr, path_a_burst_addr, path_a_burst_ctr}),

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


always @(*) begin
    dma_request_a_add_burst = 0;
    if(dma_request_a_hot) begin
        if (dma_request_a_size != 32'b0 && packer_dout_dwen[3] == 0 && packer_valid && dma_request_a_tag == packer_tag)
            dma_request_a_add_burst = 1;
        if (dma_request_a_size == 32'b0)
            dma_request_a_add_burst = 1;
    end
end

always @(*) begin
    dma_request_b_add_burst = 0;
    if(dma_request_b_hot) begin
        if (dma_request_b_size != 32'b0 && packer_dout_dwen[3] == 0 && packer_valid  && dma_request_b_tag == packer_tag)
            dma_request_b_add_burst = 1;
        if (dma_request_b_size == 32'b0)
            dma_request_b_add_burst = 1; 
    end
end


// synthesis translate_off
always @(posedge i_clk) begin
    if (packer_valid && dma_request_a_tag == packer_tag) begin
        $display("Add data to path A ctr = %d", dma_request_a_burst_ctr);
    end
    if (dma_request_a_add_burst) begin
        $display("Add burst with length = %d to path A", dma_request_a_burst_ctr);
    end
end

always @(posedge i_clk) begin
    if (packer_valid && dma_request_b_tag == packer_tag) begin
        $display("Add data to path B ctr = %d", dma_request_b_burst_ctr);
    end
    if (dma_request_b_add_burst) begin
        $display("Add burst with length = %d to path B", dma_request_b_burst_ctr);
    end
end
// synthesis translate_on

always @(*) begin
    state_next = state;
    set_path_a = 0;
    set_path_b = 0;
    dma_read_valid_next = 0;
    splitter_dma_done = 0;
    case (state)
        lp_state_idle: begin
            if(splitter_dma_pending && !path_a_burst_half_full && !path_a_data_half_full && !dma_request_a_hot) begin
                dma_read_valid_next = 1;
                set_path_a = 1;
                state_next = lp_state_request_done;
            end
             
            else if (splitter_dma_pending && !path_b_burst_half_full && !path_b_data_half_full && !dma_request_b_hot) begin
                dma_read_valid_next = 1;
                set_path_b = 1;
                state_next = lp_state_request_done;
            end
        end

        lp_state_request_done: begin
            dma_read_valid_next = 1;
            if(dma_read_done) begin
                dma_read_valid_next = 0;
                splitter_dma_done = 1;
                state_next = lp_state_idle;
            end
        end
    endcase
end

always @(posedge i_clk) begin
    if (i_rst) begin
        state <= lp_state_idle;
        dma_read_valid <= 0;
        
        dma_request_a_size <= 0;
        dma_request_a_hot <= 0;
        
        dma_request_b_size <= 0;
        dma_request_b_hot <= 0;
    end // if (i_rst)
    else begin
        state <= state_next;
        dma_read_valid <= dma_read_valid_next;

        if (set_path_a) begin
            dma_request_a_tag <= current_tag;
            dma_request_a_device_addr <= splitter_dma_address_device;
            dma_request_a_device_addr_next_burst_start <= splitter_dma_address_device;
            dma_request_a_size <= splitter_dma_size;
            dma_request_a_burst_ctr <= 0;
            dma_request_a_hot <= 1;
        end // if (set_path_a)
        else begin
            if(dma_request_a_size == 0)
                dma_request_a_hot <= 0;
              if(dma_request_a_add_burst)
                dma_request_a_device_addr <= dma_request_a_device_addr_next_burst_start;
        end

        if (set_path_b) begin
            dma_request_b_tag <= current_tag;
            dma_request_b_device_addr <= splitter_dma_address_device;
            dma_request_b_device_addr_next_burst_start <= splitter_dma_address_device;
            dma_request_b_size <= splitter_dma_size;
            dma_request_b_burst_ctr <= 0;
            dma_request_b_hot <= 1;
        end // if (set_path_a)
        else begin
            if(dma_request_b_size == 0)
                dma_request_b_hot <= 0;
              if(dma_request_b_add_burst)
                dma_request_b_device_addr <= dma_request_b_device_addr_next_burst_start;
        end


        // Path A
        if(packer_valid) begin
            if (packer_tag == dma_request_a_tag) begin
                casex (packer_dout_dwen)
                    4'b0001: dma_request_a_size <= dma_request_a_size - 4;
                    4'b001x: dma_request_a_size <= dma_request_a_size - 8;
                    4'b01xx: dma_request_a_size <= dma_request_a_size - 12;
                    4'b1xxx: dma_request_a_size <= dma_request_a_size - 16;
                endcase // packer_dout_dwen

                casex (packer_dout_dwen)
                    4'b0001: dma_request_a_device_addr_next_burst_start <= dma_request_a_device_addr_next_burst_start + 4;
                    4'b001x: dma_request_a_device_addr_next_burst_start <= dma_request_a_device_addr_next_burst_start + 8;
                    4'b01xx: dma_request_a_device_addr_next_burst_start <= dma_request_a_device_addr_next_burst_start + 12;
                    4'b1xxx: dma_request_a_device_addr_next_burst_start <= dma_request_a_device_addr_next_burst_start + 16;
                endcase // packer_dout_dwen

                if (packer_dout_dwen[3] == 0) dma_request_a_burst_ctr <= 0;
                else dma_request_a_burst_ctr <= dma_request_a_burst_ctr + 1'b1;
            end

            if (packer_tag == dma_request_b_tag) begin
                casex (packer_dout_dwen)
                    4'b0001: dma_request_b_size <= dma_request_b_size - 4;
                    4'b001x: dma_request_b_size <= dma_request_b_size - 8;
                    4'b01xx: dma_request_b_size <= dma_request_b_size - 12;
                    4'b1xxx: dma_request_b_size <= dma_request_b_size - 16;
                endcase // packer_dout_dwen

                casex (packer_dout_dwen)
                    4'b0001: dma_request_b_device_addr_next_burst_start <= dma_request_b_device_addr_next_burst_start + 4;
                    4'b001x: dma_request_b_device_addr_next_burst_start <= dma_request_b_device_addr_next_burst_start + 8;
                    4'b01xx: dma_request_b_device_addr_next_burst_start <= dma_request_b_device_addr_next_burst_start + 12;
                    4'b1xxx: dma_request_b_device_addr_next_burst_start <= dma_request_b_device_addr_next_burst_start + 16;
                endcase // packer_dout_dwen

                if (packer_dout_dwen[3] == 0) dma_request_b_burst_ctr <= 0;
                else dma_request_b_burst_ctr <= dma_request_b_burst_ctr + 1'b1;
            end
        end
    end // else
end // always @(posedge i_clk)

endmodule // dma_read_controller