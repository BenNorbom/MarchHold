"""Packs build/icon_*.png into icon.ico (PNG-compressed ICO entries)."""
import os
import struct
import sys

root = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
sizes = [16, 24, 32, 48, 64, 128, 256]
images = [open(os.path.join(root, "build", f"icon_{s}.png"), "rb").read() for s in sizes]
header = struct.pack("<HHH", 0, 1, len(images))
offset = 6 + 16 * len(images)
entries = b""
for s, data in zip(sizes, images):
    entries += struct.pack("<BBBBHHII", s % 256, s % 256, 0, 0, 1, 32, len(data), offset)
    offset += len(data)
with open(os.path.join(root, "icon.ico"), "wb") as f:
    f.write(header + entries + b"".join(images))
print("icon.ico written")
