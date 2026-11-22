// FPGA build of the pipelined CPU: cpu_core plus block-RAM instruction and
// data memories. Same ports as the single-cycle cpu.v, so either can sit in
// top.v / c_tb.v. See cpu_core.v for the pipeline itself.
module cpu_pipe #(
    parameter PROGRAM   = "",
    parameter DATA_FILE = "",
    parameter MEM_WORDS = 2048
) (
    input  wire        clk,
    input  wire        rst,
    output wire        mmio_we,
    output wire        mmio_re,
    output wire [31:0] mmio_addr,
    output wire [31:0] mmio_wdata,
    input  wire [31:0] mmio_rdata,
    output wire        retire
);
    wire [31:0] imem_addr, imem_rdata, dmem_addr, dmem_wdata, dmem_rdata, pc;
    wire        dmem_we;
    wire [3:0]  dmem_be;

    cpu_core u_core (
        .clk(clk), .rst(rst),
        .imem_addr(imem_addr), .imem_rdata(imem_rdata),
        .dmem_addr(dmem_addr), .dmem_we(dmem_we), .dmem_be(dmem_be),
        .dmem_wdata(dmem_wdata), .dmem_rdata(dmem_rdata),
        .mmio_we(mmio_we), .mmio_re(mmio_re), .mmio_addr(mmio_addr),
        .mmio_wdata(mmio_wdata), .mmio_rdata(mmio_rdata),
        .retire(retire), .pc(pc));

    imem #(.WORDS(MEM_WORDS), .FILE(PROGRAM)) u_imem (
        .clk(clk), .addr(imem_addr), .instr(imem_rdata));

    bram_be #(.WORDS(MEM_WORDS), .FILE(DATA_FILE)) u_dmem (
        .clk(clk), .addr(dmem_addr), .we(dmem_we), .be(dmem_be),
        .wdata(dmem_wdata), .rdata(dmem_rdata));
endmodule
