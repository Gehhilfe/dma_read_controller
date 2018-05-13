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
    input wire [7:0]        current_tag
);


reg splitter_dma_done;
wire splitter_dma_pending;

wire [31:0] req_address_host;
wire [31:0] req_address_device;
wire [31:0] req_size;

wire [31:0]  splitter_dma_address_host;
wire [31:0]  splitter_dma_address_device;
wire [31:0]  splitter_dma_size;

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
    lp_state_wait_data = 1;

reg [lp_state_bits-1:0] state, state_next;

reg dma_read_valid_next;

reg         set_path_a;
reg         dma_request_a_hot;
reg [7:0]   dma_request_a_tag;
reg [31:0]  dma_request_a_device_addr, dma_request_a_device_addr_next_burst_start;
reg [31:0]  dma_request_a_size;
reg [7:0]   dma_request_a_burst_ctr;
reg dma_request_a_add_burst;


wire [127:0] path_a_data_dout;
wire [3:0] path_a_data_dout_dwen;
wire [31:0] path_a_burst_addr;
wire [7:0] path_a_burst_ctr;
wire path_a_data_empty, path_a_burst_empty;
wire path_a_data_full, path_a_burst_full;

always @(*) begin
    dma_request_a_add_burst = 0;
    if (dma_request_a_size != 32'b0 && packer_dout_dwen[3] == 0)
        dma_request_a_add_burst = 1;
    if (dma_request_a_hot && dma_request_a_size == 32'b0)
        dma_request_a_add_burst = 1;
end


// synthesis translate_off
always @(posedge i_clk) begin
    if (packer_valid && dma_request_a_tag == packer_tag) begin
        $display("Add data to path a ctr = %d", dma_request_a_burst_ctr);
    end
    if (dma_request_a_add_burst) begin
        $display("Add burst with length = %d", dma_request_a_burst_ctr);
    end
end
// synthesis translate_on


fifo #(
    .BITS_DEPTH($clog2(128)),
    .BITS_WIDTH(132)
) path_a_data_fifo(
    .i_clk(i_clk),
    .i_rst(i_rst),
    .din({packer_dout_dwen, packer_dout}),
    .wr_en(packer_valid && dma_request_a_tag == packer_tag),
    .rd_en(0),
    .dout({path_a_data_dout_dwen, path_a_data_dout}),
    .full(path_a_data_full),
    .empty(path_a_data_empty)
);

fifo #(
   .BITS_DEPTH($clog2(128)),
   .BITS_WIDTH(7+32)
) path_a_burst_fifo(
    .i_clk(i_clk),
    .i_rst(i_rst),
    .din({dma_request_a_device_addr, dma_request_a_burst_ctr}),
    .wr_en(dma_request_a_add_burst),
    .rd_en(0),
    .dout({path_a_burst_addr, path_a_burst_ctr}),
    .full(path_a_burst_full),
    .empty(path_a_burst_empty)
);

always @(*) begin
    state_next = state;
    set_path_a = 0;
    dma_read_valid_next = 0;

    case (state)
        lp_state_idle: begin
            if(splitter_dma_pending && dma_request_a_size == 0) begin
                dma_read_valid_next = 1;
                set_path_a = 1;
            end
            if(splitter_dma_pending && dma_read_done) begin
                state_next = lp_state_wait_data;
                dma_read_valid_next = 0;
            end
        end // lp_state_idle:

        lp_state_wait_data: begin
            if(!dma_request_a_hot) state_next = lp_state_idle;
        end

    endcase
end

always @(posedge i_clk) begin
    if (i_rst) begin
        state <= lp_state_idle;
        dma_read_valid <= 0;
        dma_request_a_size <= 0;
        dma_request_a_hot <= 0;
        splitter_dma_done <= 0;
    end // if (i_rst)
    else begin
        state <= state_next;
        dma_read_valid <= dma_read_valid_next;

        if(splitter_dma_done) splitter_dma_done <= 0;

        if (set_path_a) begin
            dma_request_a_tag <= current_tag;
            dma_request_a_device_addr <= splitter_dma_address_device;
            dma_request_a_device_addr_next_burst_start <= splitter_dma_address_device;
            dma_request_a_size <= splitter_dma_size;
            dma_request_a_burst_ctr <= 0;
            dma_request_a_hot <= 1;
            splitter_dma_done <= 1;
        end // if (set_path_a)
        else begin
            if(dma_request_a_size == 0)
                dma_request_a_hot <= 0;
              if(dma_request_a_add_burst)
                dma_request_a_device_addr <= dma_request_a_device_addr_next_burst_start;
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
        end
    end // else
end // always @(posedge i_clk)

endmodule // dma_read_controller