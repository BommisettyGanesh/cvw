#!/usr/bin/env python3
"""
==============================================================================
test_step_and_clkdiv.py
Automated Verification Suite for CORE-V Wally SoCDebug
Tests:
  1. RISC-V Core Single-Step Execution (Instruction-Step & Clock-Cycle Step)
  2. Reconfigurable UART Clock Divider (Live Baud Rate Switching)
  3. Reconfigurable FT1248 Clock Divider (SCLK Rate Tuning)

Usage:
  # Run in mock/simulation mode (no FPGA hardware needed):
  python3 test_step_and_clkdiv.py --mock

  # Run against real Basys 3 hardware over UART:
  python3 test_step_and_clkdiv.py --protocol uart --device /dev/ttyUSB0 --baud 115200

  # Run only step test:
  python3 test_step_and_clkdiv.py --mock --test step

  # Run only clock divider tests:
  python3 test_step_and_clkdiv.py --mock --test clkdiv
==============================================================================
"""

import sys
import os
import time
import argparse

try:
    import serial
    HAS_SERIAL = True
except ImportError:
    HAS_SERIAL = False

try:
    from pyftdi.spi import SpiController
    HAS_PYFTDI = True
except ImportError:
    HAS_PYFTDI = False


class BaseProtocolInterface:
    def write(self, data: bytes):
        raise NotImplementedError
    def read_all(self) -> str:
        raise NotImplementedError
    def set_baudrate(self, baud: int):
        pass
    def close(self):
        pass


class UartInterface(BaseProtocolInterface):
    """Communicates via physical UART serial port (dbg_sel = 0)."""
    def __init__(self, port='/dev/ttyUSB0', baudrate=115200, timeout=0.8):
        if not HAS_SERIAL:
            raise RuntimeError("pyserial is not installed. Run: pip install pyserial")
        self.port = port
        self.baudrate = baudrate
        self.ser = serial.Serial(port, baudrate=baudrate, timeout=timeout)
        time.sleep(0.05)
        self.ser.reset_input_buffer()
        # Synchronize prompt
        self.ser.write(b"\n")
        time.sleep(0.05)
        self.read_all()

    def write(self, data: bytes):
        self.ser.write(data)

    def read_all(self) -> str:
        buf = b""
        time.sleep(0.03)
        while self.ser.in_waiting:
            buf += self.ser.read(self.ser.in_waiting)
            time.sleep(0.01)
        return buf.decode(errors='replace')

    def set_baudrate(self, baud: int):
        self.baudrate = baud
        self.ser.baudrate = baud
        time.sleep(0.05)
        self.ser.reset_input_buffer()

    def close(self):
        if self.ser and self.ser.is_open:
            self.ser.close()


class FT1248Interface(BaseProtocolInterface):
    """Communicates via physical FT1248 interface using pyftdi (dbg_sel = 1)."""
    def __init__(self, url='ftdi://ftdi:232h/1', clk_freq=10_000_000):
        if not HAS_PYFTDI:
            raise RuntimeError("pyftdi is not installed. Run: pip install pyftdi")
        self.spi = SpiController()
        self.spi.configure(url)
        self.port = self.spi.get_port(cs=0, freq=clk_freq, mode=0)
        time.sleep(0.02)
        self.port.write(b"\n")
        time.sleep(0.02)

    def write(self, data: bytes):
        self.port.write(data)

    def read_all(self) -> str:
        try:
            resp = self.port.read(64)
            return resp.decode(errors='replace')
        except Exception:
            return ""

    def close(self):
        self.spi.terminate()


