`timescale 1ns/1ps
module cpu_tb;
    reg clk = 0, rst = 1;
    always #5 clk = ~clk;
    integer errors = 0;

    cpu dut (.clk(clk), .rst(rst), .mmio_rdata(32'd0));

    task check_reg(input [4:0] r, input [31:0] want);
        if (dut.u_rf.regs[r] !== want) begin
            $display("FAIL x%0d: got %h, expected %h", r, dut.u_rf.regs[r], want);
            errors = errors + 1;
        end
    endtask

    initial begin
        $dumpfile("cpu.vcd");
        $dumpvars(0, cpu_tb);
        #12 rst = 0;
        #1000;   // ~100 cycles, plenty for this program

        check_reg(1, 55);              // sum of 1..10
        check_reg(2, 11);
        check_reg(3, 11);
        check_reg(4, 55);              // loaded back from memory
        check_reg(5, 32'h12345000);    // lui
        check_reg(6, 32'h00000028);    // jal return address
        check_reg(7, 0);               // skipped instruction never ran
        check_reg(8, 32'hFFFFFFC9);    // -55
        if (dut.pc !== 32'h30) begin
            $display("FAIL pc: got %h, expected 00000030", dut.pc);
            errors = errors + 1;
        end

        if (errors == 0) $display("CPU test passed: program ran correctly");
        else             $display("%0d errors", errors);
        $finish;
    end
endmodule