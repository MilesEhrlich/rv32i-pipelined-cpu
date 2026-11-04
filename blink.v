module top (
    input  wire       clk,   // 27 MHz clock from the board
    output wire [5:0] led    // 6 onboard LEDs
);
    reg [23:0] counter = 0;  // counts clock ticks
    reg [5:0]  value   = 0;  // what we display

    always @(posedge clk) begin
        if (counter == 24'd13_499_999) begin
            counter <= 0;
            value   <= value + 1;
        end else begin
            counter <= counter + 1;
        end
    end

    assign led = ~value;     // LEDs turn on when the pin is 0
endmodule