`timescale 1ns / 1ps
`ifndef CLASSES_SV
`define CLASSES_SV

`define DRIV_IF(inf) ``inf.DRIVER.driver_cb
`define MONITOR_IF(inf) ``inf.MONITOR.monitor_cb

interface conf_intf(input logic clk,reset);
    logic [31:0] start_address_host;
    logic [31:0] start_address_device;
    logic [31:0] size;
    logic valid;
    logic dir_write;
    logic transaction_done;
    logic [15:0] pcie_decommand;
    
    clocking driver_cb @(posedge clk);
        default input #1 output #1;
        output start_address_host;
        output start_address_device;
        output size;
        output valid;
        output dir_write;
        input transaction_done;
        output pcie_decommand;
    endclocking
    
    clocking monitor_cb @(posedge clk);
        default input #1 output #1;
        input start_address_host;
        input start_address_device;
        input size;
        input valid;
        input dir_write;
        input transaction_done;
        input pcie_decommand;
    endclocking

    //driver modport
    modport DRIVER  (clocking driver_cb,input clk,reset);
    
    //monitor modport 
    modport MONITOR (clocking monitor_cb,input clk,reset);    
endinterface

interface dma_intf(input logic clk, reset);
    logic pending;
    logic done;
    logic [31:0] address_host;
    logic [31:0] address_device;
    logic [31:0] size;
    logic dir_write;
    
    clocking driver_cb @(posedge clk);
        default input #1 output #1;
        output done;
        input pending;
        input address_host;
        input address_device;
        input size;
        input dir_write;
    endclocking
    
    clocking monitor_cb @(posedge clk);
        default input #1 output #1;
        input done;
        input pending;
        input address_host;
        input address_device;
        input size;
        input dir_write;
    endclocking
    
    //driver modport
    modport DRIVER  (clocking driver_cb,input clk,reset);
    
    //monitor modport 
    modport MONITOR (clocking monitor_cb,input clk,reset);
endinterface

class transaction;
    rand bit [31:0] start_address_host;
    rand bit [31:0] start_address_device;
    rand bit [15:0] size;
    rand bit dir_write;
    rand bit [2:0] max_payload_size;
    rand bit [2:0] max_read_req_size;
    int full_transactions;
    int last_transaction_size;
    
    task display;
        $display("-----------------------------------------");
        $display("- Transaction");
        $display("- size = %d", {16'b0, size});
        $display("- dir_write = %d", dir_write);
        $display("- get_full_size = %d", get_full_size());
        $display("- full_transactions = %d", full_transactions);
        $display("- last_transaction_size = %d", last_transaction_size);
        $display("- resulting transfered size = %d", transfered_size());
        $display("-----------------------------------------");
    endtask
    
    function integer transfered_size();
        transfered_size = (full_transactions*get_full_size() + last_transaction_size);
    endfunction
    
    function integer get_full_size();
        if(dir_write) get_full_size = get_max_payload_size_bytes();
        else get_full_size = get_max_read_req_bytes();
    endfunction
    
    function integer get_max_read_req_bytes();
        case(max_read_req_size)
            default: get_max_read_req_bytes = 128;
            3'b000: get_max_read_req_bytes = 128;          
            3'b001: get_max_read_req_bytes = 256;         
            3'b010: get_max_read_req_bytes = 512;          
            3'b011: get_max_read_req_bytes = 1024;        
            3'b100: get_max_read_req_bytes = 2048;        
            3'b101: get_max_read_req_bytes = 4096;
        endcase
    endfunction
    
    function integer get_max_payload_size_bytes();
        case(max_payload_size)
            default: get_max_payload_size_bytes = 128;
            3'b000: get_max_payload_size_bytes = 128;          
            3'b001: get_max_payload_size_bytes = 256;         
            3'b010: get_max_payload_size_bytes = 512;          
            3'b011: get_max_payload_size_bytes = 1024;        
        endcase
    endfunction
endclass


class generator;

    rand transaction trans;
    
    mailbox gen2drv;
    
    int repeat_count;
    
    event ended;
    
    function new(mailbox gen2drv);
        this.gen2drv = gen2drv;
        this.ended = ended;
    endfunction
    
    task main();
        repeat(repeat_count) begin
            trans = new();
            if( !trans.randomize() ) $fatal("Gen:: trans randomization failed");
            gen2drv.put(trans);
        end
        -> ended;
    endtask

endclass


class driver;

    int no_transactions;
    int single_trans;
    virtual conf_intf conf_vif;
    virtual dma_intf dma_vif;
    
    mailbox gen2driv;
        
    function new(
        virtual conf_intf conf_vif, 
        virtual dma_intf dma_vif,
        mailbox gen2driv);
        this.conf_vif = conf_vif;
        this.dma_vif = dma_vif;
        this.gen2driv = gen2driv;
        this.no_transactions = 0;
    endfunction
    
    task reset;
        wait(dma_vif.reset && conf_vif.reset);
        $display("--------- [DRIVER] Reset Started ---------");
        `DRIV_IF(conf_vif).valid <= 0;
        `DRIV_IF(dma_vif).done <= 0;
        $display("--------- [DRIVER] Reset Ended ---------");
    endtask

    task main;
        forever begin
            transaction trans;
            gen2driv.get(trans);
            $display("--------- [DRIVER-TRANSFER: %0d] ---------",no_transactions);
            @(posedge conf_vif.clk);
            `DRIV_IF(conf_vif).pcie_decommand[7:5] <= trans.max_payload_size;
            `DRIV_IF(conf_vif).pcie_decommand[14:12] <= trans.max_read_req_size;
            repeat(5) @(posedge conf_vif.clk);
            `DRIV_IF(conf_vif).start_address_host <= trans.start_address_host;
            `DRIV_IF(conf_vif).start_address_device <= trans.start_address_device;
            `DRIV_IF(conf_vif).size <= trans.size;
            `DRIV_IF(conf_vif).dir_write <= trans.dir_write;
            `DRIV_IF(conf_vif).valid <= 1;
            @(posedge conf_vif.clk);
            `DRIV_IF(conf_vif).valid <= 0;
            `DRIV_IF(dma_vif).done <= 0;
            single_trans = 0;
            while (dma_vif.pending) begin
                if(dma_vif.size == trans.get_full_size) begin
                    trans.full_transactions = trans.full_transactions + 1;
                end else begin
                    trans.last_transaction_size = dma_vif.size;
                end
                `DRIV_IF(dma_vif).done <= 1;
                @(posedge dma_vif.clk);
            end
            
            if(trans.last_transaction_size == 0) begin
                trans.last_transaction_size = dma_vif.size;
            end else begin
                `DRIV_IF(dma_vif).done <= 0;
            end
            
            assert(conf_vif.transaction_done)
            else begin
                trans.display();
                $fatal("Transmission end not signaled");
            end
            
            @(posedge dma_vif.clk);

            `DRIV_IF(dma_vif).done <= 0;
            assert(trans.size == trans.transfered_size)
            else begin
                trans.display();
                $fatal("Resulting transmission doesnt match conf request");
            end
            $display("-----------------------------------------");
            no_transactions++;
        end
    endtask
endclass

class environment;

    generator   gen;
    driver      driv;
    
    mailbox     gen2driv;
    
    virtual conf_intf conf_vif;
    virtual dma_intf dma_vif;
    
    
    function new(virtual conf_intf conf_vif, virtual dma_intf dma_vif);
        this.conf_vif = conf_vif;
        this.dma_vif = dma_vif;
        
        gen2driv = new();
        gen = new(gen2driv);           
        driv = new (conf_vif, dma_vif, gen2driv);
    endfunction
    
    task pre_test();
        driv.reset();
    endtask
    
    task test();
        fork
            gen.main();
            driv.main();
        join_any
    endtask
    
    task post_test();
        wait(gen.ended.triggered);
        wait(gen.repeat_count == driv.no_transactions);
    endtask
    
    task run();
        pre_test();
        test();
        post_test();
        $finish;
    endtask
endclass

`endif