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
    output wire                     core_halt_o,     // Connected to ExternalStall of RISC-V Core
    output wire                     core_reset_o,    // Core/System Reset request
    input  wire                     core_halted_i,   // Core Halted Status feedback
    
    // Raw GPIO interface
    output wire               [7:0] GPO8_o,
    input  wire               [7:0] GPI8_i
);

    wire [7:0] gpo8_int;
    wire [7:0] gpi8_int;

    // Bit mapping for GPO8 (written via ADP command 'C'):
    // GPO8[0]: Reset request
    // GPO8[1]: Core halt request (ExternalStall)
    // GPO8[7:2]: General purpose / future expansion
    assign GPO8_o       = gpo8_int;
    assign core_reset_o = gpo8_int[0];
    assign core_halt_o  = gpo8_int[1];

    // Bit mapping for GPI8 (read via ADP command 'C'):
    // GPI8[0]: Core halted feedback status
    // GPI8[7:1]: User inputs / GPI8_i[7:1]
    assign gpi8_int = {GPI8_i[7:1], core_halted_i};

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
