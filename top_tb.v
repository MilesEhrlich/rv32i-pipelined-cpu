`timescale 1ns/1ps
// Simulates the whole board design (top.v) and decodes the UART TX pin
// like a real serial port would, printing what the board will send.
module top_tb;
    localparam CLKS_PER_BIT = 234;
    reg clk = 0;
    always #18.5 clk = ~clk;              // 27 MHz

    reg  [1:0] btn = 2'b11;               // not pressed (active low)
    wire [5:0] led;
    wire       tx;
    top dut (.clk(clk), .btn(btn), .led(led), .uart_tx(tx));

    // UART receiver: wait for start bit, sample each bit in its middle
    reg [7:0] ch;
    integer i, lines = 0;
    initial begin
        forever begin
            @(negedge tx);
            repeat (CLKS_PER_BIT / 2) @(posedge clk);
            if (tx !== 1'b0) $display("\n[framing error: bad start bit]");
            for (i = 0; i < 8; i = i + 1) begin
                repeat (CLKS_PER_BIT) @(posedge clk);
                ch[i] = tx;
            end
            repeat (CLKS_PER_BIT) @(posedge clk);
            if (tx !== 1'b1) $display("\n[framing error: bad stop bit]");
            $write("%c", ch);
            if (ch == 8'h0A) begin
                lines = lines + 1;
                if (lines == 4) begin
                    $display("[LEDs = %b]", ~led);
                    $finish;
                end
            end
        end
    end

    initial begin
        #(37.037 * 3_000_000);
        $display("\nTIMEOUT");
        $finish;
    end
endmodule
