///////////////////////////////////////////
// wallypipelinedcore.sv
//
// Upgraded Core Wrapper for CORE-V Wally RISC-V SoC (1tops_soc)
// Integrating 5-Stage Pipelined RV32I Processor (riscv_cpu)
///////////////////////////////////////////

module wallypipelinedcore import cvw::*; #(parameter cvw_t P) (
   input  logic                  clk, reset,
   // Privileged Interrupts from CLINT & PLIC
   input  logic                  MTimerInt, MExtInt, SExtInt, MSwInt,
   input  logic [63:0]           MTIME_CLINT,
   // AMBA 3 AHB-Lite Master Bus Interface
   input  logic [P.AHBW-1:0]     HRDATA,
   input  logic                  HREADY, HRESP,
   output logic                  HCLK, HRESETn,
   output logic [P.PA_BITS-1:0]  HADDR,
   output logic [P.AHBW-1:0]     HWDATA,
   output logic [P.XLEN/8-1:0]   HWSTRB,
   output logic                  HWRITE,
   output logic [2:0]            HSIZE,
   output logic [2:0]            HBURST,
   output logic [3:0]            HPROT,
   output logic [1:0]            HTRANS,
   output logic                  HMASTLOCK,
   // Debugger / Step Controller
   input  logic                  ExternalStall,
   output logic                  InstrRetired
);

  assign HCLK    = clk;
  assign HRESETn = ~reset;

  // 32-bit internal buses from riscv_cpu
  wire [31:0] core_HADDR;
  wire [31:0] core_HWDATA;
  wire [ 3:0] core_HWSTRB;

  localparam [31:0] RESET_PC = P.RESET_VECTOR[31:0];

  riscv_cpu #(
    .RESET_PC(RESET_PC)
  ) cpu (
    .HCLK          (clk),
    .HRESETn       (~reset),
    .HADDR         (core_HADDR),
    .HWDATA        (core_HWDATA),
    .HWSTRB        (core_HWSTRB),
    .HWRITE        (HWRITE),
    .HSIZE         (HSIZE),
    .HBURST        (HBURST),
    .HPROT         (HPROT),
    .HTRANS        (HTRANS),
    .HMASTLOCK     (HMASTLOCK),
    .HRDATA        (HRDATA[31:0]),
    .HREADY        (HREADY),
    .HRESP         (HRESP),
    .PC            (),
    .PCW           (),
    .ALUResultW    (),
    .WriteDataW    (),
    .Result        (),
    .MTimerInt     (MTimerInt),
    .MSwInt        (MSwInt),
    .MExtInt       (MExtInt),
    .MTIME_CLINT   (MTIME_CLINT),
    .ExternalStall (ExternalStall),
    .InstrRetired  (InstrRetired),
    .TrapM         (),
    .mretM         ()
  );

  // Match physical address width P.PA_BITS
  if (P.PA_BITS >= 32)
    assign HADDR = { {(P.PA_BITS-32){1'b0}}, core_HADDR };
  else
    assign HADDR = core_HADDR[P.PA_BITS-1:0];

  // Match AHB bus data width P.AHBW
  if (P.AHBW >= 32)
    assign HWDATA = { {(P.AHBW-32){1'b0}}, core_HWDATA };
  else
    assign HWDATA = core_HWDATA[P.AHBW-1:0];

  // Match byte strobe width P.XLEN/8
  if (P.XLEN/8 >= 4)
    assign HWSTRB = { {(P.XLEN/8-4){1'b0}}, core_HWSTRB };
  else
    assign HWSTRB = core_HWSTRB[P.XLEN/8-1:0];

endmodule
