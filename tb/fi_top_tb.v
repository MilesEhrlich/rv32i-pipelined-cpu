// Simulates rtl/fi_top.v for a few trials and prints each report as it is
// assembled (no UART decoding needed). TEXT_END is the end of .text (llvm-objdump -h):
//   iverilog -g2012 -DFI_PORTS -DPROG='"sw/build/digits.hex"' -DPAR=0 -DTEXT_END=32'h6a4 \
//     -DTRIALS=4 -o build/fi_top_tb tb/fi_top_tb.v rtl/fi_top.v rtl/cpu_core.v rtl/regfile.v \
//     rtl/alu.v rtl/imm_gen.v rtl/imem.v rtl/bram_be.v rtl/uart_tx.v && vvp -n build/fi_top_tb
`timescale 1ns/1ps
module fi_top_tb;
    reg clk = 0;
    always #5 clk = ~clk;
    wire [5:0] led; wire tx;
    fi_top #(.PROGRAM(`PROG), .PARITY(`PAR), .TEXT_END(`TEXT_END), .CLKS_PER_BIT(2))
        dut (.clk(clk), .btn(2'b00), .led(led), .uart_tx(tx));
    integer n = 0;
    always @(posedge clk)
        if (dut.state == 6 && !dut.tx_wait) begin
            $display("trial %0d tgt=%0d reg=%0d bit=%0d img=%0d fire=%0d gcyc=%0d gclass=%0d gchk=%08x gflags=%02x | flags=%02x exit=%0d class=%0d chk=%08x cyc=%0d",
                dut.trial, dut.tgt, dut.t_reg, dut.t_bit, dut.image, dut.fire_cyc, dut.g_cycles,
                dut.g_class, dut.g_check, dut.g_flags, dut.flags, dut.exit_code, dut.result, dut.check, dut.cyc);
            n = n + 1;
            if (n == `TRIALS) $finish;
        end
endmodule
