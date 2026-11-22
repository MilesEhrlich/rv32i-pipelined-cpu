// Tang Nano 9K top level: the RV32I CPU plus its memory-mapped devices.
//   0x10000000  W  UART transmit byte (115200 8N1 over the board's USB)
//   0x10000008  R  cycle counter
//   0x1000000C  RW LEDs (bit = 1 means lit)
//   0x10000010  R  UART status (bit 0 = busy)
//   0x10000014  R  buttons (bit 0 = S1, bit 1 = S2; 1 = pressed)
//   0x10000018  R  instructions retired
//   0x1000001C  R  system clock frequency in Hz
// S1 also resets the CPU.
//
// Clock: the pipelined core runs at 40.5 MHz from the PLL (27 MHz x 3/2;
// its Fmax is ~44 MHz). The single-cycle core (Fmax ~28 MHz) runs directly
// from the 27 MHz oscillator.
module top #(parameter PROGRAM = "sw/build/board.hex") (
    input  wire       clk,        // 27 MHz oscillator
    input  wire [1:0] btn,        // active low
    output wire [5:0] led,        // active low
    output wire       uart_tx
);
`ifdef SINGLE_CYCLE
    localparam CLK_HZ = 27_000_000;
    wire sys_clk = clk;
    wire pll_lock = 1'b1;
`else
    localparam CLK_HZ = 40_500_000;
    wire sys_clk, pll_lock;
  `ifdef SYNTHESIS
    // 27 MHz / (IDIV_SEL+1) * (FBDIV_SEL+1) = 27 / 2 * 3 = 40.5 MHz
    // VCO = 40.5 MHz * ODIV(16) = 648 MHz (must be 400..1200 MHz)
    rPLL #(
        .FCLKIN("27"), .DEVICE("GW1NR-9C"),
        .IDIV_SEL(1), .DYN_IDIV_SEL("false"),
        .FBDIV_SEL(2), .DYN_FBDIV_SEL("false"),
        .ODIV_SEL(16), .DYN_ODIV_SEL("false"),
        .PSDA_SEL("0000"), .DYN_DA_EN("false"), .DUTYDA_SEL("1000"),
        .CLKOUT_FT_DIR(1'b1), .CLKOUTP_FT_DIR(1'b1),
        .CLKOUT_DLY_STEP(0), .CLKOUTP_DLY_STEP(0),
        .CLKFB_SEL("internal"), .CLKOUT_BYPASS("false"),
        .CLKOUTP_BYPASS("false"), .CLKOUTD_BYPASS("false"),
        .DYN_SDIV_SEL(2), .CLKOUTD_SRC("CLKOUT"), .CLKOUTD3_SRC("CLKOUT")
    ) u_pll (
        .CLKIN(clk), .CLKFB(1'b0), .RESET(1'b0), .RESET_P(1'b0),
        .FBDSEL(6'd0), .IDSEL(6'd0), .ODSEL(6'd0), .PSDA(4'd0),
        .DUTYDA(4'd0), .FDLY(4'd0),
        .CLKOUT(sys_clk), .LOCK(pll_lock), .CLKOUTP(), .CLKOUTD(), .CLKOUTD3());
  `else
    assign sys_clk = clk;          // simulation: testbench drives the system clock
    assign pll_lock = 1'b1;
  `endif
`endif

    // ---- Reset: until the PLL locks, for a while after that, and while S1 is held ----
    reg [1:0]  btn_sync0, btn_sync;          // synchronize the async buttons
    always @(posedge sys_clk) begin btn_sync0 <= ~btn; btn_sync <= btn_sync0; end

    reg [15:0] por = 0;
    wire       por_done = &por;
    always @(posedge sys_clk)
        if (!pll_lock)     por <= 0;
        else if (!por_done) por <= por + 1'b1;
    wire rst = !por_done || btn_sync[0];

    // ---- CPU ----
    wire        mmio_we, mmio_re;
    wire [31:0] mmio_addr, mmio_wdata;
    reg  [31:0] mmio_rdata;
    wire        retire;

`ifdef SINGLE_CYCLE
    cpu      #(.PROGRAM(PROGRAM), .DATA_FILE(PROGRAM)) u_cpu (
`else
    cpu_pipe #(.PROGRAM(PROGRAM), .DATA_FILE(PROGRAM)) u_cpu (
`endif
        .clk(sys_clk), .rst(rst),
        .mmio_we(mmio_we), .mmio_re(mmio_re), .mmio_addr(mmio_addr),
        .mmio_wdata(mmio_wdata), .mmio_rdata(mmio_rdata), .retire(retire));

    // ---- Registered I/O writes ----
    // Stores to devices are captured at the clock edge and acted on the next
    // cycle, keeping the device logic off the CPU's critical path.
    reg        wr_pending = 0;
    reg [7:0]  wr_addr;
    reg [31:0] wr_data;
    always @(posedge sys_clk) begin
        wr_pending <= mmio_we && !rst;
        wr_addr    <= mmio_addr[7:0];
        wr_data    <= mmio_wdata;
    end

    // ---- Devices ----
    reg [31:0] cycles = 0;
    always @(posedge sys_clk) cycles <= rst ? 32'd0 : cycles + 1'b1;
    reg [31:0] instret = 0;
    always @(posedge sys_clk) instret <= rst ? 32'd0 : instret + retire;

    reg [5:0] led_reg = 0;
    always @(posedge sys_clk)
        if (rst) led_reg <= 0;
        else if (wr_pending && wr_addr == 8'h0C) led_reg <= wr_data[5:0];
    assign led = ~led_reg;

    wire uart_busy;
    uart_tx #(.CLKS_PER_BIT((CLK_HZ + 57_600) / 115_200)) u_uart (
        .clk(sys_clk), .rst(rst),
        .start(wr_pending && wr_addr == 8'h00),
        .data(wr_data[7:0]), .tx(uart_tx), .busy(uart_busy));

    always @(*) begin
        case (mmio_addr[7:0])
            8'h08:   mmio_rdata = cycles;
            8'h0C:   mmio_rdata = {26'd0, led_reg};
            8'h10:   mmio_rdata = {31'd0, uart_busy | (wr_pending && wr_addr == 8'h00)};
            8'h14:   mmio_rdata = {30'd0, btn_sync};
            8'h18:   mmio_rdata = instret;
            8'h1C:   mmio_rdata = CLK_HZ;
            default: mmio_rdata = 32'd0;
        endcase
    end
endmodule
