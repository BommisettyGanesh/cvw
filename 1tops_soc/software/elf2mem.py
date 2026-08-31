import struct
import sys

with open(sys.argv[1], "rb") as f:
    data = f.read()

# pad to multiple of 4 bytes
if len(data) % 4 != 0:
    data += b'\x00' * (4 - (len(data) % 4))

print("@00000000")
for i in range(0, len(data), 4):
    word = struct.unpack("<I", data[i:i+4])[0]
    print(f"{word:08x}")
