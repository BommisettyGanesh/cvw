#!/usr/bin/env python3
"""
Automated Test Runner for UC Berkeley riscv-tests on CPU Core Only.
Tests riscv_cpu directly connected to ahb_ram in QuestaSim and monitors tohost.
"""

import os
import sys
import glob
import re
import struct
import shutil
import subprocess
import argparse

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.dirname(os.path.dirname(SCRIPT_DIR))

# Toolchain definitions
CVW_BIN = "/home/ganesh/cvw/bin"
GCC = os.path.join(CVW_BIN, "riscv64-unknown-elf-gcc") if os.path.exists(os.path.join(CVW_BIN, "riscv64-unknown-elf-gcc")) else (shutil.which("riscv64-unknown-elf-gcc") or "riscv64-unknown-elf-gcc")
OBJCOPY = os.path.join(CVW_BIN, "riscv64-unknown-elf-objcopy") if os.path.exists(os.path.join(CVW_BIN, "riscv64-unknown-elf-objcopy")) else (shutil.which("riscv64-unknown-elf-objcopy") or "riscv64-unknown-elf-objcopy")
NM = os.path.join(CVW_BIN, "riscv64-unknown-elf-nm") if os.path.exists(os.path.join(CVW_BIN, "riscv64-unknown-elf-nm")) else (shutil.which("riscv64-unknown-elf-nm") or "riscv64-unknown-elf-nm")
VSIM = "/home/ganesh/altera_lite/25.1std/questa_fse/bin/vsim"
VLOG = "/home/ganesh/altera_lite/25.1std/questa_fse/bin/vlog"
VLIB = "/home/ganesh/altera_lite/25.1std/questa_fse/bin/vlib"

ENV_DIR = os.path.join(SCRIPT_DIR, "env")
SRC_DIR = os.path.join(SCRIPT_DIR, "src")
LINK_LD = os.path.join(ENV_DIR, "link.ld")

TEST_GROUPS = {
    "alu": [
        "rv32ui-p-add", "rv32ui-p-addi", "rv32ui-p-sub", "rv32ui-p-and",
        "rv32ui-p-or", "rv32ui-p-xor", "rv32ui-p-sll", "rv32ui-p-srl",
        "rv32ui-p-sra", "rv32ui-p-slt", "rv32ui-p-sltu", "rv32ui-p-lui",
        "rv32ui-p-auipc"
    ],
    "branch": [
        "rv32ui-p-beq", "rv32ui-p-bne", "rv32ui-p-blt", "rv32ui-p-bge",
        "rv32ui-p-jal", "rv32ui-p-jalr"
    ],
    "memory": [
        "rv32ui-p-lw", "rv32ui-p-sw"
    ],
    "hazard": [
        "rv32ui-p-hazard"
    ]
}

