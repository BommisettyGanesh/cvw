#!/usr/bin/env python3
"""
Automated Bare-Metal C Program & Benchmark Runner for RISC-V AHB-Lite SoC.
Compiles C programs with riscv64-unknown-elf-gcc (RV32I soft-mul) and runs them in QuestaSim.
"""

import os
import sys
import glob
import struct
import shutil
import subprocess
import argparse

CVW_BIN = "/home/ganesh/cvw/bin"
if os.path.exists(os.path.join(CVW_BIN, "riscv64-unknown-elf-gcc")):
    GCC = os.path.join(CVW_BIN, "riscv64-unknown-elf-gcc")
    OBJCOPY = os.path.join(CVW_BIN, "riscv64-unknown-elf-objcopy")
    OBJDUMP = os.path.join(CVW_BIN, "riscv64-unknown-elf-objdump")
    NM = os.path.join(CVW_BIN, "riscv64-unknown-elf-nm")
else:
    GCC = shutil.which("riscv64-unknown-elf-gcc") or "/usr/bin/riscv64-unknown-elf-gcc"
    OBJCOPY = shutil.which("riscv64-unknown-elf-objcopy") or "/usr/bin/riscv64-unknown-elf-objcopy"
    OBJDUMP = shutil.which("riscv64-unknown-elf-objdump") or "/usr/bin/riscv64-unknown-elf-objdump"
    NM = shutil.which("riscv64-unknown-elf-nm") or "/usr/bin/riscv64-unknown-elf-nm"

VSIM = "/home/ganesh/altera_lite/25.1std/questa_fse/bin/vsim"
VLOG = "/home/ganesh/altera_lite/25.1std/questa_fse/bin/vlog"
VLIB = "/home/ganesh/altera_lite/25.1std/questa_fse/bin/vlib"

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.dirname(os.path.dirname(SCRIPT_DIR))
BSP_DIR = os.path.join(SCRIPT_DIR, "bsp")
SRC_DIR = os.path.join(SCRIPT_DIR, "src")
LINK_LD = os.path.join(BSP_DIR, "link.ld")

