`timescale 1ns / 1ps
`include "random_test.sv"

module transmission_spliter_tb;

bit clk;
bit reset;

always #5 clk = ~clk;

initial begin
    reset = 1;
    #25 reset = 0;
end

conf_intf conf(clk,reset);
dma_intf dma(clk,reset);

test t1(conf, dma);

transmission_spliter DUT (
    .i_clk(conf.clk),
    .i_rst(conf.reset),
    .conf_start_address_host(conf.start_address_host),
    .conf_start_address_device(conf.start_address_device),
    .conf_size({16'b0, conf.size}),
    .conf_valid(conf.valid),
    .conf_dir_write(conf.dir_write),
    .conf_transaction_done(conf.transaction_done),
    
    .pcie_dcommand(conf.pcie_decommand),
    
    .dma_pending(dma.pending),
    .dma_done(dma.done),
    .dma_size(dma.size),
    .dma_address_host(dma.address_host),
    .dma_address_device(dma.address_device),
    .dma_dir_write(dma.dir_write)
);

endmodule