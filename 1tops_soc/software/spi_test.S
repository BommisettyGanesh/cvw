# spi_test.S - SPI Hardware FIFO Saturation & Backpressure Test
.section .text
.globl _start

_start:
    lui   s0, 0x10040         # SPI Base (0x1004_0000)
    lui   s1, 0x80002         # Data RAM (0x8000_2000)

    # 1. Set slow SCK divider (SckDiv = 0xFFF, ~1.3ms per byte)
    li    t0, 0xfff
    sw    t0, 0x00(s0)

    # 2. Burst write 8 bytes into SPI_TXDATA (0x1004_0048)
    #    Takes ~320 nanoseconds (far faster than 1.3ms drain time)
    li    t1, 0x11
    sw    t1, 0x48(s0)
    li    t1, 0x22
    sw    t1, 0x48(s0)
    li    t1, 0x33
    sw    t1, 0x48(s0)
    li    t1, 0x44
    sw    t1, 0x48(s0)
    li    t1, 0x55
    sw    t1, 0x48(s0)
    li    t1, 0x66
    sw    t1, 0x48(s0)
    li    t1, 0x77
    sw    t1, 0x48(s0)
    li    t1, 0x88
    sw    t1, 0x48(s0)

    # 3. Sample SPI_TXDATA while FIFO is saturated:
    #    Bit 31 is TransmitFIFOFull (Expected: 0x80000000)
    lw    t2, 0x48(s0)
    sw    t2, 0x00(s1)        # 0x80002000 = Sampled SPI_TXDATA (0x80000000)

    # 4. Wait ~20 ms for FIFO to drain and loop back into RX FIFO
    li    t3, 1000000
drain_wait:
    addi  t3, t3, -1
    bnez  t3, drain_wait

    # 5. Read back first received byte from SPI_RXDATA (0x1004_004C)
    lw    t4, 0x4c(s0)
    sw    t4, 0x04(s1)        # 0x80002004 = First RX byte (0x00000011)

done:
    wfi
    j     done
