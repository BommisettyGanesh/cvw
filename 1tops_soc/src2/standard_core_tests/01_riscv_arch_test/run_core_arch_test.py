#!/usr/bin/env python3
"""
Automated Test Runner for RISC-V International Architecture Tests on CPU Core Only.
Tests riscv_cpu directly connected to ahb_ram in QuestaSim and validates against Spike ISS.
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
SPIKE = os.path.join(CVW_BIN, "spike")
VSIM = "/home/ganesh/altera_lite/25.1std/questa_fse/bin/vsim"
VLOG = "/home/ganesh/altera_lite/25.1std/questa_fse/bin/vlog"
VLIB = "/home/ganesh/altera_lite/25.1std/questa_fse/bin/vlib"

# Standard Test Suites
WALLY_REF = "/home/ganesh/Desktop/wally_reference"
RV32I_SUITE_DIR = f"{WALLY_REF}/cvw/addins/riscv-arch-test/riscv-test-suite/rv32i_m/I/src"
ZICSR_SUITE_DIR = f"{WALLY_REF}/cvw/addins/riscv-arch-test-cvw/tests/rv32i/Zicsr"
PRIV_SUITE_DIR  = f"{WALLY_REF}/cvw/addins/riscv-arch-test/riscv-test-suite/rv32i_m/privilege/src"

ENV_DIR         = f"{WALLY_REF}/cvw/addins/riscv-arch-test/riscv-test-suite/env"
MODEL_ENV_DIR   = f"{WALLY_REF}/cvw/addins/riscv-arch-test/riscof-plugins/rv32/spike_simple/env"
LINK_LD         = f"{WALLY_REF}/cvw/tests/riscof/spike/env/link.ld"
ZICSR_ENV_DIR   = os.path.join(SCRIPT_DIR, "zicsr_env")
ZICSR_TESTS_ENV = f"{WALLY_REF}/cvw/addins/riscv-arch-test-cvw/tests/env"

TEST_GROUPS = {
    "alu": [
        "add-01", "addi-01", "and-01", "andi-01", "or-01", "ori-01",
        "xor-01", "xori-01", "sll-01", "slli-01", "srl-01", "srli-01",
        "sra-01", "srai-01", "slt-01", "slti-01", "sltu-01", "sltiu-01",
        "sub-01", "lui-01", "auipc-01"
    ],
    "branch": [
        "beq-01", "bne-01", "blt-01", "bge-01", "bltu-01", "bgeu-01",
        "jal-01", "jalr-01"
    ],
    "memory": [
        "lw-align-01", "lh-align-01", "lhu-align-01", "lb-align-01", "lbu-align-01",
        "sw-align-01", "sh-align-01", "sb-align-01"
    ],
    "priv": [
        "ecall", "ebreak"
    ],
    "zicsr": [
        "Zicsr-csrrw-00", "Zicsr-csrrs-00", "Zicsr-csrrc-00",
        "Zicsr-csrrwi-00", "Zicsr-csrrsi-00", "Zicsr-csrrci-00"
    ]
}

def run_cmd(cmd, cwd=None):
    res = subprocess.run(cmd, shell=True, cwd=cwd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    if res.returncode != 0:
        return False, res.stdout + "\n" + res.stderr
    return True, res.stdout

def compile_core_rtl():
    """Compiles the CPU core and single-cycle memory fresh into QuestaSim work library."""
    work_dir = os.path.join(SCRIPT_DIR, "work")
    if os.path.exists(work_dir):
        shutil.rmtree(work_dir, ignore_errors=True)

    ok, out = run_cmd(f"{VLIB} work", cwd=SCRIPT_DIR)
    if not ok:
        print(f"[RTL COMPILE ERROR] Failed to vlib work:\n{out}")
        return False

    components = sorted(glob.glob(f"{REPO_ROOT}/components/*.v"))
    core_files = [
        f"{REPO_ROOT}/main/riscv_cpu.v",
        f"{REPO_ROOT}/main/ahb_ram.v",
        f"{SCRIPT_DIR}/tb_core_arch.sv"
    ]
    src_str = " ".join(components + core_files)
    cmd = f"{VLOG} -sv -timescale 1ns/1ps -work work +incdir+{REPO_ROOT}/main +incdir+{REPO_ROOT}/components {src_str}"
    ok, out = run_cmd(cmd, cwd=SCRIPT_DIR)
    if not ok:
        print(f"[RTL COMPILE ERROR] Compilation failed:\n{out}")
        return False
    return True

def locate_source(test_name):
    if test_name.startswith("Zicsr"):
        s = os.path.join(ZICSR_SUITE_DIR, f"{test_name}.S")
        if os.path.exists(s): return s, "zicsr"
    s_priv = os.path.join(PRIV_SUITE_DIR, f"{test_name}.S")
    if os.path.exists(s_priv): return s_priv, "priv"
    s_i = os.path.join(RV32I_SUITE_DIR, f"{test_name}.S")
    if os.path.exists(s_i): return s_i, "rv32i"
    return None, None

def get_symbols(elf_file):
    symbols = {}
    ok, out = run_cmd(f"{NM} {elf_file}")
    if not ok: return symbols
    for line in out.splitlines():
        parts = line.split()
        if len(parts) == 3:
            addr, _, name = parts
            symbols[name] = int(addr, 16)
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
    os.makedirs(build_dir, exist_ok=True)
    src_file, test_type = locate_source(test_name)
    if not src_file:
        print(f"[-] Source file for {test_name} not found!")
        return False

    elf_file = os.path.join(build_dir, f"{test_name}.elf")
    bin_file = os.path.join(build_dir, f"{test_name}.bin")
    hex_file = os.path.join(build_dir, f"{test_name}.hex")
    spike_sig = os.path.join(build_dir, f"{test_name}.spike.sig")
    dut_sig   = os.path.join(build_dir, f"{test_name}.dut.sig")

    tfile = os.path.basename(src_file)
    if test_type == "zicsr":
        compile_cmd = (
            f"{GCC} -march=rv32i_zicsr -mabi=ilp32 -mno-relax -static -mcmodel=medany -fvisibility=hidden -nostdlib -nostartfiles "
            f"-T {LINK_LD} -I {ZICSR_ENV_DIR} -I {ZICSR_TESTS_ENV} -DSIGNATURE "
            f"-DSAIL_CLINT_BASE_ADDRESS=0x2000000 -DSAIL_SIMPLE_INTERRUPT_GENERATOR_BASE_ADDRESS=0x3000000 "
            f'-DTEST_FILE=\\"{tfile}\\" -DXLEN=32 '
            f"{src_file} -o {elf_file}"
        )
        spike_isa = "rv32i_zicsr"
    elif test_type == "priv":
        compile_cmd = (
            f"{GCC} -march=rv32i_zicsr -mabi=ilp32 -mno-relax -static -mcmodel=medany -fvisibility=hidden -nostdlib -nostartfiles "
            f"-T {LINK_LD} -I {MODEL_ENV_DIR} -I {ENV_DIR} -DTEST_CASE_1=True -Drvtest_mtrap_routine=True -DXLEN=32 "
            f"{src_file} -o {elf_file}"
        )
        spike_isa = "rv32i_zicsr"
    else:
        compile_cmd = (
            f"{GCC} -march=rv32i -mabi=ilp32 -mno-relax -static -mcmodel=medany -fvisibility=hidden -nostdlib -nostartfiles "
            f"-T {LINK_LD} -I {MODEL_ENV_DIR} -I {ENV_DIR} -DTEST_CASE_1=True -DXLEN=32 "
            f"{src_file} -o {elf_file}"
        )
        spike_isa = "rv32i"

    ok, out = run_cmd(compile_cmd)
    if not ok:
        print(f"[-] GCC Compilation failed for {test_name}:\n{out}")
        return False

    # Extract binary & hex
    run_cmd(f"{OBJCOPY} -O binary {elf_file} {bin_file}")
    bin_to_hex(bin_file, hex_file)

    symbols = get_symbols(elf_file)
    begin_sig = symbols.get("begin_signature", 0)
    end_sig   = symbols.get("end_signature", 0)
    tohost    = symbols.get("tohost", 0)

    # 1. Run Spike Golden Model
    spike_cmd = f"{SPIKE} --isa={spike_isa} --priv=m +signature={spike_sig} +signature-granularity=4 {elf_file}"
    ok, out = run_cmd(spike_cmd)
    if not ok or not os.path.exists(spike_sig):
        print(f"[-] Spike execution failed for {test_name}:\n{out}")
        return False

    # 2. Run QuestaSim on CPU Core Only
    vsim_cmd = (
        f"{VSIM} -c -voptargs=\"+acc\" -do \"run -all; quit -f\" work.tb_core_arch "
        f"\"+HEX={hex_file}\" \"+SIG={dut_sig}\" \"+TOHOST={tohost:x}\" "
        f"\"+BEGIN_SIG={begin_sig:x}\" \"+END_SIG={end_sig:x}\" \"+MAX_CYCLES=200000\""
    )
    ok, out = run_cmd(vsim_cmd, cwd=SCRIPT_DIR)
    if not ok or not os.path.exists(dut_sig):
        print(f"[-] QuestaSim execution failed for {test_name}:\n{out}")
        return False

    # 3. Compare Signatures
    with open(spike_sig, "r") as f:
        spike_lines = [l.strip().lower() for l in f if l.strip()]
    with open(dut_sig, "r") as f:
        dut_lines = [l.strip().lower() for l in f if l.strip()]

    if spike_lines == dut_lines:
        print(f"  [PASS] {test_name:<20} (Signature match: {len(dut_lines)} words)")
        return True
    else:
        print(f"  [FAIL] {test_name:<20} Signature MISMATCH!")
        for idx, (exp, act) in enumerate(zip(spike_lines, dut_lines)):
            if exp != act:
                print(f"         Word {idx}: Spike=0x{exp} vs DUT=0x{act}")
                break
        return False

def main():
    parser = argparse.ArgumentParser(description="RISC-V CPU Core Architecture Compliance Runner")
    parser.add_argument("--group", choices=["alu", "branch", "memory", "priv", "zicsr", "all"], default="all")
    parser.add_argument("--test", type=str, help="Specific test to execute")
    parser.add_argument("--recompile-rtl", action="store_true", default=True, help="Recompile core RTL fresh")
    args = parser.parse_args()

    print("==================================================================")
    print(" RISC-V International Architecture Tests (CPU Core Only vs Spike)")
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
        for grp in ["alu", "branch", "memory", "priv", "zicsr"]:
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
    print(f" ARCHITECTURE TEST RESULTS: {passed} PASSED, {failed} FAILED (Total: {len(tests_to_run)})")
    print("------------------------------------------------------------------")

    if failed == 0:
        print(">>> ALL CPU CORE ARCHITECTURAL COMPLIANCE TESTS PASSED! <<<\n")
        sys.exit(0)
    else:
        print(">>> ARCHITECTURAL COMPLIANCE VERIFICATION FAILED! <<<\n")
        sys.exit(1)

if __name__ == "__main__":
    main()
