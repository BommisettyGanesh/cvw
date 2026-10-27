#!/usr/bin/env python3
"""
Automated Test Runner for Google RISCV-DV / Constrained Random Torture Suite on Pure CPU Core.
"""

import os
import sys
import glob
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
SPIKE = os.path.join(CVW_BIN, "spike") if os.path.exists(os.path.join(CVW_BIN, "spike")) else (shutil.which("spike") or "spike")
VSIM = "/home/ganesh/altera_lite/25.1std/questa_fse/bin/vsim"
VLOG = "/home/ganesh/altera_lite/25.1std/questa_fse/bin/vlog"
VLIB = "/home/ganesh/altera_lite/25.1std/questa_fse/bin/vlib"

TEST_NAMES = [
    "torture_raw_hazards",
    "torture_load_use_hazard",
    "torture_branch_storm",
    "torture_memory_stress",
    "torture_complex_random"
]

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
        f"{SCRIPT_DIR}/tb_core_torture.sv"
    ]
    src_str = " ".join(components + core_files)
    vlog_cmd = f"{VLOG} -sv -timescale 1ns/1ps -work work +incdir+{REPO_ROOT}/main +incdir+{REPO_ROOT}/components {src_str}"
    ok, out = run_cmd(vlog_cmd, cwd=SCRIPT_DIR)
    if not ok:
        print(f"[-] vlog failed:\n{out}")
        return False
    return True

def bin_to_hex(bin_path, hex_path):
    with open(bin_path, "rb") as f:
        data = f.read()
    pad = (4 - (len(data) % 4)) % 4
    data += b'\x00' * pad
    words = struct.unpack(f"<{len(data)//4}I", data)
    with open(hex_path, "w") as f:
        for w in words:
            f.write(f"{w:08x}\n")

def run_test(test_name, build_dir, run_spike=True):
    src_file = os.path.join(SCRIPT_DIR, "src", f"{test_name}.S")
    elf_file = os.path.join(build_dir, f"{test_name}.elf")
    bin_file = os.path.join(build_dir, f"{test_name}.bin")
    hex_file = os.path.join(build_dir, f"{test_name}.hex")
    link_ld  = os.path.join(SCRIPT_DIR, "env", "link.ld")
    env_dir  = os.path.join(SCRIPT_DIR, "env")

    # 1. Compile with GCC
    compile_cmd = (
        f"{GCC} -march=rv32i_zicsr -mabi=ilp32 -mno-relax -static -nostdlib -nostartfiles "
        f"-T {link_ld} -I {env_dir} {src_file} -o {elf_file}"
    )
    ok, out = run_cmd(compile_cmd)
    if not ok:
        print(f"[-] Compilation failed for {test_name}:\n{out}")
        return False, 0, 0, 0.0

    # 2. Cross-verify with Spike ISS
    if run_spike and os.path.exists(SPIKE):
        spike_cmd = f"{SPIKE} --isa=rv32i_zicsr {elf_file}"
        s_ok, s_out = run_cmd(spike_cmd)
        if not s_ok:
            print(f"[-] Spike verification failed for {test_name}:\n{s_out}")
            return False, 0, 0, 0.0

    # 3. Create hex
    run_cmd(f"{OBJCOPY} -O binary {elf_file} {bin_file}")
    bin_to_hex(bin_file, hex_file)

    # 4. Run on riscv_cpu in QuestaSim
    vsim_cmd = f"{VSIM} -c -voptargs=\"+acc\" -do \"run -all; quit -f\" work.tb_core_torture \"+HEX={hex_file}\""
    ok, out = run_cmd(vsim_cmd, cwd=SCRIPT_DIR)
    
    passed = "[PASS] Torture Test PASSED!" in out
    cycles = 0
    instructions = 0
    cpi = 0.0

    for line in out.splitlines():
        if "Cycles:" in line and "Instructions:" in line:
            parts = line.strip().split("|")
            try:
                cycles = int(parts[0].split(":")[1].strip())
                instructions = int(parts[1].split(":")[1].strip())
                cpi = float(parts[2].split(":")[1].strip())
            except Exception:
                pass

    return passed, cycles, instructions, cpi

def main():
    parser = argparse.ArgumentParser(description="Google RISCV-DV / Torture Test Runner")
    parser.add_argument("--test", choices=TEST_NAMES + ["all"], default="all", help="Test to run")
    parser.add_argument("--regenerate", action="store_true", help="Regenerate assembly tests")
    args = parser.parse_args()

    print("==================================================================")
    print(" Google RISCV-DV / Constrained Random Torture Suite (CPU Core)    ")
    print("==================================================================")

    if args.regenerate or not os.path.exists(os.path.join(SCRIPT_DIR, "src", "torture_raw_hazards.S")):
        print("[*] Regenerating assembly tests from python generator...")
        run_cmd(f"python3 {os.path.join(SCRIPT_DIR, 'src', 'generate_torture_tests.py')}")

    print("[*] Compiling riscv_cpu RTL and testbench fresh in QuestaSim...")
    if not compile_core_rtl():
        sys.exit(1)
    print("[+] RTL Compilation successful.\n")

    build_dir = os.path.join(SCRIPT_DIR, "build")
    os.makedirs(build_dir, exist_ok=True)

    tests_to_run = TEST_NAMES if args.test == "all" else [args.test]

    results = []
    for t in tests_to_run:
        print(f"[*] Running {t}...")
        passed, cycles, instrs, cpi = run_test(t, build_dir)
        status_str = "PASS" if passed else "FAIL"
        results.append((t, status_str, cycles, instrs, cpi))
        if passed:
            print(f"    [+] {t}: PASSED (Cycles: {cycles}, Instructions: {instrs}, CPI: {cpi:.2f})")
        else:
            print(f"    [-] {t}: FAILED")

    print("\n------------------------------------------------------------------")
    print(" GOOGLE RISCV-DV / TORTURE TEST RESULTS SUMMARY")
    print("------------------------------------------------------------------")
    print(f"{'Test Name':<28} | {'Status':<6} | {'Cycles':<8} | {'Instrs':<8} | {'CPI':<5}")
    print("-" * 66)
    
    all_passed = True
    for name, status, cyc, inst, cpi in results:
        print(f"{name:<28} | {status:<6} | {cyc:<8} | {inst:<8} | {cpi:<5.2f}")
        if status != "PASS":
            all_passed = False

    print("------------------------------------------------------------------")
    if all_passed:
        print(">>> ALL GOOGLE RISCV-DV / TORTURE TESTS PASSED! <<<\n")
        sys.exit(0)
    else:
        print(">>> TORTURE TEST SUITE FAILED! <<<\n")
        sys.exit(1)

if __name__ == "__main__":
    main()
