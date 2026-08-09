import os
import subprocess

wally_dir = "/home/ganesh/Desktop/cvw"
riscv_dir = "/home/ganesh/cvw"
os.makedirs(riscv_dir, exist_ok=True)
os.makedirs(os.path.join(riscv_dir, "logs"), exist_ok=True)

log_path = os.path.join(riscv_dir, "install.log")
with open(log_path, "a") as log_file:
    log_file.write("\n========================================\nResuming Wally toolchain installation...\n========================================\n")
    log_file.flush()

    env = os.environ.copy()
    env["RISCV"] = riscv_dir
    env["WALLY"] = wally_dir
    env["GIT_TERMINAL_PROMPT"] = "0"
    env["PATH"] = f"{riscv_dir}/bin:" + env.get("PATH", "")

    cmd = [os.path.join(wally_dir, "bin/wally-tool-chain-install.sh")]
    proc = subprocess.Popen(
        cmd,
        cwd=wally_dir,
        env=env,
        stdout=log_file,
        stderr=subprocess.STDOUT,
        start_new_session=True
    )
    print(f"Toolchain installer resumed with PID {proc.pid}")
