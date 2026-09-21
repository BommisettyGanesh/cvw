#!/usr/bin/env python3
"""
SoCDebug CLI Utility for CORE-V Wally RISC-V SoC
Supports Core Halt, Memory/Accelerator Read/Write, and Core Resume
"""

import sys
import time
import argparse
import serial

class DebuggerClient:
    def __init__(self, port='/dev/ttyUSB0', baudrate=115200, timeout=1.0):
        self.ser = serial.Serial(port, baudrate=baudrate, timeout=timeout)
        time.sleep(0.1)
        self.ser.reset_input_buffer()
        # Wake up / ensure ADP mode
        self.ser.write(b"\x1b\n")
        time.sleep(0.05)
        self.read_all()

    def read_all(self):
        buf = b""
        while self.ser.in_waiting:
            buf += self.ser.read(self.ser.in_waiting)
            time.sleep(0.02)
        return buf.decode(errors='replace')

    def send_cmd(self, cmd_str):
        self.ser.reset_input_buffer()
        self.ser.write((cmd_str + "\n").encode())
        time.sleep(0.05)
        resp = self.read_all()
        return resp.strip()

    def halt_core(self):
        """Halts the RISC-V Core by asserting ExternalStall (GPO8 bit 1)"""
        print("[*] Halting RISC-V Core...")
        resp = self.send_cmd("C 0202")
        print(f"    Response: {resp}")
        return resp

    def resume_core(self):
        """Resumes the RISC-V Core by deasserting ExternalStall (GPO8 bit 1)"""
        print("[*] Resuming RISC-V Core...")
        resp = self.send_cmd("C 0102")
        print(f"    Response: {resp}")
        return resp

    def reset_core(self):
        """Pulses core reset (GPO8 bit 0)"""
        print("[*] Resetting Core...")
        self.send_cmd("C 0201")
        time.sleep(0.01)
        resp = self.send_cmd("C 0101")
        print(f"    Response: {resp}")
        return resp

    def read32(self, addr):
        """Reads a 32-bit word from memory or peripheral address"""
        self.send_cmd(f"A {addr:08x}")
        resp = self.send_cmd("R")
        # Output format is typically "R 0x12345678" or similar
        print(f"[*] Read [0x{addr:08x}]: {resp}")
        return resp

    def write32(self, addr, value):
        """Writes a 32-bit word to memory or peripheral address"""
        self.send_cmd(f"A {addr:08x}")
        resp = self.send_cmd(f"W {value:08x}")
        print(f"[*] Write [0x{addr:08x}] <= 0x{value:08x}: {resp}")
        return resp

    def read_accelerator(self):
        """Reads accelerator status and operands"""
        print("\n=== Reading Accelerator Region (0x30000000) ===")
        self.read32(0x30000000)  # Operand A / CSR Control
        self.read32(0x30000004)  # Operand B / CSR Status
        self.read32(0x30000008)  # Product Result / Config
        self.read32(0x3000000C)  # Print register / Performance cycles

def main():
    parser = argparse.ArgumentParser(description="SoCDebug CLI for CORE-V Wally")
    parser.add_argument("-d", "--device", default="/dev/ttyUSB0", help="Serial port")
    parser.add_argument("-b", "--baud", type=int, default=115200, help="Baud rate")
    subparsers = parser.add_subparsers(dest="command", help="Command to run")

    subparsers.add_parser("halt", help="Halt the RISC-V core in middle of execution")
    subparsers.add_parser("resume", help="Resume the RISC-V core")
    subparsers.add_parser("reset", help="Reset the RISC-V core")

    p_read = subparsers.add_parser("read", help="Read 32-bit memory location")
    p_read.add_argument("address", type=lambda x: int(x, 0), help="Hex address (e.g. 0x30000008)")

    p_write = subparsers.add_parser("write", help="Write 32-bit memory location")
    p_write.add_argument("address", type=lambda x: int(x, 0), help="Hex address")
    p_write.add_argument("value", type=lambda x: int(x, 0), help="Hex value to write")

    subparsers.add_parser("read_accel", help="Read accelerator status & result registers")

    args = parser.parse_args()

    if not args.command:
        parser.print_help()
        sys.exit(1)

    try:
        client = DebuggerClient(port=args.device, baudrate=args.baud)
    except Exception as e:
        print(f"Error opening serial port {args.device}: {e}")
        print("Note: In simulation, test with tb/tb_debugger.sv")
        sys.exit(1)

    if args.command == "halt":
        client.halt_core()
    elif args.command == "resume":
        client.resume_core()
    elif args.command == "reset":
        client.reset_core()
    elif args.command == "read":
        client.read32(args.address)
    elif args.command == "write":
        client.write32(args.address, args.value)
    elif args.command == "read_accel":
        client.read_accelerator()

if __name__ == "__main__":
    main()
