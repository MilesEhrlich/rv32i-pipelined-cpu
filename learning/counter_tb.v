`timescale 1ns/1ps
module counter_tb;
    reg clk = 0, rst = 1, in = 0;
    wire [3:0] count;
    wire r1, r2;

    counter dut (.clk(clk), .rst(rst), .in(in),
                 .count(count), .r1(r1), .r2(r2));

    always #5 clk = ~clk;   // flip every 5ns, so a 10ns clock

    initial begin
        $dumpfile("counter.vcd");   // save waveforms here
        $dumpvars(0, counter_tb);

        #20 rst = 0;          // release reset after 2 clocks
        #30 in  = 1;          // pulse the input for one clock
        #10 in  = 0;
        #200;

        $display("Final count = %d", count);
        $finish;
    end
endmodule