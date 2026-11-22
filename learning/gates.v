module top (
    input  wire       clk,
    input  wire [1:0] btn,   // the two buttons
    output wire [5:0] led
);
    // Buttons read 0 when pressed, so flip them:
    // a = 1 means button A is pressed
    wire a = ~btn[0];
    wire b = ~btn[1];

    wire [5:0] result;
    assign result[0] = a & b;     // AND: both pressed
    assign result[1] = a | b;     // OR: either pressed
    assign result[2] = a ^ b;     // XOR: exactly one pressed
    assign result[3] = ~a;        // NOT: A not pressed
    assign result[4] = ~(a & b);  // NAND: not both
    assign result[5] = 0;         // unused, stays off

    assign led = ~result;         // LEDs are on when the pin is 0
endmodule
