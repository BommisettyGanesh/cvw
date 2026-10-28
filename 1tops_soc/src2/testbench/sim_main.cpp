#include <iostream>
#include "Vtb.h"
#include "verilated.h"
#include "verilated_vcd_c.h"

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    Verilated::traceEverOn(true);

    Vtb* tb = new Vtb;
    VerilatedVcdC* tfp = new VerilatedVcdC;
    tb->trace(tfp, 2);  // depth 2: captures AHB bus signals at SoC level, excluding core internals
    tfp->open("trace.vcd");

    // Reset sequence
    // Assert reset for 10 cycles
    tb->reset = 1;
    for(int i=0; i<10; i++) {
        tb->clk = 0;
        tb->eval();
        tb->clk = 1;
        tb->eval();
    }
    tb->reset = 0;

    int time = 50;
    // Run simulation for a set number of cycles (or until completion logic if added)
    for (int i=0; i<100000; i++) {
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

extern "C" const char* getenvval(const char* env_name) {
    const char* val = std::getenv(env_name);
    return val ? val : "";
}
