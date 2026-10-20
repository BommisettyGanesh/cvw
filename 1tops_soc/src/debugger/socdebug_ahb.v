//-----------------------------------------------------------------------------
// SoCDebug AHB Debug Controller for RISC-V SoC (CORE-V Wally)
// Adapted from SoC Labs SoCDebug Tech for CORE-V Wally / 1tops_soc
//-----------------------------------------------------------------------------

`timescale 1ns / 1ps

module socdebug_ahb #(
    parameter         PROMPT_CHAR   = "]"
)(  
    // AHB-lite Master Interface
    input  wire                     HCLK,
    input  wire                     HRESETn,
    output wire              [31:0] HADDR32_o,
    output wire              [ 2:0] HBURST3_o,
    output wire                     HMASTLOCK_o,
    output wire              [ 3:0] HPROT4_o,
    output wire              [ 2:0] HSIZE3_o,
    output wire              [ 1:0] HTRANS2_o,
    output wire              [31:0] HWDATA32_o,
    output wire                     HWRITE_o,
    input  wire              [31:0] HRDATA32_i,
    input  wire                     HREADY_i,
    input  wire                     HRESP_i,
    
    // Comms Byte Stream (AXI-Stream format from/to UART or USRT)
    // Stream to Host (Debugger TX -> Host RX)
    output wire                     COMTX_TVALID_o,
    output wire            [ 7:0]   COMTX_TDATA_o,
    input  wire                     COMTX_TREADY_i,
    // Stream from Host (Host TX -> Debugger RX)
    input  wire                     COMRX_TVALID_i,
    input  wire             [ 7:0]  COMRX_TDATA_i,
    output wire                     COMRX_TREADY_o,
    
    // STDIO Byte Stream (Optional terminal I/O bypass)
    output wire                     STDTX_TVALID_o,
    output wire            [ 7:0]   STDTX_TDATA_o,
    input  wire                     STDTX_TREADY_i,
    input  wire                     STDRX_TVALID_i,
    input  wire             [ 7:0]  STDRX_TDATA_i,
    output wire                     STDRX_TREADY_o,
    
    // Core Debug & Control Signals
    output wire                     core_halt_o,      // Connected to ExternalStall of RISC-V Core
    output wire                     core_reset_o,     // Core/System Reset request
    input  wire                     core_halted_i,    // Core Halted Status feedback
    output wire                     core_step_o,      // Core Step Request (GPO8[2])
    output wire                     core_step_mode_o, // Core Step Mode (GPO8[3]: 0=Instr, 1=Cycle)
    input  wire                     core_step_busy_i, // Core Step in progress (GPI8[1])
    input  wire                     core_step_done_i, // Core Step completed (GPI8[2])
    
    // Raw GPIO interface
    output wire               [7:0] GPO8_o,
    input  wire               [7:0] GPI8_i
);

    wire [7:0] gpo8_int;
    wire [7:0] gpi8_int;

    // Bit mapping for GPO8 (written via ADP command 'C'):
    // GPO8[0]: Reset request
    // GPO8[1]: Core halt request (ExternalStall)
    // GPO8[2]: Core single-step trigger (rising edge initiated)
    // GPO8[3]: Core single-step mode (0 = Instruction, 1 = Clock Cycle)
    // GPO8[7:4]: General purpose / future expansion
    assign GPO8_o           = gpo8_int;
    assign core_reset_o     = gpo8_int[0];
    assign core_halt_o      = gpo8_int[1];
    assign core_step_o      = gpo8_int[2];
    assign core_step_mode_o = gpo8_int[3];

    // Bit mapping for GPI8 (read via ADP command 'C'):
    // GPI8[0]: Core halted feedback status
    // GPI8[1]: Core step busy status (1 = stepping in flight, 0 = idle/halted)
    // GPI8[2]: Core step done status (1-cycle pulse upon completion)
    // GPI8[7:3]: User inputs / GPI8_i[7:3]
    assign gpi8_int = {GPI8_i[7:3], (core_step_done_i | GPI8_i[2]), (core_step_busy_i | GPI8_i[1]), (core_halted_i | GPI8_i[0])};

    // Instantiation of ADP AHB Controller
    socdebug_adp_control #(
        .PROMPT_CHAR (PROMPT_CHAR)
    ) u_adp_control (
        // AHB Interface
        .HCLK           (HCLK),
        .HRESETn        (HRESETn),
        .HADDR32_o      (HADDR32_o),
        .HBURST3_o      (HBURST3_o),
        .HMASTLOCK_o    (HMASTLOCK_o),
        .HPROT4_o       (HPROT4_o),
        .HSIZE3_o       (HSIZE3_o),
        .HTRANS2_o      (HTRANS2_o),
        .HWDATA32_o     (HWDATA32_o),
        .HWRITE_o       (HWRITE_o),
        .HRDATA32_i     (HRDATA32_i),
        .HREADY_i       (HREADY_i),
        .HRESP_i        (HRESP_i),
        
        // GPIO Interface
        .GPO8_o         (gpo8_int),
        .GPI8_i         (gpi8_int),
        
        // STDIO Interface
        .STDTX_TVALID_o (STDTX_TVALID_o),
        .STDTX_TDATA_o  (STDTX_TDATA_o ),
        .STDTX_TREADY_i (STDTX_TREADY_i),
        .STDRX_TVALID_i (STDRX_TVALID_i),
        .STDRX_TDATA_i  (STDRX_TDATA_i ),
        .STDRX_TREADY_o (STDRX_TREADY_o),
        
        // COMIO Interface
        .COMRX_TVALID_i (COMRX_TVALID_i),
        .COMRX_TDATA_i  (COMRX_TDATA_i ),
        .COMRX_TREADY_o (COMRX_TREADY_o),
        .COMTX_TVALID_o (COMTX_TVALID_o),
        .COMTX_TDATA_o  (COMTX_TDATA_o ),
        .COMTX_TREADY_i (COMTX_TREADY_i)
    );

endmodule
