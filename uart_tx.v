// 8N1 UART transmitter. Pulse `start` with a byte while !busy.
// Default: 27 MHz / 234 = ~115200 baud (0.16% error).
module uart_tx #(parameter CLKS_PER_BIT = 234) (
    input  wire       clk,
    input  wire       rst,
    input  wire       start,
    input  wire [7:0] data,
    output reg        tx,
    output wire       busy
);
    reg [9:0]  shift;      // {stop, data[7:0], start}, sent LSB first
    reg [3:0]  bits_left;
    reg [15:0] count;

    assign busy = (bits_left != 0);

    always @(posedge clk) begin
        if (rst) begin
            tx <= 1'b1; bits_left <= 0; count <= 0;
        end else if (!busy) begin
            tx <= 1'b1;
            if (start) begin
                shift     <= {1'b1, data, 1'b0};
                bits_left <= 4'd10;
                count     <= 0;
            end
        end else begin
            tx <= shift[0];
            if (count == CLKS_PER_BIT - 1) begin
                count     <= 0;
                shift     <= {1'b1, shift[9:1]};
                bits_left <= bits_left - 1'b1;
            end else begin
                count <= count + 1'b1;
            end
        end
    end
endmodule