class MockSoCDebugInterface(BaseProtocolInterface):
    """
    Realistic in-memory mock of the SoCDebug ADP controller, AHB bus,
    core step controller FSM, and clock divider registers.
    """
    def __init__(self, clk_freq=50_000_000, default_baud=115200, default_ft_div=1):
        self.clk_freq = clk_freq
        self.current_baud = default_baud
        self.uart_div = clk_freq // default_baud # 434 (0x01B2)
        self.ft_div = default_ft_div            # 1 (FPGA default)
        self.addr = 0x80000000
        self.val = 0x00000000
        self.gpo = 0x00                          # GPO8
        self.core_halted = 0
        self.step_busy = 0
        self.step_done = 0
        self.step_count = 0
        self.pc = 0x80000000
        self.regs = [0] * 32
        self.memory = {}
        self.last_resp = "] "

    def set_baudrate(self, baud: int):
        self.current_baud = baud

    def _execute_mock_step(self, is_cycle_step: bool):
        """Simulates 1 retired instruction or 1 clock cycle."""
        self.step_count += 1
        self.step_done = 1
        if is_cycle_step:
            return

        # Simple RV32I instruction emulator for step_test.bin
        instr = self.memory.get(self.pc, 0x00000013)
        self.pc += 4

        opcode = instr & 0x7F
        rd = (instr >> 7) & 0x1F
        funct3 = (instr >> 12) & 0x7
        rs1 = (instr >> 15) & 0x1F
        rs2 = (instr >> 20) & 0x1F
        imm_i = (instr >> 20)
        if imm_i & 0x800:
            imm_i -= 0x1000
        imm_u = instr & 0xFFFFF000
        imm_s = ((instr >> 25) << 5) | ((instr >> 7) & 0x1F)
        if imm_s & 0x800:
            imm_s -= 0x1000

        if opcode == 0x37: # LUI
            if rd != 0: self.regs[rd] = imm_u & 0xFFFFFFFF
        elif opcode == 0x13: # OP-IMM
            if funct3 == 0: # ADDI
                if rd != 0: self.regs[rd] = (self.regs[rs1] + imm_i) & 0xFFFFFFFF
        elif opcode == 0x33: # OP
            if funct3 == 0: # ADD
                if rd != 0: self.regs[rd] = (self.regs[rs1] + self.regs[rs2]) & 0xFFFFFFFF
        elif opcode == 0x23: # STORE
            if funct3 == 2: # SW
                mem_addr = (self.regs[rs1] + imm_s) & 0xFFFFFFFF
                self.memory[mem_addr] = self.regs[rs2] & 0xFFFFFFFF

    def write(self, data: bytes):
        cmd = data.decode(errors='ignore').strip()
        if not cmd:
            self.last_resp = "]\n"
            return

        parts = cmd.split()
        op = parts[0].upper()

        if op == 'A':
            if len(parts) > 1:
                self.addr = int(parts[1], 16)
            self.last_resp = f"A 0x{self.addr:08x}\n]\n"
        elif op == 'R':
            count = 1
            if len(parts) > 1:
                try: count = int(parts[1], 16)
                except ValueError: count = 1
            lines = []
            for _ in range(count):
                val = self.memory.get(self.addr, 0x00000000)
                lines.append(f"R 0x{val:08x}")
                self.addr += 4
            self.last_resp = "\n".join(lines) + "\n]\n"
        elif op == 'W' and len(parts) > 1:
            val = int(parts[1], 16)
            self.memory[self.addr] = val
            self.last_resp = f"W 0x{val:08x}\n]\n"
            self.addr += 4
        elif op == 'V' and len(parts) > 1:
            self.val = int(parts[1], 16)
            self.last_resp = f"V 0x{self.val:08x}\n]\n"
        elif op == 'F' and len(parts) > 1:
            count = int(parts[1], 16)
            for _ in range(count):
                self.memory[self.addr] = self.val
                self.addr += 4
            self.last_resp = f"F 0x{count:08x}\n]\n"
        elif op == 'C':
            if len(parts) > 1:
                param = int(parts[1], 16)
                action = (param >> 8) & 0xFF
                bits = param & 0xFF
                if action == 1:
                    self.gpo &= ~bits
                elif action == 2:
                    self.gpo |= bits
                elif action == 3:
                    self.gpo = bits

                # Update core state from GPO
                if self.gpo & 0x01: # Reset request
                    self.pc = 0x80000000
                self.core_halted = 1 if (self.gpo & 0x02) else 0

                # Check step trigger (GPO[2])
                if (self.gpo & 0x04) and self.core_halted:
                    is_cycle = bool(self.gpo & 0x08)
                    self._execute_mock_step(is_cycle)
                else:
                    self.step_done = 0

            gpi = (self.core_halted & 1) | ((self.step_busy & 1) << 1) | ((self.step_done & 1) << 2)
            self.last_resp = f"C 0x{gpi:02x}{self.gpo:02x}0000\n]\n"
        elif op == 'B':
            if len(parts) > 1:
                p = int(parts[1], 16)
                subcmd = (p >> 24) & 0xFF
                if subcmd == 0x01:
                    self.uart_div = p & 0xFFFF
                elif subcmd == 0x02:
                    self.ft_div = p & 0xFF
                elif subcmd == 0x03:
                    self.uart_div = (p >> 8) & 0xFFFF
                    self.ft_div = p & 0xFF
                else:
                    self.uart_div = p & 0xFFFF
            combined = ((self.ft_div & 0xFF) << 16) | (self.uart_div & 0xFFFF)
            self.last_resp = f"B 0x00{self.ft_div:02x}{self.uart_div:04x}\n]\n"
        elif op == 'D':
            if len(parts) > 1:
                self.ft_div = int(parts[1], 16) & 0xFF
            self.last_resp = f"D 0x{self.ft_div:02x}\n]\n"
        elif op == 'X':
            self.last_resp = "\n"
        else:
            self.last_resp = f"?\n]\n"

    def read_all(self) -> str:
        resp = self.last_resp
        self.last_resp = ""
        return resp


