`timescale 1ns/1ps
// Runs a compiled C program on the CPU and acts as its I/O devices:
//   0x10000000  write: print a character to the simulator console
//   0x10000004  write: end the simulation with an exit code (0 = pass)
//   0x10000008  read:  cycle counter since reset
//   0x10000018  read:  instructions retired since reset
// Pick the program with:  iverilog -P c_tb.PROGRAM=\"sw/build/foo.hex\" ...
module c_tb;
    parameter PROGRAM   = "sw/build/hello.hex";
    parameter MAX_CYCLES = 2_000_000;

    reg clk = 0, rst = 1;
    always #5 clk = ~clk;

    wire        mmio_we, mmio_re;
    wire [31:0] mmio_addr, mmio_wdata;
    reg  [31:0] mmio_rdata;
    reg  [31:0] cycles = 0, instret = 0;
    wire        retire;

`ifdef SINGLE_CYCLE
    cpu      #(.PROGRAM(PROGRAM), .DATA_FILE(PROGRAM)) dut (
`else
    cpu_pipe #(.PROGRAM(PROGRAM), .DATA_FILE(PROGRAM)) dut (
`endif
        .clk(clk), .rst(rst),
        .mmio_we(mmio_we), .mmio_re(mmio_re), .mmio_addr(mmio_addr),
        .mmio_wdata(mmio_wdata), .mmio_rdata(mmio_rdata), .retire(retire));

    always @(*) begin
        case (mmio_addr)
            32'h10000008: mmio_rdata = cycles;
            32'h10000018: mmio_rdata = instret;
            32'h1000001C: mmio_rdata = 27_000_000;
            default:      mmio_rdata = 32'd0;
        endcase
    end

    always @(posedge clk) begin
        if (!rst) cycles <= cycles + 1;
        if (retire) instret <= instret + 1;
        if (mmio_we) begin
            case (mmio_addr)
                32'h10000000: $write("%c", mmio_wdata[7:0]);
                32'h10000004: begin
                    $display("--- program exited with code %0d after %0d cycles, %0d instructions (CPI %0.3f) ---",
                             mmio_wdata, cycles, instret, cycles * 1.0 / instret);
                    if (mmio_wdata == 0) $display("C TEST PASSED");
                    else                 $display("C TEST FAILED");
                    $finish;
                end
                32'h1000000C: ;   // LEDs: nothing to show in simulation
                default: $display("warning: store to unmapped I/O address %h", mmio_addr);
            endcase
        end
        if (cycles >= MAX_CYCLES) begin
            $display("C TEST FAILED: timeout after %0d cycles (pc = %h)", cycles, dut.pc);
            $finish;
        end
    end

    initial begin
        #12 rst = 0;
    end
endmodule
