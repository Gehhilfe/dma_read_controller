module adv_dma_read_controller #(
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
    output wire [31:0]      dma_read_addr,
    output wire [9:0]       dma_read_len,
    output reg              dma_read_valid,
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


reg splitter_dma_done;
wire splitter_dma_pending;

wire [31:0] req_address_host;
wire [31:0] req_address_device;
wire [31:0] req_size;

wire [31:0]  splitter_dma_address_host;
wire [31:0]  splitter_dma_address_device;
wire [11:0]  splitter_dma_size;

assign dma_read_addr = splitter_dma_address_host;
assign dma_read_len = splitter_dma_size[11:2];

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

integer j;

reg [p_paths-1:0] path_sel;
reg [p_paths-1:0] set_paths;
wire [p_paths-1:0] paths_hot;
wire [p_paths-1:0] paths_can_start;

wire [p_paths-1:0][132-1:0] paths_data_out;
wire [p_paths-1:0] paths_data_rd;
wire [p_paths-1:0] paths_data_half_full;

wire [p_paths-1:0][40-1:0] paths_burst_out;
wire [p_paths-1:0] paths_burst_rd;
wire [p_paths-1:0] paths_burst_empty;

generate
    genvar i;
    for (i=0; i<p_paths; i=i+1) begin

        wire        dma_set_path = set_paths[i];

        reg        dma_request_hot;
        assign paths_hot[i] = dma_request_hot;
        reg [7:0]  dma_request_tag;
        reg [31:0] dma_request_device_addr, dma_request_device_addr_next_burst_start;
        reg [11:0] dma_request_size;
        reg [7:0]  dma_request_burst_ctr;
        reg        dma_request_add_burst;

        wire path_burst_half_full;
        assign paths_can_start[i] = !paths_data_half_full[i] && !path_burst_half_full && !dma_request_hot;
        
        fifo #(
            .BITS_DEPTH($clog2(64)),
            .BITS_WIDTH(132)
        ) path_data_fifo(
            .i_clk(i_clk),
            .i_rst(i_rst),
            .din({packer_dout_dwen, packer_dout}),
            .wr_en(packer_valid && dma_request_tag == packer_tag),
            .rd_en(paths_data_rd[i]),
            .dout(paths_data_out[i]),
            .half_full(paths_data_half_full[i]),
            .elements (path_elements)
        );

        fifo #(
           .BITS_DEPTH($clog2(64)),
           .BITS_WIDTH(40)
        ) path_burst_fifo(
            .i_clk(i_clk),
            .i_rst(i_rst),
            .din({dma_request_device_addr, dma_request_burst_ctr}),
            .wr_en(dma_request_add_burst),
            .rd_en(paths_burst_rd[i]),
            .dout(paths_burst_out[i]),
            .half_full(path_burst_half_full),
            .empty(paths_burst_empty[i])
        );

        always @(*) begin
            dma_request_add_burst = 0;
            if(dma_request_hot) begin
                if (dma_request_size != 11'b0 && packer_dout_dwen[3] == 0 && packer_valid && dma_request_tag == packer_tag)
                    dma_request_add_burst = 1;
                if (dma_request_size == 11'b0)
                    dma_request_add_burst = 1;
            end
        end

        always @(posedge i_clk) begin
            if (i_rst) begin
                dma_request_size <= 0;
                dma_request_hot <= 0; 
            end else begin
                if (dma_set_path) begin
                    dma_request_tag <= current_tag;
                    dma_request_device_addr <= splitter_dma_address_device;
                    dma_request_device_addr_next_burst_start <= splitter_dma_address_device;
                    dma_request_size <= splitter_dma_size;
                    dma_request_burst_ctr <= 0;
                    dma_request_hot <= 1;
                end // if (dma_set_path)
                else begin
                    if(dma_request_size == 0)
                        dma_request_hot <= 0;
                    if(dma_request_add_burst)
                        dma_request_device_addr <= dma_request_device_addr_next_burst_start;
                end


                if(packer_valid) begin
                    if (packer_tag == dma_request_tag) begin
                        casex (packer_dout_dwen)
                            4'b0001: dma_request_size <= dma_request_size - 4;
                            4'b001x: dma_request_size <= dma_request_size - 8;
                            4'b01xx: dma_request_size <= dma_request_size - 12;
                            4'b1xxx: dma_request_size <= dma_request_size - 16;
                        endcase // packer_dout_dwen

                        casex (packer_dout_dwen)
                            4'b0001: dma_request_device_addr_next_burst_start <= dma_request_device_addr_next_burst_start + 4;
                            4'b001x: dma_request_device_addr_next_burst_start <= dma_request_device_addr_next_burst_start + 8;
                            4'b01xx: dma_request_device_addr_next_burst_start <= dma_request_device_addr_next_burst_start + 12;
                            4'b1xxx: dma_request_device_addr_next_burst_start <= dma_request_device_addr_next_burst_start + 16;
                        endcase // packer_dout_dwen

                        if (packer_dout_dwen[3] == 0) dma_request_burst_ctr <= 0;
                        else dma_request_burst_ctr <= dma_request_burst_ctr + 1'b1;
                    end
                end
            end // end else
        end // always @(posedge i_clk)
    end
endgenerate

generate
    for (i=0; i<p_paths; i=i+1) begin
        reg all_null;
        always @(*) begin
            all_null = paths_can_start[i];
            for (j=0; j<i;j=j+1) begin
                if(paths_can_start[j])
                    all_null = 0;
            end
        end

        always @(*) begin
            path_sel[i] = all_null;
        end
    end
endgenerate


adv_drc_axi_pusher #(
    .p_paths(p_paths)
) pusher (
    .i_clk(i_clk),
    .i_rst(i_rst),

    .paths_burst_rd(paths_burst_rd),
    .paths_data_rd(paths_data_rd),
    .paths_data_in(paths_data_out),
    .paths_burst_empty(paths_burst_empty),
    .paths_burst_in(paths_burst_out),

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

localparam
    lp_state_bits = 32,
    lp_state_idle = 0,
    lp_state_request_done = 1,
    lp_state_interrupt = 2;

reg [lp_state_bits-1:0] state, state_next;
reg dma_read_valid_next;
reg int_valid_next;
reg splitter_dma_pending_d;

always @(*) begin
    state_next = state;
    set_paths = 0;
    dma_read_valid_next = 0;
    splitter_dma_done = 0;
    int_valid_next = 0;
    case (state)
        lp_state_idle: begin
            if(splitter_dma_pending_d && !splitter_dma_pending) begin
                int_valid_next = 1;
                state_next = lp_state_interrupt;
            end // if(splitter_dma_pending_d && !splitter_dma_pending)
            else if(splitter_dma_pending && |path_sel) begin
                dma_read_valid_next = 1;
                set_paths = path_sel;
                state_next = lp_state_request_done;
            end
        end // lp_state_idle

        lp_state_interrupt: begin
            int_valid_next = 1;
            if (int_done) begin
                int_valid_next = 0;
                state_next = lp_state_idle;
            end // if (int_done)
        end // lp_state_interrupt

        lp_state_request_done: begin
            dma_read_valid_next = 1;
            if(dma_read_done) begin
                dma_read_valid_next = 0;
                splitter_dma_done = 1;
                state_next = lp_state_idle;
            end
        end // lp_state_request_done
    endcase
end

always @(posedge i_clk) begin
    if (i_rst) begin
        state <= lp_state_idle;
        dma_read_valid <= 0;
        splitter_dma_pending_d <= 0;
        int_valid <= 0;
    end // if (i_rst)
    else begin
        state <= state_next;
        dma_read_valid <= dma_read_valid_next;
        splitter_dma_pending_d <= splitter_dma_pending;
        int_valid <= int_valid_next;
    end // else
end // always @(posedge i_clk)

endmodule // adv_dma_read_controller