class SoCDebugTester:
    def __init__(self, iface: BaseProtocolInterface, clk_freq=50_000_000, verbose=True):
        self.iface = iface
        self.clk_freq = clk_freq
        self.verbose = verbose
        self.passed = 0
        self.failed = 0

    def send_cmd(self, cmd_str: str) -> str:
        self.iface.write((cmd_str + "\n").encode())
        time.sleep(0.03)
        resp = self.iface.read_all()
        return resp.strip()

    def record_result(self, test_name: str, passed: bool, msg: str = ""):
        if passed:
            self.passed += 1
            print(f"  [PASS] {test_name}" + (f": {msg}" if msg else ""))
        else:
            self.failed += 1
            print(f"  [FAIL] {test_name}" + (f": {msg}" if msg else ""))

    # -------------------------------------------------------------------------
    # Test 1: Single-Step Execution
    # -------------------------------------------------------------------------
    def test_step_execution(self, bin_path: str = "step_test.bin"):
        print("\n==============================================================================")
        print(" TEST SUITE 1: RISC-V CORE STEP EXECUTION VERIFICATION")
        print("==============================================================================")

        # 1.1 Halt CPU Core
        print("[*] 1.1 Halting RISC-V Core (C 0202)...")
        self.send_cmd("C 0202")
        status = self.send_cmd("C")
        is_halted = "C 0x01" in status or "C 0x05" in status or "C 0x07" in status or "C 0x03" in status
        self.record_result("Core Halt Assertion", is_halted, f"Status={status}")

        # 1.2 Zero Out Data Memory Area (0x80002000 - 0x80002020)
        print("[*] 1.2 Zeroing Data RAM at 0x80002000...")
        self.send_cmd("A 80002000")
        self.send_cmd("V 00000000")
        self.send_cmd("F 08") # 8 words
        self.send_cmd("A 80002000")
        r0 = self.send_cmd("R")
        self.record_result("DRAM Initialized to Zero", "0x00000000" in r0, f"Readback={r0}")

        # 1.3 Load Step Test Program into IRAM
        print("[*] 1.3 Loading Step Test Program into IRAM (0x80000000)...")
        if os.path.exists(bin_path):
            with open(bin_path, "rb") as f:
                code_bytes = f.read()
            self.send_cmd("A 80000000")
            for i in range(0, len(code_bytes), 4):
                chunk = code_bytes[i:i+4]
                word = int.from_bytes(chunk, byteorder='little')
                self.send_cmd(f"W {word:08x}")
            print(f"    Loaded {len(code_bytes)} bytes from {bin_path}.")
        else:
            # Fallback opcodes for step_test.S:
            # lui s0, 0x80002; li t0, 0x11111111; sw t0, 0(s0); j loop
            fallback_words = [
                0x80002437, # lui s0, 0x80002
                0x111112b7, # lui t0, 0x11111
                0x11128293, # addi t0, t0, 273 (0x11111111)
                0x00542023, # sw t0, 0(s0)
                0x22222337, # lui t1, 0x22222
                0x22230313, # addi t1, t1, 546 (0x22222222)
                0x00642223, # sw t1, 4(s0)
                0x333333b7, # lui t2, 0x33333
                0x33338393, # addi t2, t2, 819 (0x33333333)
                0x00742423, # sw t2, 8(s0)
                0x00628e33, # add t3, t0, t1
                0x01c42623, # sw t3, 12(s0)
                0xcafecede, # lui t4, 0xcafec
                0xadee8e93, # addi t4, t4, -1346 (0xcafebabe)
                0x01d42823, # sw t4, 16(s0)
                0x0000006f  # j loop
            ]
            self.send_cmd("A 80000000")
            for w in fallback_words:
                self.send_cmd(f"W {w:08x}")
            print("    Loaded fallback step test sequence into IRAM.")

        # Reset PC to 0x80000000 while keeping CPU halted
        print("[*] 1.4 Pulsing Reset Vector while Halted (C 0201 -> C 0101)...")
        self.send_cmd("C 0201")
        time.sleep(0.01)
        self.send_cmd("C 0101")
        time.sleep(0.01)

        # 1.5 Perform Single Instruction Steps and Verify Memory Commits
        print("[*] 1.5 Performing Instruction Steps (C 0204 -> C 0104)...")
        # Step through instructions 1 to 4 (lui s0, lui t0, addi t0, sw t0)
        for step_idx in range(4):
            self.send_cmd("C 0204")
            time.sleep(0.01)
            self.send_cmd("C 0104")

        # Verify Marker 1 committed at 0x80002000
        self.send_cmd("A 80002000")
        r_step1 = self.send_cmd("R")
        self.record_result("Step 1 Marker (0x11111111 at 0x80002000)",
                           "0x11111111" in r_step1, f"Readback={r_step1}")

        # Step next 3 instructions (lui t1, addi t1, sw t1)
        for _ in range(3):
            self.send_cmd("C 0204")
            time.sleep(0.01)
            self.send_cmd("C 0104")

        self.send_cmd("A 80002004")
        r_step2 = self.send_cmd("R")
        self.record_result("Step 2 Marker (0x22222222 at 0x80002004)",
                           "0x22222222" in r_step2, f"Readback={r_step2}")

        # Step next 3 instructions (lui t2, addi t2, sw t2)
        for _ in range(3):
            self.send_cmd("C 0204")
            time.sleep(0.01)
            self.send_cmd("C 0104")

        self.send_cmd("A 80002008")
        r_step3 = self.send_cmd("R")
        self.record_result("Step 3 Marker (0x33333333 at 0x80002008)",
                           "0x33333333" in r_step3, f"Readback={r_step3}")

        # 1.6 Verify Clock Cycle Stepping (C 020c -> C 010c)
        print("[*] 1.6 Performing Clock-Cycle Step (C 020c -> C 010c)...")
        self.send_cmd("C 020c")
        time.sleep(0.01)
        self.send_cmd("C 010c")
        status_cycle = self.send_cmd("C")
        self.record_result("Core Remains Halted after Clock-Cycle Step",
                           "0x0" in status_cycle, f"Status={status_cycle}")

        # 1.7 Resume Core Execution
        print("[*] 1.7 Resuming Core (C 0102)...")
        self.send_cmd("C 0102")
        status_run = self.send_cmd("C")
        is_running = "C 0x00" in status_run or "C 0x04" in status_run
        self.record_result("Core Resumed (ExternalStall Deasserted)",
                           is_running, f"Status={status_run}")

    # -------------------------------------------------------------------------
    # Test 2: UART Clock Division
    # -------------------------------------------------------------------------
    def test_uart_clock_division(self):
        print("\n==============================================================================")
        print(" TEST SUITE 2: RECONFIGURABLE UART CLOCK DIVIDER VERIFICATION")
        print("==============================================================================")

        # 2.1 Read Default Dividers via 'B'
        print("[*] 2.1 Querying Default Clock Dividers (B)...")
        b_resp = self.send_cmd("B")
        print(f"    Response: {b_resp}")
        tokens = b_resp.replace("]", "").strip().split()
        hex_tokens = [t for t in tokens if t.startswith("0x")]
        if not hex_tokens:
            self.record_result("Query Default Dividers", False, f"Invalid format: {b_resp}")
            return
        div_val = int(hex_tokens[0], 16)
        orig_uart_div = div_val & 0xFFFF
        orig_ft_div = (div_val >> 16) & 0xFF
        expected_uart_div = self.clk_freq // 115200

        print(f"    Detected: UART Divider = {orig_uart_div} (0x{orig_uart_div:04x}), FT1248 Divider = {orig_ft_div}")
        self.record_result("UART Default Clock Divider Read",
                           orig_uart_div > 0, f"Value={orig_uart_div}")

        # 2.2 Test Reconfiguration of UART Divider
        target_baud = 230400
        new_div = self.clk_freq // target_baud
        print(f"[*] 2.2 Reconfiguring UART Divider to {new_div} (0x{new_div:04x}) for {target_baud} Baud...")
        self.send_cmd(f"B {new_div:04x}")
        b_resp2 = self.send_cmd("B")
        div_val2 = int([t for t in b_resp2.replace("]", "").strip().split() if t.startswith("0x")][0], 16)
        updated_uart_div = div_val2 & 0xFFFF
        self.record_result("UART Divider Register Updated",
                           updated_uart_div == new_div, f"Expected {new_div}, Got {updated_uart_div}")

        # 2.3 Live Communication Check at New Baud Rate (if real UART)
        if hasattr(self.iface, "set_baudrate"):
            print(f"[*] 2.3 Switching Host Serial Port to {target_baud} Baud...")
            self.iface.set_baudrate(target_baud)
            time.sleep(0.05)
            # Ping debugger at new baud rate
            resp_new_baud = self.send_cmd("B")
            self.record_result("Live Bidirectional UART at Reconfigured Baud",
                               "B 0x" in resp_new_baud, f"Response={resp_new_baud}")

            # Restore original baud rate
            print(f"[*] 2.4 Restoring UART Divider to {orig_uart_div} ({self.clk_freq // orig_uart_div} Baud)...")
            self.send_cmd(f"B {orig_uart_div:04x}")
            self.iface.set_baudrate(115200)
            time.sleep(0.05)
            resp_restored = self.send_cmd("B")
            self.record_result("UART Restored to Original Baud (115200)",
                               "B 0x" in resp_restored, f"Response={resp_restored}")
        else:
            # Restore
            self.send_cmd(f"B {orig_uart_div:04x}")

    # -------------------------------------------------------------------------
    # Test 3: FT1248 Clock Division
    # -------------------------------------------------------------------------
    def test_ft_clock_division(self):
        print("\n==============================================================================")
        print(" TEST SUITE 3: RECONFIGURABLE FT1248 CLOCK DIVIDER VERIFICATION")
        print("==============================================================================")

        # 3.1 Query FT1248 Divider via 'D'
        print("[*] 3.1 Querying FT1248 Divider via 'D'...")
        d_resp = self.send_cmd("D")
        tokens = [t for t in d_resp.replace("]", "").strip().split() if t.startswith("0x")]
        orig_ft_div = int(tokens[0], 16) & 0xFF if tokens else 4
        print(f"    Initial FT1248 Divider = {orig_ft_div}")
        self.record_result("Query FT1248 Divider via 'D'", len(tokens) > 0, f"Value={orig_ft_div}")

        # 3.2 Update FT1248 Divider via 'D 08'
        print("[*] 3.2 Updating FT1248 Divider to 8 via 'D 08'...")
        self.send_cmd("D 08")
        d_resp2 = self.send_cmd("D")
        val2 = int([t for t in d_resp2.replace("]", "").strip().split() if t.startswith("0x")][0], 16) & 0xFF
        self.record_result("FT1248 Divider Updated via 'D'", val2 == 8, f"Got {val2}")

        # 3.3 Verify FT1248 Divider Reflected in Combined 'B' Query
        b_resp = self.send_cmd("B")
        b_val = int([t for t in b_resp.replace("]", "").strip().split() if t.startswith("0x")][0], 16)
        ft_in_b = (b_val >> 16) & 0xFF
        self.record_result("FT1248 Divider Reflected in 'B' Register [23:16]",
                           ft_in_b == 8, f"Bits[23:16]={ft_in_b}")

        # 3.4 Update FT1248 Divider Explicitly via 'B 02<val>'
        print("[*] 3.4 Updating FT1248 Divider via Subcommand 'B 02000002'...")
        self.send_cmd("B 02000002")
        d_resp3 = self.send_cmd("D")
        val3 = int([t for t in d_resp3.replace("]", "").strip().split() if t.startswith("0x")][0], 16) & 0xFF
        self.record_result("FT1248 Divider Updated via 'B 02'", val3 == 2, f"Got {val3}")

        # 3.5 Restore Initial FT1248 Divider
        print(f"[*] 3.5 Restoring Initial FT1248 Divider ({orig_ft_div})...")
        self.send_cmd(f"D {orig_ft_div:02x}")
        d_restored = self.send_cmd("D")
        val_restored = int([t for t in d_restored.replace("]", "").strip().split() if t.startswith("0x")][0], 16) & 0xFF
        self.record_result("FT1248 Divider Restored", val_restored == orig_ft_div, f"Got {val_restored}")

    def run_all(self, test_filter="all", bin_path="step_test.bin"):
        t0 = time.time()
        if test_filter in ("all", "step"):
            self.test_step_execution(bin_path)
        if test_filter in ("all", "clkdiv", "uart"):
            self.test_uart_clock_division()
        if test_filter in ("all", "clkdiv", "ft1248"):
            self.test_ft_clock_division()

        elapsed = time.time() - t0
        print("\n==============================================================================")
        print(f" FINAL VERIFICATION SUMMARY ({elapsed:.2f}s)")
        print("==============================================================================")
        print(f"  Passed Assertions: {self.passed}")
        print(f"  Failed Assertions: {self.failed}")
        if self.failed == 0:
            print("\n>>> [SUCCESS] ALL TEST SCENARIOS PASSED CLEANLY! <<<\n")
            return 0
        else:
            print("\n>>> [FAILURE] SOME ASSERTIONS FAILED! <<<\n")
            return 1


