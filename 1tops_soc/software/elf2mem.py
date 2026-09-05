import sys

if len(sys.argv) != 4:
    print("Usage: elf2mem.py <input.bin> <test_instr.mem> <test_data.mem>")
    sys.exit(1)

input_bin = sys.argv[1]
instr_mem = sys.argv[2]
data_mem = sys.argv[3]

with open(input_bin, "rb") as f:
    data = f.read()

# pad to multiple of 4 bytes
if len(data) % 4 != 0:
    data += b'\x00' * (4 - (len(data) % 4))

# Split at 8KB boundary (0x2000 bytes)
# If the binary is smaller than 8KB, all of it goes to instr
instr_data = data[:0x2000]
data_data = data[0x2000:] if len(data) > 0x2000 else b''

def write_mem(filename, binary_data):
    with open(filename, "w") as f:
        f.write("@00000000\n")
        for i in range(0, len(binary_data), 4):
            word = int.from_bytes(binary_data[i:i+4], byteorder='little')
            f.write(f"{word:08x}\n")

write_mem(instr_mem, instr_data)
write_mem(data_mem, data_data)
