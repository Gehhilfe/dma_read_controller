`timescale 1ns / 1ps

module transmission_spliter(
    input wire i_clk,
    input wire i_rst,
    input wire [31:0] conf_start_address_host,
    input wire [31:0] conf_start_address_device,
    input wire [31:0] conf_size,
    input wire conf_valid,
    input wire conf_dir_write,
    input wire [15:0] pcie_dcommand,
    output reg conf_transaction_done,
    
    output reg dma_pending,
    input wire dma_done,
    
    output wire [31:0] dma_address_host,
    output wire [31:0] dma_address_device,
    output reg [31:0] dma_size,
    output wire dma_dir_write
    
    );

reg [2:0] max_read_req_size;
reg [2:0] max_payload_size;

reg [31:0] max_read_req_bytes;
reg [15:0] max_read_req_shift;

reg [31:0] max_payload_size_bytes;
reg [15:0] max_payload_size_shift;

reg [31:0] r_conf_address_device;
reg [31:0] r_conf_address_host;
reg [31:0] r_conf_size;
reg r_conf_dir_write;
reg r_is_full;
reg r_is_full_next;

assign dma_address_device = r_conf_address_device;
assign dma_address_host = r_conf_address_host;
assign dma_dir_write = r_conf_dir_write;

always @(*) begin   
    if(conf_valid) begin
        if(conf_dir_write)
            r_is_full = conf_size >= max_payload_size_bytes;
        else
            r_is_full = conf_size >= max_read_req_bytes;
    end else begin
        if(r_conf_dir_write)
                r_is_full = r_conf_size >= max_payload_size_bytes;
            else
                r_is_full = r_conf_size >= max_read_req_bytes;
    end
end

always @(*) begin   
    if(r_conf_dir_write)
            r_is_full_next = r_conf_size >= max_payload_size_bytes<<1;
        else
            r_is_full_next = r_conf_size >= max_read_req_bytes<<1;
end

always @(*) begin
    dma_size = r_conf_size;
    if(r_is_full) begin
        if(!r_conf_dir_write) dma_size = max_read_req_bytes;
        else dma_size = max_payload_size_bytes;
    end
end

localparam
    lp_state_bits = 8,
    lp_state_idle = 0,
    lp_state_do = 1;

reg [lp_state_bits-1:0] state, state_next;
reg dma_pending_next;
reg done_op;
reg conf_transaction_done_next;

always @(*) begin
    state_next = state;
    dma_pending_next = 0;
    done_op = 0;
    conf_transaction_done_next = 0;

    case(state)
        lp_state_idle: begin
            if (conf_valid) begin
                state_next = lp_state_do;
                dma_pending_next = 1;
            end
        end
        
        lp_state_do: begin
            dma_pending_next = 1;
            if (dma_done) begin
                done_op = 1;
                if(!r_is_full_next) begin
                    dma_pending_next = 0;
                    state_next = lp_state_idle;
                    conf_transaction_done_next = 1;
                end
            end
        end
    endcase
end


always @(*) begin
    case(max_read_req_size)
        default: begin
            max_read_req_bytes = 128;
            max_read_req_shift = $clog2(128);
        end
        
        3'b000: begin
            max_read_req_bytes = 128;
            max_read_req_shift = $clog2(128);
         end
         
         3'b001: begin
            max_read_req_bytes = 256;
            max_read_req_shift = $clog2(256);        
         end
         
        3'b010: begin
            max_read_req_bytes = 512;
            max_read_req_shift = $clog2(512);        
        end
          
        3'b011: begin
            max_read_req_bytes = 1024;
            max_read_req_shift = $clog2(1024);        
        end
        
        3'b100: begin
            max_read_req_bytes = 2048;
            max_read_req_shift = $clog2(2048);        
        end
        
        3'b101: begin
            max_read_req_bytes = 4096;
            max_read_req_shift = $clog2(4096);        
        end
    endcase
    
    case(max_payload_size)
        default: begin
            max_payload_size_bytes = 128;
            max_payload_size_shift = $clog2(128);
        end
        
        3'b000: begin
            max_payload_size_bytes = 128;
            max_payload_size_shift = $clog2(128);
        end
        
        3'b001: begin
            max_payload_size_bytes = 256;
            max_payload_size_shift = $clog2(256);        
        end
        
        3'b010: begin
            max_payload_size_bytes = 512;
            max_payload_size_shift = $clog2(512);        
        end
        
        3'b011: begin
            max_payload_size_bytes = 1024;
            max_payload_size_shift = $clog2(1024);        
        end
    endcase
end

always @(posedge i_clk) begin
    if (i_rst) begin
        max_payload_size <= 0;
        max_read_req_size <= 0;
        dma_pending <= 0;
        state <= lp_state_idle;
        conf_transaction_done <= 0;
        
    end else begin
        max_payload_size <= pcie_dcommand[7:5];
        max_read_req_size <= pcie_dcommand[14:12];
        state <= state_next;
        if (r_conf_size[31])
            dma_pending <= 0;
        else
            dma_pending <= dma_pending_next;

        conf_transaction_done <= conf_transaction_done_next;
        
        if(conf_valid) begin
            r_conf_address_host <= conf_start_address_host;
            r_conf_address_device <= conf_start_address_device;
            r_conf_size <= conf_size;
            r_conf_dir_write <= conf_dir_write;
        end else if (done_op) begin
            r_conf_address_host <= r_conf_address_host + dma_size;
            r_conf_address_device <= r_conf_address_device + dma_size;
            r_conf_size <= r_conf_size - dma_size;
        end
    end
end
endmodule