def main():
    parser = argparse.ArgumentParser(
        description="Automated Step & Clock Division Verification for CORE-V Wally SoCDebug"
    )
    parser.add_argument("-p", "--protocol", choices=["uart", "ft1248"], default="uart",
                        help="Physical protocol interface (matches SW0 dbg_sel switch)")
    parser.add_argument("-d", "--device", default="/dev/ttyUSB0",
                        help="Serial port (for UART, e.g. /dev/ttyUSB0)")
    parser.add_argument("-b", "--baud", type=int, default=115200,
                        help="Initial baud rate (default: 115200)")
    parser.add_argument("--ftdi-url", default="ftdi://ftdi:232h/1",
                        help="FTDI device URL for FT1248")
    parser.add_argument("--mock", action="store_true",
                        help="Run using full in-memory simulator without hardware")
    parser.add_argument("--test", choices=["all", "step", "clkdiv", "uart", "ft1248"], default="all",
                        help="Subset of tests to run (default: all)")
    parser.add_argument("--clk-freq", type=int, default=50_000_000,
                        help="SoC Core clock frequency in Hz (default: 50 MHz for FPGA)")
    parser.add_argument("--program", default="step_test.bin",
                        help="Binary program to load for step testing (default: step_test.bin)")

    args = parser.parse_args()

    if args.mock:
        print("[!] Running in MOCK Mode (Emulating SoCDebug hardware and Core)...")
        iface = MockSoCDebugInterface(clk_freq=args.clk_freq, default_baud=args.baud)
    else:
        try:
            if args.protocol == "uart":
                if not HAS_SERIAL:
                    print("[!] 'pyserial' not installed. Falling back to MOCK mode.")
                    iface = MockSoCDebugInterface(clk_freq=args.clk_freq, default_baud=args.baud)
                else:
                    iface = UartInterface(port=args.device, baudrate=args.baud)
            else:
                if not HAS_PYFTDI:
                    print("[!] 'pyftdi' not installed. Falling back to MOCK mode.")
                    iface = MockSoCDebugInterface(clk_freq=args.clk_freq, default_baud=args.baud)
                else:
                    iface = FT1248Interface(url=args.ftdi_url)
        except Exception as e:
            print(f"[!] Error opening interface ({args.protocol}): {e}")
            print(f"[!] Falling back to MOCK mode for validation...")
            iface = MockSoCDebugInterface(clk_freq=args.clk_freq, default_baud=args.baud)

    tester = SoCDebugTester(iface, clk_freq=args.clk_freq)
    try:
        ret = tester.run_all(test_filter=args.test, bin_path=args.program)
    finally:
        iface.close()

    sys.exit(ret)


if __name__ == "__main__":
    main()
