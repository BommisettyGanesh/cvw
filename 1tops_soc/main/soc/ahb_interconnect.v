// =============================================================================
// Module: ahb_interconnect
// Purpose: AHB-Lite Bus Decoder & Multiplexer (RAM, UART, CLINT)
// =============================================================================

module ahb_interconnect (
    input             HCLK,
    input             HRESETn,

    // From Core AHB Master
    input      [31:0] HADDR,
    input      [31:0] HWDATA,
    input      [ 3:0] HWSTRB,
    input             HWRITE,
    input      [ 2:0] HSIZE,
    input      [ 1:0] HTRANS,
    output     [31:0] HRDATA,
    output            HREADY,
    output            HRESP,

    // Slave 0: RAM (0x8000_0000 - 0x87FF_FFFF)
    output            HSEL_RAM,
    input      [31:0] HRDATA_RAM,
    input             HREADYOUT_RAM,
    input             HRESP_RAM,

    // Slave 1: UART (0x1000_0000 - 0x1000_0FFF)
    output            HSEL_UART,
    input      [31:0] HRDATA_UART,
    input             HREADYOUT_UART,
    input             HRESP_UART,

    // Slave 2: CLINT Timer (0x0200_0000 - 0x0200_FFFF)
    output            HSEL_CLINT,
    input      [31:0] HRDATA_CLINT,
    input             HREADYOUT_CLINT,
    input             HRESP_CLINT
);

    // Address Decode
    assign HSEL_RAM   = (HADDR >= 32'h8000_0000 && HADDR <= 32'h87FF_FFFF);
    assign HSEL_UART  = (HADDR >= 32'h1000_0000 && HADDR <= 32'h1000_0FFF);
    assign HSEL_CLINT = (HADDR >= 32'h0200_0000 && HADDR <= 32'h0200_FFFF);

    // Register active slave for Data Phase multiplexing
    reg [1:0] active_slave_d;
    always @(posedge HCLK or negedge HRESETn) begin
        if (!HRESETn)
            active_slave_d <= 2'd0;
        else if (HREADY) begin
            if (HSEL_RAM)        active_slave_d <= 2'd0;
            else if (HSEL_UART)  active_slave_d <= 2'd1;
            else if (HSEL_CLINT) active_slave_d <= 2'd2;
            else                 active_slave_d <= 2'd0;
        end
    end

    // Multiplex Read Data and Response from selected slave
    assign HRDATA = (active_slave_d == 2'd0) ? HRDATA_RAM :
                    (active_slave_d == 2'd1) ? HRDATA_UART :
                    (active_slave_d == 2'd2) ? HRDATA_CLINT : 32'd0;

    assign HREADY = (active_slave_d == 2'd0) ? HREADYOUT_RAM :
                    (active_slave_d == 2'd1) ? HREADYOUT_UART :
                    (active_slave_d == 2'd2) ? HREADYOUT_CLINT : 1'b1;

    assign HRESP  = (active_slave_d == 2'd0) ? HRESP_RAM :
                    (active_slave_d == 2'd1) ? HRESP_UART :
                    (active_slave_d == 2'd2) ? HRESP_CLINT : 1'b0;

endmodule