def run_cmd(cmd, cwd=None):
    res = subprocess.run(cmd, shell=True, cwd=cwd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    if res.returncode != 0:
        return False, res.stdout + "\n" + res.stderr
    return True, res.stdout

def compile_rtl(verbose=False):
    """Compiles the complete RISC-V SoC and tb_c_bench into QuestaSim work directory."""
    work_dir = os.path.join(SCRIPT_DIR, "work")
    if os.path.exists(work_dir):
        shutil.rmtree(work_dir, ignore_errors=True)

    ok, out = run_cmd(f"{VLIB} work", cwd=SCRIPT_DIR)
    if not ok:
        print("[RTL COMPILE ERROR] Failed to vlib work:\n" + out)
        return False

    components = sorted(glob.glob(f"{REPO_ROOT}/components/*.v"))
    main_files = [
        f"{REPO_ROOT}/main/riscv_cpu.v",
        f"{REPO_ROOT}/main/soc/multiplier_ahb.v",
        f"{REPO_ROOT}/main/soc/riscv_soc_ahb.v"
    ]
    uncore_files = sorted(glob.glob(f"{REPO_ROOT}/uncore/*.sv"))
    debugger_files = sorted(glob.glob(f"{REPO_ROOT}/debugger/*.v") + glob.glob(f"{REPO_ROOT}/debugger/*.sv"))
    tb_file = f"{SCRIPT_DIR}/tb_c_bench.v"

    src_files = components + main_files + uncore_files + debugger_files + [tb_file]
    src_str = " ".join(src_files)

    cmd = f"{VLOG} -sv -work work +incdir+{REPO_ROOT}/main +incdir+{REPO_ROOT}/main/soc +incdir+{REPO_ROOT}/components +incdir+{REPO_ROOT}/uncore +incdir+{REPO_ROOT}/debugger {src_str}"
    ok, out = run_cmd(cmd, cwd=SCRIPT_DIR)
    if not ok:
        print("[RTL COMPILE ERROR] Compilation failed:\n" + out)
        return False
    if verbose:
        print(out)
    return True

def bin_to_hex(bin_path, hex_path):
    with open(bin_path, "rb") as f:
        data = f.read()
    rem = len(data) % 4
    if rem != 0:
        data += b'\x00' * (4 - rem)
    with open(hex_path, "w") as f:
        for i in range(0, len(data), 4):
            word = struct.unpack("<I", data[i:i+4])[0]
            f.write(f"{word:08x}\n")

def get_symbols(elf_path):
    ok, out = run_cmd(f"{NM} {elf_path}")
    if not ok:
        raise RuntimeError("nm failed:\n" + out)
    symbols = {}
    for line in out.strip().splitlines():
        parts = line.split()
        if len(parts) >= 3:
            addr, sym_type, name = parts[0], parts[1], parts[2]
            symbols[name] = int(addr, 16)
    return symbols

def compile_c_test(test_name, extra_cflags="", iterations=1):
    build_dir = os.path.join(SCRIPT_DIR, "build", test_name)
    os.makedirs(build_dir, exist_ok=True)

    elf_file = os.path.join(build_dir, f"{test_name}.elf")
    bin_file = os.path.join(build_dir, f"{test_name}.bin")
    hex_file = os.path.join(build_dir, f"{test_name}.hex")
    dump_file = os.path.join(build_dir, f"{test_name}.objdump")

    bsp_srcs = [
        os.path.join(BSP_DIR, "crt.S"),
        os.path.join(BSP_DIR, "syscalls.c")
    ]

    c_sources = []
    include_dirs = [BSP_DIR]

    if test_name == "hello":
        c_sources = [os.path.join(SRC_DIR, "hello", "hello.c")]
    elif test_name == "matmul":
        c_sources = [os.path.join(SRC_DIR, "matmul", "matmul.c")]
    elif test_name == "qsort":
        c_sources = [os.path.join(SRC_DIR, "qsort", "qsort.c")]
    elif test_name == "coremark":
        cm_dir = os.path.join(SRC_DIR, "coremark")
        include_dirs.append(cm_dir)
        c_sources = [
            os.path.join(cm_dir, "core_main.c"),
            os.path.join(cm_dir, "core_list_join.c"),
            os.path.join(cm_dir, "core_matrix.c"),
            os.path.join(cm_dir, "core_state.c"),
            os.path.join(cm_dir, "core_util.c"),
            os.path.join(cm_dir, "core_portme.c")
        ]
        extra_cflags += f" -DITERATIONS={iterations} -DPERFORMANCE_RUN=1 -DTOTAL_DATA_SIZE=2000"
    else:
        # Custom user file
        if os.path.exists(test_name):
            c_sources = [test_name]
        else:
            raise FileNotFoundError(f"Unknown test benchmark: {test_name}")

    inc_str = " ".join([f"-I{d}" for d in include_dirs])
    src_str = " ".join(bsp_srcs + c_sources)

    cflags = (
        f"-march=rv32i_zicsr_zicntr -mabi=ilp32 -O2 -static -nostdlib -mstrict-align "
        f"-fno-builtin -fno-tree-loop-distribute-patterns "
        f"-T{LINK_LD} {inc_str} {extra_cflags}"
    )

    cmd = f"{GCC} {cflags} {src_str} -o {elf_file} -lgcc"
    ok, out = run_cmd(cmd)
    if not ok:
        print(f"[GCC ERROR] Compilation failed for {test_name}:\n{out}")
        return False, None, None

    # Disassembly dump
    run_cmd(f"{OBJDUMP} -d -S {elf_file} > {dump_file}")

    # Generate flat binary & hex
    ok, out = run_cmd(f"{OBJCOPY} -O binary {elf_file} {bin_file}")
    if not ok:
        print(f"[OBJCOPY ERROR]:\n{out}")
        return False, None, None

    bin_to_hex(bin_file, hex_file)
    return True, elf_file, hex_file

def run_benchmark(test_name, max_cycles=10000000, wait_states="0", iterations=1):
    print(f"\n========================================================")
    print(f"[*] Compiling C Benchmark: {test_name.upper()}")
    print(f"========================================================")
    ok, elf_file, hex_file = compile_c_test(test_name, iterations=iterations)
    if not ok:
        return False

    symbols = get_symbols(elf_file)
    tohost_addr = symbols.get("tohost")
    if tohost_addr is None:
        print("[ERROR] 'tohost' symbol not found in ELF!")
        return False

    print(f"[+] Compiled successfully -> ELF size: {os.path.getsize(elf_file)} bytes")
    print(f"[+] Entry point: 0x{symbols.get('_start', 0x80000000):08x}")
    print(f"[+] tohost address: 0x{tohost_addr:08x}")
    print(f"[*] Launching simulation in QuestaSim...\n")

    wait_arg = ""
    if str(wait_states).lower() == "random":
        wait_arg = "+AHB_WAIT_RANDOM"
    elif str(wait_states).isdigit() and int(wait_states) > 0:
        wait_arg = f"+AHB_WAIT_STATES={wait_states}"

    vsim_cmd = (
        f"{VSIM} -c -voptargs=\"+acc\" -do 'run -all; quit' work.tb_c_bench "
        f"+HEX={hex_file} +TOHOST={tohost_addr:x} +MAX_CYCLES={max_cycles} {wait_arg}"
    )

    p = subprocess.Popen(
        vsim_cmd, shell=True, cwd=SCRIPT_DIR,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True
    )

    in_uart = False
    for line in iter(p.stdout.readline, ''):
        # Filter Questa header noise, print benchmark output directly
        if line.startswith("# ") and not line.startswith("# **") and not line.startswith("# Loading"):
            clean = line[2:]
            sys.stdout.write(clean)
            sys.stdout.flush()
        elif "[TB]" in line:
            sys.stdout.write(line)
            sys.stdout.flush()

    p.wait()
    return p.returncode == 0

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Run Bare-Metal C Benchmarks on RISC-V SoC")
    parser.add_argument("--test", choices=["hello", "matmul", "qsort", "coremark"], default="hello",
                        help="Benchmark to execute (hello, matmul, qsort, coremark)")
    parser.add_argument("--recompile-rtl", action="store_true", help="Recompile core RTL with QuestaSim vlog")
    parser.add_argument("--max-cycles", type=int, default=10000000, help="Maximum simulation clock cycles")
    parser.add_argument("--wait-states", default="0", help="AHB wait states: '0', '1', '2', or 'random'")
    parser.add_argument("--iterations", type=int, default=1, help="CoreMark iterations (default: 1 for fast simulation)")
    args = parser.parse_args()

    work_dir = os.path.join(SCRIPT_DIR, "work")
    if args.recompile_rtl or not os.path.exists(work_dir):
        print("[*] Compiling SoC RTL & testbench in QuestaSim...")
        if not compile_rtl():
            sys.exit(1)
        print("[✓] RTL compilation finished successfully.\n")

    success = run_benchmark(args.test, max_cycles=args.max_cycles,
                            wait_states=args.wait_states, iterations=args.iterations)
    if success:
        print(f"\n[✓] Benchmark '{args.test}' execution completed successfully!")
    else:
        print(f"\n[✗] Benchmark '{args.test}' failed!")
        sys.exit(1)
