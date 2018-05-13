`include "classes.sv"
`ifndef RANDOM_TEST_SV
`define RANDOM_TEST_SV
program test(conf_intf conf, dma_intf dma);
   
  //declaring environment instance
  environment env;
   
  initial begin
    //creating environment
    env = new(conf, dma);
     
    //setting the repeat count of generator as 10, means to generate 10 packets
    env.gen.repeat_count = 1024*1024;
     
    //calling run of env, it interns calls generator and driver main tasks.
    env.run();
  end
endprogram
`endif