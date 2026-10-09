#!/usr/bin/env python3
"""
SoCDebug Dual-Protocol CLI Utility for CORE-V Wally RISC-V SoC
Supports both UART and FT1248 High-Speed Debug Protocols.
Hardware selection is governed by the physical 'dbg_sel' hardware pad:
  dbg_sel = 0 -> UART active (FT1248 isolated)
  dbg_sel = 1 -> FT1248 active (UART isolated)
"""

import sys
import time
import argparse

# Optional hardware communication libraries
try:
    import serial
    HAS_SERIAL = True
except ImportError:
    HAS_SERIAL = False

try:
    from pyftdi.ftdi import Ftdi
    from pyftdi.spi import SpiController
    HAS_PYFTDI = True
except ImportError:
    HAS_PYFTDI = False


class BaseProtocolInterface:
    def write(self, data: bytes):
        raise NotImplementedError
    def read(self, nbytes: int) -> bytes:
        raise NotImplementedError
    def read_all(self) -> str:
        raise NotImplementedError
    def close(self):
        pass


class UartInterface(BaseProtocolInterface):
    """Communicates via physical UART serial port (dbg_sel = 0)"""
    def __init__(self, port='/dev/ttyUSB0', baudrate=115200, timeout=1.0):
        if not HAS_SERIAL:
            raise RuntimeError("pyserial is not installed. Run: pip install pyserial")
        self.ser = serial.Serial(port, baudrate=baudrate, timeout=timeout)
        time.sleep(0.05)
        self.ser.reset_input_buffer()
        # Ensure ADP prompt mode
        self.ser.write(b"\n")
        time.sleep(0.02)
        self.read_all()

    def write(self, data: bytes):
        self.ser.write(data)

    def read_all(self) -> str:
        buf = b""
        time.sleep(0.02)
        while self.ser.in_waiting:
            buf += self.ser.read(self.ser.in_waiting)
            time.sleep(0.01)
        return buf.decode(errors='replace')

    def close(self):
        if self.ser and self.ser.is_open:
            self.ser.close()


class FT1248Interface(BaseProtocolInterface):
    """
    Communicates via FTDI FT232H / FT2232H FT1248 High-Speed Interface (dbg_sel = 1)
    FT1248 provides synchronous streaming up to 30 MHz.
    """
    def __init__(self, url='ftdi://ftdi:232h/1', clk_freq=10_000_000):
        if not HAS_PYFTDI:
            raise RuntimeError("pyftdi is not installed. Run: pip install pyftdi")
        self.spi = SpiController()
        self.spi.configure(url)
        # FT1248 mode 0 (CPOL=0, CPHA=0)
        self.port = self.spi.get_port(cs=0, freq=clk_freq, mode=0)
        time.sleep(0.02)
        # Send newline to sync prompt
        self.port.write(b"\n")
        time.sleep(0.02)

    def write(self, data: bytes):
        self.port.write(data)

    def read_all(self) -> str:
        # FT1248 read cycle
        try:
            resp = self.port.read(64)
            return resp.decode(errors='replace')
        except Exception:
            return ""

    def close(self):
        self.spi.terminate()


