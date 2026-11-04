`timescale 1ns/1ps
module alu_tb;
    reg  [31:0] a, b;
    reg  [2:0]  op;
    wire [31:0] result;
    wire        zero;
    integer errors = 0;

    alu dut (.a(a), .b(b), .op(op), .result(result), .zero(zero));

    // Reusable test: set inputs, wait, compare
    task check(input [2:0] t_op, input [31:0] t_a, input [31:0] t_b,
               input [31:0] expected);
        begin
            op = t_op; a = t_a; b = t_b;
            #1;
            if (result !== expected) begin
                $display("FAIL: op=%0d a=%h b=%h got %h expected %h",
                         t_op, t_a, t_b, result, expected);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        check(0, 5, 3, 8);                                      // add
        check(0, 32'hFFFFFFFF, 1, 0);                           // add wraps around
        check(1, 5, 3, 2);                                      // sub
        check(1, 3, 5, 32'hFFFFFFFE);                           // 3 - 5 = -2
        check(2, 32'hF0F0F0F0, 32'hFF00FF00, 32'hF000F000);     // and
        check(3, 32'hF0F0F0F0, 32'h0F0F0F0F, 32'hFFFFFFFF);     // or
        check(4, 32'hAAAA5555, 32'hFFFF0000, 32'h55555555);     // xor

        check(1, 7, 7, 0);                                      // 7 - 7 = 0
        if (zero !== 1) begin
            $display("FAIL: zero flag not set");
            errors = errors + 1;
        end

        if (errors == 0) $display("All ALU tests passed");
        else             $display("%0d errors", errors);
        $finish;
    end
endmodule