def run_cmd(cmd, cwd=None):
    res = subprocess.run(cmd, shell=True, cwd=cwd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    return res.returncode == 0, res.stdout

def compile_core_rtl():
    work_dir = os.path.join(SCRIPT_DIR, "work")
    if os.path.exists(work_dir):
        shutil.rmtree(work_dir)
    
    ok, out = run_cmd(f"{VLIB} work", cwd=SCRIPT_DIR)
    if not ok:
        print(f"[-] vlib failed:\n{out}")
        return False

    components = sorted(glob.glob(f"{REPO_ROOT}/components/*.v"))
    core_files = [
        f"{REPO_ROOT}/main/riscv_cpu.v",
        f"{REPO_ROOT}/main/ahb_ram.v",
        f"{SCRIPT_DIR}/tb_core_berkeley.sv"
    ]
    src_str = " ".join(components + core_files)
    vlog_cmd = f"{VLOG} -sv -timescale 1ns/1ps -work work +incdir+{REPO_ROOT}/main +incdir+{REPO_ROOT}/components {src_str}"
    ok, out = run_cmd(vlog_cmd, cwd=SCRIPT_DIR)
    if not ok:
        print(f"[-] vlog failed:\n{out}")
        return False
    return True

def get_symbols(elf_file):
    ok, out = run_cmd(f"{NM} {elf_file}")
    symbols = {}
    if ok:
        for line in out.splitlines():
            parts = line.strip().split()
            if len(parts) >= 3:
                try:
                    symbols[parts[2]] = int(parts[0], 16)
                except ValueError:
                    pass
    return symbols

def bin_to_hex(bin_path, hex_path):
    with open(bin_path, "rb") as f:
        data = f.read()
    pad = (4 - (len(data) % 4)) % 4
    data += b'\x00' * pad
    words = struct.unpack(f"<{len(data)//4}I", data)
    with open(hex_path, "w") as f:
        for w in words:
            f.write(f"{w:08x}\n")

def run_test(test_name, build_dir):
    src_file = os.path.join(SRC_DIR, f"{test_name}.S")
    if not os.path.exists(src_file):
        print(f"[-] Source file for {test_name} not found!")
        return False

    elf_file = os.path.join(build_dir, f"{test_name}.elf")
    bin_file = os.path.join(build_dir, f"{test_name}.bin")
    hex_file = os.path.join(build_dir, f"{test_name}.hex")

    compile_cmd = (
        f"{GCC} -march=rv32i -mabi=ilp32 -mno-relax -static -mcmodel=medany -fvisibility=hidden -nostdlib -nostartfiles "
        f"-T {LINK_LD} -I {ENV_DIR} "
        f"{src_file} -o {elf_file}"
    )

    ok, out = run_cmd(compile_cmd)
    if not ok:
        print(f"[-] GCC Compilation failed for {test_name}:\n{out}")
        return False

    run_cmd(f"{OBJCOPY} -O binary {elf_file} {bin_file}")
    bin_to_hex(bin_file, hex_file)

    symbols = get_symbols(elf_file)
    tohost = symbols.get("tohost", 0x80001000)

    # Run QuestaSim on CPU Core Only
    vsim_cmd = (
        f"{VSIM} -c -voptargs=\"+acc\" -do \"run -all; quit -f\" work.tb_core_berkeley "
        f"\"+HEX={hex_file}\" \"+NAME={test_name}\" \"+TOHOST={tohost:x}\" \"+MAX_CYCLES=50000\""
    )
    ok, out = run_cmd(vsim_cmd, cwd=SCRIPT_DIR)
    
    # Check for PASS marker
    for line in out.splitlines():
        if "[PASS]" in line:
            print(line)
            sys.stdout.flush()
            return True
        elif "[FAIL]" in line or "[TIMEOUT]" in line:
            print(line)
            sys.stdout.flush()
            return False

    print(f"  [FAIL] {test_name:<20} Unknown simulation error!\n{out}")
    sys.stdout.flush()
    return False

def main():
    parser = argparse.ArgumentParser(description="UC Berkeley riscv-tests CPU Core Runner")
    parser.add_argument("--group", choices=["alu", "branch", "memory", "hazard", "all"], default="all")
    parser.add_argument("--test", type=str, help="Specific test to execute")
    parser.add_argument("--recompile-rtl", action="store_true", default=True, help="Recompile core RTL fresh")
    args = parser.parse_args()

    print("==================================================================")
    print(" UC Berkeley Self-Checking ISA Tests (riscv-tests / Core Only)    ")
    print("==================================================================")

    if args.recompile_rtl:
        print("[*] Compiling riscv_cpu RTL and testbench fresh in QuestaSim...")
        if not compile_core_rtl():
            sys.exit(1)
        print("[+] RTL Compilation successful.\n")

    build_dir = os.path.join(SCRIPT_DIR, "build")
    os.makedirs(build_dir, exist_ok=True)

    tests_to_run = []
    if args.test:
        tests_to_run = [args.test]
    elif args.group == "all":
        for grp in ["alu", "branch", "memory", "hazard"]:
            tests_to_run.extend(TEST_GROUPS[grp])
    else:
        tests_to_run = TEST_GROUPS[args.group]

    passed = 0
    failed = 0
    for t in tests_to_run:
        res = run_test(t, build_dir)
        if res: passed += 1
        else: failed += 1

    print("\n------------------------------------------------------------------")
    print(f" BERKELEY TEST RESULTS: {passed} PASSED, {failed} FAILED (Total: {len(tests_to_run)})")
    print("------------------------------------------------------------------")

    if failed == 0:
        print(">>> ALL UC BERKELEY CPU CORE TESTS PASSED! <<<\n")
        sys.exit(0)
    else:
        print(">>> UC BERKELEY VERIFICATION FAILED! <<<\n")
        sys.exit(1)

if __name__ == "__main__":
    main()
