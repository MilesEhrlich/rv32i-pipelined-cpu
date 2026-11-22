module counter (
    input  wire       clk,
    input  wire       rst,     // reset: 1 = clear everything
    input  wire       in,
    output reg  [3:0] count,
    output reg        r1,
    output reg        r2
);
    always @(posedge clk) begin
        if (rst) begin
            count <= 0;
            r1    <= 0;
            r2    <= 0;
        end else begin
            count <= count + 1;
            r1    <= in;
            r2    <= r1;
        end
    end
endmodule