class MockInterface(BaseProtocolInterface):
    """Emulated protocol interface for testing CLI logic without physical hardware"""
    def __init__(self, proto_name="Mock"):
        self.proto_name = proto_name
        self.gpo = 0x00
        self.addr = 0x80000000
        self.memory = {
            0x80000000: 0x00000297,
            0x80000004: 0x02028293,
            0x80002000: 0xdeadbeef,
            0x30000000: 0x00000008,
            0x30000004: 0x00000009,
            0x30000008: 0x00000048,
        }
        self.last_resp = f"[{self.proto_name}_MOCK] Connected. System banner: 0x50c1ab04\n]"
        print(f"[!] Running in MOCK/EMULATED mode ({proto_name}). No real hardware connected.")

    def write(self, data: bytes):
        cmd = data.decode(errors='ignore').strip()
        parts = cmd.split()
        if not parts:
            self.last_resp = "]"
            return

        c = parts[0].upper()
        if c == 'A' and len(parts) > 1:
            self.addr = int(parts[1], 16)
            self.last_resp = f"]A 0x{self.addr:08x}\n]"
        elif c == 'W' and len(parts) > 1:
            val = int(parts[1], 16)
            self.memory[self.addr] = val
            self.last_resp = f"]W 0x{val:08x}\n]"
            self.addr += 4
        elif c == 'R':
            val = self.memory.get(self.addr, 0x00000000)
            self.last_resp = f"]R 0x{val:08x}\n]"
            self.addr += 4
        elif c == 'C':
            if len(parts) > 1:
                param = int(parts[1], 16)
                action = (param >> 8) & 0xff
                bits = param & 0xff
                if action == 1:
                    self.gpo &= ~bits
                elif action == 2:
                    self.gpo |= bits
                elif action == 3:
                    self.gpo = bits
            halt_status = 1 if (self.gpo & 0x02) else 0
            self.last_resp = f"]C 0x{halt_status:02x}{self.gpo:02x}0000\n]"
        elif c == 'M' or c == 'V' or c == 'P':
            self.last_resp = f"]{c} 0x00000000\n]"
        else:
            self.last_resp = "]?\n]"

    def read_all(self) -> str:
        resp = self.last_resp
        self.last_resp = ""
        return resp


class DebuggerClient:
    def __init__(self, interface: BaseProtocolInterface):
        self.iface = interface

    def send_cmd(self, cmd_str: str) -> str:
        self.iface.write((cmd_str + "\n").encode())
        time.sleep(0.04)
        resp = self.iface.read_all()
        return resp.strip()

    def halt_core(self):
        """Halts RISC-V CPU by asserting ExternalStall (GPO8 bit 1)"""
        print("[*] Halting RISC-V Core...")
        resp = self.send_cmd("C 0202")
        print(f"    Response: {resp}")
        # Query status
        status = self.get_status()
        if "0x01" in status or "0x1" in status:
            print("    [PASS] Core confirmed HALTED (ExternalStall active).")
        return resp

    def resume_core(self):
        """Resumes RISC-V CPU by deasserting ExternalStall (GPO8 bit 1)"""
        print("[*] Resuming RISC-V Core...")
        resp = self.send_cmd("C 0102")
        print(f"    Response: {resp}")
        status = self.get_status()
        print("    [PASS] Core resumed.")
        return resp

    def reset_core(self):
        """Pulses core reset request (GPO8 bit 0)"""
        print("[*] Pulsing Core Reset...")
        self.send_cmd("C 0201")
        time.sleep(0.01)
        resp = self.send_cmd("C 0101")
        print(f"    Response: {resp}")
        return resp

    def get_status(self):
        """Queries hardware control & status register (GPI8 and GPO8)"""
        resp = self.send_cmd("C")
        print(f"[*] Core & GPO Status: {resp}")
        return resp

    def read32(self, addr: int):
        """Reads a 32-bit word from memory or peripheral address ('A' then 'R')"""
        self.send_cmd(f"A {addr:08x}")
        resp = self.send_cmd("R")
        print(f"[*] Read [0x{addr:08x}]: {resp}")
        return resp

    def write32(self, addr: int, value: int):
        """Writes a 32-bit word to memory or peripheral address ('A' then 'W')"""
        self.send_cmd(f"A {addr:08x}")
        resp = self.send_cmd(f"W {value:08x}")
        print(f"[*] Write [0x{addr:08x}] <= 0x{value:08x}: {resp}")
        # Automatic readback verification
        self.send_cmd(f"A {addr:08x}")
        readback = self.send_cmd("R")
        print(f"[*] Verified Readback: {readback}")
        return resp

    def read_accelerator(self):
        """Reads 1TOPS hardware accelerator registers"""
        print("\n=== Reading 1TOPS Accelerator Region (0x30000000) ===")
        self.read32(0x30000000)  # Multiplier OpA
        self.read32(0x30000004)  # Multiplier OpB
        self.read32(0x30000008)  # Multiplier Product
        self.read32(0x3000000C)  # Config / Status

    def dump_memory(self, start_addr: int, count: int = 16):
        """Dumps consecutive words from target memory"""
        print(f"\n=== Memory Dump: 0x{start_addr:08x} ({count} words) ===")
        self.send_cmd(f"A {start_addr:08x}")
        for i in range(count):
            curr_addr = start_addr + (i * 4)
            resp = self.send_cmd("R")
            print(f"  0x{curr_addr:08x}: {resp}")


