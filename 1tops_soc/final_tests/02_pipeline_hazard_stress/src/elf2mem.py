import sys

if len(sys.argv) < 4:
    print("Usage: elf2mem.py <input.bin> <test_instr.mem> <test_data.mem> [split_boundary_hex]")
    sys.exit(1)

input_bin = sys.argv[1]
instr_mem = sys.argv[2]
data_mem = sys.argv[3]
split_boundary = int(sys.argv[4], 16) if len(sys.argv) > 4 else 0x8000

with open(input_bin, "rb") as f:
    data = f.read()

# pad to multiple of 4 bytes
if len(data) % 4 != 0:
    data += b'\x00' * (4 - (len(data) % 4))

instr_data = data[:split_boundary]
data_data = data[split_boundary:] if len(data) > split_boundary else b''

def write_mem(filename, binary_data):
    with open(filename, "w") as f:
        f.write("@00000000\n")
        for i in range(0, len(binary_data), 4):
            word = int.from_bytes(binary_data[i:i+4], byteorder='little')
            f.write(f"{word:08x}\n")

write_mem(instr_mem, instr_data)
write_mem(data_mem, data_data)
