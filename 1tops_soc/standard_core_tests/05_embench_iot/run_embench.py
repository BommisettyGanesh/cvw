#!/usr/bin/env python3
"""
Automated Test Runner for Embench-IoT Algorithmic Kernels on Pure CPU Core.
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
VSIM = "/home/ganesh/altera_lite/25.1std/questa_fse/bin/vsim"
VLOG = "/home/ganesh/altera_lite/25.1std/questa_fse/bin/vlog"
VLIB = "/home/ganesh/altera_lite/25.1std/questa_fse/bin/vlib"

KERNELS = {
    "crc32": [os.path.join(SCRIPT_DIR, "src", "crc32", "crc_32.c")],
    "matmult-int": [os.path.join(SCRIPT_DIR, "src", "matmult-int", "matmult-int.c")],
    "nettle-sha256": [os.path.join(SCRIPT_DIR, "src", "nettle-sha256", "nettle-sha256.c")],
    "edn": [os.path.join(SCRIPT_DIR, "src", "edn", "libedn.c")]
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
        f"{SCRIPT_DIR}/tb_core_embench.sv"
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

def run_kernel(kernel_name, build_dir):
    elf_file = os.path.join(build_dir, f"{kernel_name}.elf")
    bin_file = os.path.join(build_dir, f"{kernel_name}.bin")
    hex_file = os.path.join(build_dir, f"{kernel_name}.hex")

    kernel_c = KERNELS[kernel_name]
    support_c = [
        os.path.join(SCRIPT_DIR, "support", "main_embench.c"),
        os.path.join(SCRIPT_DIR, "support", "beebsc.c"),
        os.path.join(SCRIPT_DIR, "bsp", "syscalls.c")
    ]
    crt_s = os.path.join(SCRIPT_DIR, "bsp", "crt.S")
    link_ld = os.path.join(SCRIPT_DIR, "bsp", "link.ld")

    compile_cmd = (
        f"{GCC} -O2 -march=rv32i_zicsr_zicntr -mabi=ilp32 -mno-relax -static -nostdlib -nostartfiles "
        f"-T {link_ld} {crt_s} {' '.join(support_c)} {' '.join(kernel_c)} "
        f"-I {os.path.join(SCRIPT_DIR, 'support')} -I {os.path.join(SCRIPT_DIR, 'bsp')} "
        f"-I {os.path.join(SCRIPT_DIR, 'src', kernel_name)} "
        f"-DCPU_MHZ=1 -DWARMUP_HEAT=1 -DLOCAL_SCALE_FACTOR=1 -o {elf_file} -lgcc"
    )

    print(f"\n[*] Compiling Embench kernel '{kernel_name}' with GCC...")
    ok, out = run_cmd(compile_cmd)
    if not ok:
        print(f"[-] GCC Compilation failed:\n{out}")
        return False
    print(f"[+] Kernel '{kernel_name}' successfully compiled.")

    run_cmd(f"{OBJCOPY} -O binary {elf_file} {bin_file}")
    bin_to_hex(bin_file, hex_file)

    print(f"[*] Running '{kernel_name}' on riscv_cpu in QuestaSim...")
    vsim_cmd = f"{VSIM} -c -voptargs=\"+acc\" -do \"run -all; quit -f\" work.tb_core_embench \"+HEX={hex_file}\""
    
    p = subprocess.Popen(vsim_cmd, shell=True, cwd=SCRIPT_DIR, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    passed = False
    for line in iter(p.stdout.readline, ''):
        line_clean = line.rstrip()
        if line_clean.startswith("# Loading") or line_clean.startswith("# ** Note: (vsim-3812") or line_clean.startswith("# Reading"):
            continue
        if line_clean.startswith("# "):
            line_clean = line_clean[2:]
        if line_clean:
            print(line_clean)
            sys.stdout.flush()
        if "[PASS]" in line:
            passed = True

    p.wait()
    return passed

def main():
    parser = argparse.ArgumentParser(description="Embench-IoT CPU Core Runner")
    parser.add_argument("--kernel", choices=list(KERNELS.keys()) + ["all"], default="all", help="Kernel to run")
    parser.add_argument("--recompile-rtl", action="store_true", default=True, help="Recompile core RTL fresh")
    args = parser.parse_args()

    print("==================================================================")
    print(" Embench-IoT Algorithmic Benchmark Suite (CPU Core Only)          ")
    print("==================================================================")

    if args.recompile_rtl:
        print("[*] Compiling riscv_cpu RTL and testbench fresh in QuestaSim...")
        if not compile_core_rtl():
            sys.exit(1)
        print("[+] RTL Compilation successful.\n")

    build_dir = os.path.join(SCRIPT_DIR, "build")
    os.makedirs(build_dir, exist_ok=True)

    kernels_to_run = list(KERNELS.keys()) if args.kernel == "all" else [args.kernel]

    passed = 0
    failed = 0
    for k in kernels_to_run:
        res = run_kernel(k, build_dir)
        if res: passed += 1
        else: failed += 1

    print("\n------------------------------------------------------------------")
    print(f" EMBENCH-IOT RESULTS: {passed} PASSED, {failed} FAILED (Total: {len(kernels_to_run)})")
    print("------------------------------------------------------------------")

    if failed == 0:
        print(">>> ALL EMBENCH-IOT KERNELS PASSED AND VERIFIED! <<<\n")
        sys.exit(0)
    else:
        print(">>> EMBENCH-IOT BENCHMARK VERIFICATION FAILED! <<<\n")
        sys.exit(1)

if __name__ == "__main__":
    main()
