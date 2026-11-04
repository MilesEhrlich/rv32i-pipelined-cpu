`timescale 1ns/1ps
module adder_tb;
    reg  [3:0] a, b;
    wire [3:0] sum;
    wire       cout;
    integer i, j, errors = 0;

    adder4 dut (.a(a), .b(b), .sum(sum), .cout(cout));

    initial begin
        for (i = 0; i < 16; i = i + 1) begin
            for (j = 0; j < 16; j = j + 1) begin
                a = i; b = j;
                #1;   // let the logic settle
                if ({cout, sum} !== i + j) begin
                    $display("FAIL: %0d + %0d gave %0d", i, j, {cout, sum});
                    errors = errors + 1;
                end
            end
        end
        if (errors == 0) $display("All 256 tests passed");
        else             $display("%0d errors", errors);
        $finish;
    end
endmodule