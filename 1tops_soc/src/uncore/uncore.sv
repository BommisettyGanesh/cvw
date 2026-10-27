
module uncore #(
    parameter MEM_SIZE_BYTES    = 16384,
    parameter IRAM_BASE         = 32'h8000_0000,
    parameter IRAM_SIZE_BYTES   = MEM_SIZE_BYTES / 2,
    parameter DRAM_BASE         = IRAM_BASE + (MEM_SIZE_BYTES / 2),
    parameter DRAM_SIZE_BYTES   = MEM_SIZE_BYTES / 2,
    parameter XLEN              = 32,
    parameter BOOTROM_SUPPORTED = 0,
    parameter SPI_SUPPORTED     = 1,
    parameter CLINT_SUPPORTED   = 1,
    parameter PLIC_SUPPORTED    = 1,
    parameter UART_SUPPORTED    = 1,
    parameter GPIO_SUPPORTED    = 1
)(
    input  logic                 HCLK,
    input  logic                 HRESETn,
    input  logic                 TIMECLK,

    // AHB Bus Master Interface (connected to CPU Core)
    input  logic [31:0]          HADDR,
    input  logic [XLEN-1:0]      HWDATA,
    input  logic [XLEN/8-1:0]    HWSTRB,
    input  logic                 HWRITE,
    input  logic [ 2:0]          HSIZE,
    input  logic [ 2:0]          HBURST,
    input  logic [ 3:0]          HPROT,
    input  logic [ 1:0]          HTRANS,
    input  logic                 HMASTLOCK,
    input  logic                 HREADY,
    output logic [XLEN-1:0]      HRDATA,
    output logic                 HREADYOUT,
    output logic                 HRESP,

    // External AHB Slave / Accelerator Interface (EXT_MEM: 0x3000_0000 - 0x30FF_FFFF)
    output logic                 HSELEXT,
    input  logic [XLEN-1:0]      HRDATAEXT,
    input  logic                 HREADYEXT,
    input  logic                 HRESPEXT,

    // Interrupt & Timer Signals to Core
    output logic                 MTimerInt,
    output logic                 MSwInt,
    output logic                 MExtInt,
    output logic                 SExtInt,
    output logic [63:0]          MTIME_CLINT,

    // Peripheral I/O Pins
    input  logic [31:0]          GPIOIN,
    output logic [31:0]          GPIOOUT,
    output logic [31:0]          GPIOEN,
    input  logic                 UARTSin,
    output logic                 UARTSout,
    input  logic                 SPIIn,
    output logic                 SPIOut,
    output logic [3:0]           SPICS,
    output logic                 SPICLK,
    input  logic                 SDCIn,
    output logic                 SDCCmd,
    output logic [3:0]           SDCCS,
    output logic                 SDCCLK
);

    // Default SDC un-driven lines
    assign SDCCmd = 1'b0;
    assign SDCCS  = 4'hF;
    assign SDCCLK = 1'b0;

    // =========================================================================
    // 1. AHB Address Decoding
    // =========================================================================
    wire HSELRam_I   = (HADDR >= IRAM_BASE && HADDR < (IRAM_BASE + IRAM_SIZE_BYTES));
    wire HSELRam_D   = (HADDR >= DRAM_BASE && HADDR < (DRAM_BASE + DRAM_SIZE_BYTES));
    wire HSELEXT_int = (HADDR >= 32'h3000_0000 && HADDR <= 32'h30FF_FFFF);
    wire HSELBootRom = (HADDR >= 32'h0000_1000 && HADDR <= 32'h0000_1FFF);
    wire HSELCLINT   = (HADDR >= 32'h0200_0000 && HADDR <= 32'h0200_FFFF);
    wire HSELPLIC    = (HADDR >= 32'h0C00_0000 && HADDR <= 32'h0FFF_FFFF);
    wire HSELUART    = (HADDR >= 32'h1000_0000 && HADDR <= 32'h1000_0FFF);
    wire HSELSPI     = (HADDR >= 32'h1004_0000 && HADDR <= 32'h1004_0FFF);
    wire HSELGPIO    = (HADDR >= 32'h1006_0000 && HADDR <= 32'h1006_0FFF);

    assign HSELEXT = HSELEXT_int;

    localparam APB_PERIPHS = 5;
    wire [APB_PERIPHS-1:0] HSEL_APB = {HSELGPIO, HSELSPI, HSELUART, HSELPLIC, HSELCLINT};
    wire                   HSELBRIDGE = |HSEL_APB;

    // =========================================================================
    // 2. Address Decoder Delay Registers for AHB Data Phase
    // =========================================================================
    logic HSELRam_ID, HSELRam_DD, HSELEXTD, HSELBootRomD, HSELBRIDGED, HSELNoneD;

    always_ff @(posedge HCLK or negedge HRESETn) begin
        if (!HRESETn) begin
            HSELRam_ID    <= 1'b0;
            HSELRam_DD    <= 1'b0;
            HSELEXTD      <= 1'b0;
            HSELBootRomD  <= 1'b0;
            HSELBRIDGED   <= 1'b0;
            HSELNoneD     <= 1'b1;
        end else if (HREADY) begin
            HSELRam_ID    <= HSELRam_I;
            HSELRam_DD    <= HSELRam_D;
            HSELEXTD      <= HSELEXT_int;
            HSELBootRomD  <= HSELBootRom;
            HSELBRIDGED   <= HSELBRIDGE;
            HSELNoneD     <= !(HSELRam_I | HSELRam_D | HSELEXT_int | HSELBootRom | HSELBRIDGE);
        end
    end

    // =========================================================================
    // 3. AHB On-Chip Instruction RAM (ram_i: 0x8000_0000)
    // =========================================================================
    logic [XLEN-1:0] HRDATA_RAM_I;
    logic            HREADYOUT_RAM_I, HRESP_RAM_I;

    ram_ahb #(
        .XLEN(XLEN),
        .PA_BITS(32),
        .RANGE(IRAM_SIZE_BYTES - 1),
        .BASE_ADDR(IRAM_BASE),
        .PRELOAD(0),
        .MEMFILE("test_instr.mem"),
        .RAM_LATENCY(0)
    ) ram_i (
        .HCLK(HCLK),
        .HRESETn(HRESETn),
        .HSELRam(HSELRam_I),
        .HADDR(HADDR),
        .HWRITE(HWRITE),
        .HREADY(HREADY),
        .HTRANS(HTRANS),
        .HWDATA(HWDATA),
        .HWSTRB(HWSTRB),
        .HREADRam(HRDATA_RAM_I),
        .HRESPRam(HRESP_RAM_I),
        .HREADYRam(HREADYOUT_RAM_I)
    );

    // =========================================================================
    // 4. AHB On-Chip Data RAM (ram_d: 0x8000_2000)
    // =========================================================================
    logic [XLEN-1:0] HRDATA_RAM_D;
    logic            HREADYOUT_RAM_D, HRESP_RAM_D;

    ram_ahb #(
        .XLEN(XLEN),
        .PA_BITS(32),
        .RANGE(DRAM_SIZE_BYTES - 1),
        .BASE_ADDR(DRAM_BASE),
        .PRELOAD(0),
        .MEMFILE("test_data.mem"),
        .RAM_LATENCY(0)
    ) ram_d (
        .HCLK(HCLK),
        .HRESETn(HRESETn),
        .HSELRam(HSELRam_D),
        .HADDR(HADDR),
        .HWRITE(HWRITE),
        .HREADY(HREADY),
        .HTRANS(HTRANS),
        .HWDATA(HWDATA),
        .HWSTRB(HWSTRB),
        .HREADRam(HRDATA_RAM_D),
        .HRESPRam(HRESP_RAM_D),
        .HREADYRam(HREADYOUT_RAM_D)
    );

    // =========================================================================
    // 5. Optional AHB Boot ROM (0x0000_1000 - 0x0000_1FFF)
    // =========================================================================
    logic [XLEN-1:0] HRDATA_BOOTROM;
    logic            HREADYOUT_BOOTROM, HRESP_BOOTROM;

    generate
        if (BOOTROM_SUPPORTED) begin : gen_bootrom
            rom_ahb #(
                .XLEN(XLEN),
                .PA_BITS(32),
                .RANGE(4095),
                .PRELOAD(0),
                .MEMFILE("")
            ) bootrom (
                .HCLK(HCLK),
                .HRESETn(HRESETn),
                .HSELRom(HSELBootRom),
                .HADDR(HADDR),
                .HREADY(HREADY),
                .HTRANS(HTRANS),
                .HREADRom(HRDATA_BOOTROM),
                .HRESPRom(HRESP_BOOTROM),
                .HREADYRom(HREADYOUT_BOOTROM)
            );
        end else begin : gen_no_bootrom
            assign HRDATA_BOOTROM    = '0;
            assign HRESP_BOOTROM     = 1'b0;
            assign HREADYOUT_BOOTROM = 1'b1;
        end
    endgenerate

    // =========================================================================
    // 6. AHB to APB Bridge
    // =========================================================================
    logic [XLEN-1:0] HRDATA_BRIDGE;
    logic            HREADYOUT_BRIDGE, HRESP_BRIDGE;

    logic            PCLK, PRESETn;
    logic [APB_PERIPHS-1:0] PSEL;
    logic            PWRITE, PENABLE;
    logic [31:0]     PADDR;
    logic [XLEN-1:0] PWDATA;
    logic [XLEN/8-1:0] PSTRB;
    logic [APB_PERIPHS-1:0] PREADY_PERIPHS;
    logic [APB_PERIPHS*XLEN-1:0] PRDATA_PERIPHS;

    ahbapbbridge #(
        .XLEN(XLEN),
        .PERIPHS(APB_PERIPHS)
    ) bridge (
        .HCLK(HCLK),
        .HRESETn(HRESETn),
        .HSEL(HSEL_APB),
        .HADDR(HADDR),
        .HWDATA(HWDATA),
        .HWSTRB(HWSTRB),
        .HWRITE(HWRITE),
        .HTRANS(HTRANS),
        .HREADY(HREADY),
        .HRDATA(HRDATA_BRIDGE),
        .HRESP(HRESP_BRIDGE),
        .HREADYOUT(HREADYOUT_BRIDGE),
        .PCLK(PCLK),
        .PRESETn(PRESETn),
        .PSEL(PSEL),
        .PWRITE(PWRITE),
        .PENABLE(PENABLE),
        .PADDR(PADDR),
        .PWDATA(PWDATA),
        .PSTRB(PSTRB),
        .PREADY(PREADY_PERIPHS),
        .PRDATA(PRDATA_PERIPHS)
    );

    // =========================================================================
    // 7. APB Peripherals (CLINT, PLIC, UART, SPI, GPIO)
    // =========================================================================
    logic [XLEN-1:0] PRDATA_CLINT, PRDATA_PLIC, PRDATA_UART, PRDATA_SPI, PRDATA_GPIO;
    logic            PREADY_CLINT, PREADY_PLIC, PREADY_UART, PREADY_SPI, PREADY_GPIO;
    logic            UARTIntr, GPIOIntr, SPIIntr;

    generate
    // Peripheral 0: CLINT (Base: 0x0200_0000, APB Slot 0)
    if (CLINT_SUPPORTED) begin : gen_clint
        clint_apb #(XLEN) clint (
            .PCLK(PCLK),
            .PRESETn(PRESETn),
            .PSEL(PSEL[0]),
            .PADDR(PADDR[15:0]),
            .PWDATA(PWDATA),
            .PSTRB(PSTRB),
            .PWRITE(PWRITE),
            .PENABLE(PENABLE),
            .PRDATA(PRDATA_CLINT),
            .PREADY(PREADY_CLINT),
            .MTIME(MTIME_CLINT),
            .MTimerInt(MTimerInt),
            .MSwInt(MSwInt)
        );
    end else begin : gen_no_clint
        assign PRDATA_CLINT = '0;
        assign PREADY_CLINT = 1'b1;
        assign MTIME_CLINT  = '0;
        assign MTimerInt    = 1'b0;
        assign MSwInt       = 1'b0;
    end

    // Peripheral 1: PLIC (Base: 0x0C00_0000, APB Slot 1)
    if (PLIC_SUPPORTED) begin : gen_plic
        plic_apb #(XLEN) plic (
            .PCLK(PCLK),
            .PRESETn(PRESETn),
            .PSEL(PSEL[1]),
            .PADDR(PADDR[27:0]),
            .PWDATA(PWDATA),
            .PSTRB(PSTRB),
            .PWRITE(PWRITE),
            .PENABLE(PENABLE),
            .PRDATA(PRDATA_PLIC),
            .PREADY(PREADY_PLIC),
            .UARTIntr(UARTIntr),
            .GPIOIntr(GPIOIntr),
            .SPIIntr(SPIIntr),
            .SDCIntr(1'b0),
            .MExtInt(MExtInt),
            .SExtInt(SExtInt)
        );
    end else begin : gen_no_plic
        assign PRDATA_PLIC = '0;
        assign PREADY_PLIC = 1'b1;
        assign MExtInt     = 1'b0;
        assign SExtInt     = 1'b0;
    end

    // Peripheral 2: 16550 UART (Base: 0x1000_0000, APB Slot 2)
    if (UART_SUPPORTED) begin : gen_uart
        uart_apb #(
            .XLEN(XLEN),
            .UART_PRESCALE(1),
            .USE_REAL_UART(0)
        ) uart (
            .PCLK(PCLK),
            .PRESETn(PRESETn),
            .PSEL(PSEL[2]),
            .PADDR(PADDR[2:0]),
            .PWDATA(PWDATA),
            .PSTRB(PSTRB),
            .PWRITE(PWRITE),
            .PENABLE(PENABLE),
            .PRDATA(PRDATA_UART),
            .PREADY(PREADY_UART),
            .SIN(UARTSin),
            .SOUT(UARTSout),
            .INTR(UARTIntr),
            .DSRb(1'b1),
            .DCDb(1'b1),
            .CTSb(1'b0),
            .RIb(1'b1),
            .RTSb(),
            .DTRb(),
            .OUT1b(),
            .OUT2b(),
            .TXRDYb(),
            .RXRDYb()
        );
    end else begin : gen_no_uart
        assign PRDATA_UART = '0;
        assign PREADY_UART = 1'b1;
        assign UARTSout    = 1'b1;
        assign UARTIntr    = 1'b0;
    end

    // Peripheral 3: SPI Controller (Base: 0x1004_0000, APB Slot 3)
    if (SPI_SUPPORTED) begin : gen_spi
        spi_apb #(
            .XLEN(XLEN),
            .SPI_LOOPBACK_TEST(0)
        ) spi (
            .PCLK(PCLK),
            .PRESETn(PRESETn),
            .PSEL(PSEL[3]),
            .PADDR(PADDR[7:0]),
            .PWDATA(PWDATA),
            .PSTRB(PSTRB),
            .PWRITE(PWRITE),
            .PENABLE(PENABLE),
            .PREADY(PREADY_SPI),
            .PRDATA(PRDATA_SPI),
            .SPIOut(SPIOut),
            .SPIIn(SPIIn),
            .SPICS(SPICS),
            .SPIIntr(SPIIntr),
            .SPICLK(SPICLK)
        );
    end else begin : gen_no_spi
        assign PRDATA_SPI = '0;
        assign PREADY_SPI = 1'b1;
        assign SPIOut     = 1'b0;
        assign SPICS      = 4'hF;
        assign SPIIntr    = 1'b0;
        assign SPICLK     = 1'b0;
    end

    // Peripheral 4: GPIO (Base: 0x1006_0000, APB Slot 4)
    if (GPIO_SUPPORTED) begin : gen_gpio
        gpio_apb #(XLEN) gpio (
            .PCLK(PCLK),
            .PRESETn(PRESETn),
            .PSEL(PSEL[4]),
            .PADDR(PADDR[7:0]),
            .PWDATA(PWDATA),
            .PSTRB(PSTRB),
            .PWRITE(PWRITE),
            .PENABLE(PENABLE),
            .PRDATA(PRDATA_GPIO),
            .PREADY(PREADY_GPIO),
            .GPIOIN(GPIOIN),
            .GPIOOUT(GPIOOUT),
            .GPIOEN(GPIOEN),
            .GPIOIntr(GPIOIntr)
        );
    end else begin : gen_no_gpio
        assign PRDATA_GPIO = '0;
        assign PREADY_GPIO = 1'b1;
        assign GPIOOUT     = 32'd0;
        assign GPIOEN      = 32'd0;
        assign GPIOIntr    = 1'b0;
    end
    endgenerate

    // Pack APB Peripheral responses into bus arrays
    assign PREADY_PERIPHS = {PREADY_GPIO, PREADY_SPI, PREADY_UART, PREADY_PLIC, PREADY_CLINT};
    assign PRDATA_PERIPHS = {PRDATA_GPIO, PRDATA_SPI, PRDATA_UART, PRDATA_PLIC, PRDATA_CLINT};

    // =========================================================================
    // 8. AHB Read Multiplexer & Response Logic
    // =========================================================================
    assign HRDATA = HSELRam_ID    ? HRDATA_RAM_I      :
                    HSELRam_DD    ? HRDATA_RAM_D      :
                    HSELEXTD      ? HRDATAEXT         :
                    HSELBootRomD  ? HRDATA_BOOTROM    :
                    HSELBRIDGED   ? HRDATA_BRIDGE     : '0;

    assign HREADYOUT = HSELRam_ID    ? HREADYOUT_RAM_I   :
                       HSELRam_DD    ? HREADYOUT_RAM_D   :
                       HSELEXTD      ? HREADYEXT         :
                       HSELBootRomD  ? HREADYOUT_BOOTROM :
                       HSELBRIDGED   ? HREADYOUT_BRIDGE  :
                       HSELNoneD     ? 1'b1 : 1'b1;

    assign HRESP = HSELRam_ID    ? HRESP_RAM_I    :
                   HSELRam_DD    ? HRESP_RAM_D    :
                   HSELEXTD      ? HRESPEXT       :
                   HSELBootRomD  ? HRESP_BOOTROM  :
                   HSELBRIDGED   ? HRESP_BRIDGE   : 1'b0;

endmodule
