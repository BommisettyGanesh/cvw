#include <iostream>
#include "Vtb.h"
#include "verilated.h"
#include "verilated_vcd_c.h"

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    Verilated::traceEverOn(true);

    Vtb* tb = new Vtb;
    VerilatedVcdC* tfp = new VerilatedVcdC;
    tb->trace(tfp, 99);
    tfp->open("trace.vcd");

    // Reset sequence
    tb->reset = 1;
    tb->clk = 0;

    for (int i=0; i<10; i++) {
        tb->clk = !tb->clk;
        tb->eval();
        tfp->dump(i*5);
    }

    tb->reset = 0;

    int time = 50;
    // Run simulation for a set number of cycles (or until completion logic if added)
    for (int i=0; i<5000; i++) {
        tb->clk = !tb->clk;
        tb->eval();
        tfp->dump(time);
        time += 5;
    }

    tb->final();
    tfp->close();
    delete tb;
    return 0;
}
