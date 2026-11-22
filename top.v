// Tang Nano 9K top level: the RV32I CPU plus its memory-mapped devices.
//   0x10000000  W  UART transmit byte (115200 8N1 over the board's USB)
//   0x10000008  R  cycle counter
//   0x1000000C  RW LEDs (bit = 1 means lit)
//   0x10000010  R  UART status (bit 0 = busy)
//   0x10000014  R  buttons (bit 0 = S1, bit 1 = S2; 1 = pressed)
// S1 also resets the CPU.
module top #(parameter PROGRAM = "sw/build/board.hex") (
    input  wire       clk,        // 27 MHz
    input  wire [1:0] btn,        // active low
    output wire [5:0] led,        // active low
    output wire       uart_tx
);
    // ---- Reset: held for a while after configuration, and while S1 is held ----
    reg [1:0]  btn_sync0, btn_sync;          // synchronize the async buttons
    always @(posedge clk) begin btn_sync0 <= ~btn; btn_sync <= btn_sync0; end

    reg [15:0] por = 0;
    wire       por_done = &por;
    always @(posedge clk) if (!por_done) por <= por + 1'b1;
    wire rst = !por_done || btn_sync[0];

    // ---- CPU ----
    wire        mmio_we, mmio_re;
    wire [31:0] mmio_addr, mmio_wdata;
    reg  [31:0] mmio_rdata;

    cpu #(.PROGRAM(PROGRAM), .DATA_FILE(PROGRAM)) u_cpu (
        .clk(clk), .rst(rst),
        .mmio_we(mmio_we), .mmio_re(mmio_re), .mmio_addr(mmio_addr),
        .mmio_wdata(mmio_wdata), .mmio_rdata(mmio_rdata));

    // ---- Registered I/O writes ----
    // Stores to devices are captured at the clock edge and acted on the next
    // cycle. This keeps the device logic off the CPU's critical path
    // (instruction -> registers -> ALU -> address decode).
    reg        wr_pending = 0;
    reg [7:0]  wr_addr;
    reg [31:0] wr_data;
    always @(posedge clk) begin
        wr_pending <= mmio_we && !rst;
        wr_addr    <= mmio_addr[7:0];
        wr_data    <= mmio_wdata;
    end

    // ---- Devices ----
    reg [31:0] cycles = 0;
    always @(posedge clk) cycles <= rst ? 32'd0 : cycles + 1'b1;

    reg [5:0] led_reg = 0;
    always @(posedge clk)
        if (rst) led_reg <= 0;
        else if (wr_pending && wr_addr == 8'h0C) led_reg <= wr_data[5:0];
    assign led = ~led_reg;

    wire uart_busy;
    uart_tx u_uart (.clk(clk), .rst(rst),
                    .start(wr_pending && wr_addr == 8'h00),
                    .data(wr_data[7:0]), .tx(uart_tx), .busy(uart_busy));

    always @(*) begin
        case (mmio_addr[7:0])
            8'h08:   mmio_rdata = cycles;
            8'h0C:   mmio_rdata = {26'd0, led_reg};
            8'h10:   mmio_rdata = {31'd0, uart_busy | (wr_pending && wr_addr == 8'h00)};
            8'h14:   mmio_rdata = {30'd0, btn_sync};
            default: mmio_rdata = 32'd0;
        endcase
    end
endmodule
