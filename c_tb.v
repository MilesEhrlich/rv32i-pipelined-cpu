`timescale 1ns/1ps
// Runs a compiled C program on the CPU and acts as its I/O devices:
//   0x10000000  write: print a character to the simulator console
//   0x10000004  write: end the simulation with an exit code (0 = pass)
//   0x10000008  read:  cycle counter since reset
// Pick the program with:  iverilog -P c_tb.PROGRAM=\"sw/build/foo.hex\" ...
module c_tb;
    parameter PROGRAM   = "sw/build/hello.hex";
    parameter MAX_CYCLES = 2_000_000;

    reg clk = 0, rst = 1;
    always #5 clk = ~clk;

    wire        mmio_we, mmio_re;
    wire [31:0] mmio_addr, mmio_wdata;
    reg  [31:0] mmio_rdata;
    reg  [31:0] cycles = 0;

    cpu #(.PROGRAM(PROGRAM), .DATA_FILE(PROGRAM)) dut (
        .clk(clk), .rst(rst),
        .mmio_we(mmio_we), .mmio_re(mmio_re), .mmio_addr(mmio_addr),
        .mmio_wdata(mmio_wdata), .mmio_rdata(mmio_rdata));

    always @(*) begin
        case (mmio_addr)
            32'h10000008: mmio_rdata = cycles;
            default:      mmio_rdata = 32'd0;
        endcase
    end

    always @(posedge clk) begin
        if (!rst) cycles <= cycles + 1;
        if (mmio_we) begin
            case (mmio_addr)
                32'h10000000: $write("%c", mmio_wdata[7:0]);
                32'h10000004: begin
                    $display("--- program exited with code %0d after %0d cycles ---",
                             mmio_wdata, cycles);
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