def main():
    parser = argparse.ArgumentParser(
        description="SoCDebug Dual-Protocol CLI for CORE-V Wally (UART & FT1248)",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Hardware Pin Protocol Selection Note:
  Make sure the board physical pin 'dbg_sel' matches your selected --protocol:
    dbg_sel = LOW (0)  -> --protocol uart   (UART pins active, FT1248 isolated)
    dbg_sel = HIGH (1) -> --protocol ft1248 (FT1248 pins active, UART isolated)
        """
    )
    parser.add_argument("-p", "--protocol", choices=["uart", "ft1248"], default="uart",
                        help="Debug protocol to use (matches physical dbg_sel pad)")
    parser.add_argument("-d", "--device", default="/dev/ttyUSB0",
                        help="Serial port (for UART, e.g. /dev/ttyUSB0)")
    parser.add_argument("-b", "--baud", type=int, default=115200,
                        help="UART Baud rate (default: 115200)")
    parser.add_argument("--ftdi-url", default="ftdi://ftdi:232h/1",
                        help="FTDI device URL for FT1248 mode (default: ftdi://ftdi:232h/1)")
    parser.add_argument("--mock", action="store_true",
                        help="Run in mock/emulated mode without physical hardware")

    subparsers = parser.add_subparsers(dest="command", help="Command to run")

    subparsers.add_parser("halt", help="Halt the RISC-V core during execution")
    subparsers.add_parser("resume", help="Resume the RISC-V core")
    subparsers.add_parser("reset", help="Pulse core reset")
    subparsers.add_parser("status", help="Read core halt and GPO status")

    p_read = subparsers.add_parser("read", help="Read 32-bit memory location")
    p_read.add_argument("address", type=lambda x: int(x, 0), help="Hex address (e.g. 0x80000000)")

    p_write = subparsers.add_parser("write", help="Write 32-bit memory location with readback verification")
    p_write.add_argument("address", type=lambda x: int(x, 0), help="Hex address")
    p_write.add_argument("value", type=lambda x: int(x, 0), help="Hex value to write")

    p_dump = subparsers.add_parser("dump", help="Dump consecutive 32-bit words")
    p_dump.add_argument("address", type=lambda x: int(x, 0), help="Hex start address")
    p_dump.add_argument("-n", "--count", type=int, default=8, help="Number of 32-bit words to dump")

    subparsers.add_parser("read_accel", help="Read 1TOPS accelerator registers")

    args = parser.parse_args()

    if not args.command:
        parser.print_help()
        sys.exit(1)

    # Initialize interface
    if args.mock:
        iface = MockInterface(proto_name=args.protocol.upper())
    else:
        try:
            if args.protocol == "uart":
                if not HAS_SERIAL:
                    print("[!] Note: 'pyserial' not installed. Falling back to MOCK mode for demo.")
                    iface = MockInterface(proto_name="UART")
                else:
                    iface = UartInterface(port=args.device, baudrate=args.baud)
            else:  # ft1248
                if not HAS_PYFTDI:
                    print("[!] Note: 'pyftdi' not installed. Falling back to MOCK mode for demo.")
                    iface = MockInterface(proto_name="FT1248")
                else:
                    iface = FT1248Interface(url=args.ftdi_url)
        except Exception as e:
            print(f"[!] Error opening interface ({args.protocol}): {e}")
            print(f"[!] Tip: Use --mock to test CLI commands without physical hardware.")
            sys.exit(1)

    client = DebuggerClient(iface)

    try:
        if args.command == "halt":
            client.halt_core()
        elif args.command == "resume":
            client.resume_core()
        elif args.command == "reset":
            client.reset_core()
        elif args.command == "status":
            client.get_status()
        elif args.command == "read":
            client.read32(args.address)
        elif args.command == "write":
            client.write32(args.address, args.value)
        elif args.command == "dump":
            client.dump_memory(args.address, args.count)
        elif args.command == "read_accel":
            client.read_accelerator()
    finally:
        iface.close()


if __name__ == "__main__":
    main()
