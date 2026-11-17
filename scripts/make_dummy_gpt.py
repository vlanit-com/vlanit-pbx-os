#!/usr/bin/env python3
"""make_dummy_gpt.py <file> — минимальная GPT с одним разделом (raw-файл).

Назначение: заглушка слота A в фазах 3/4 mirror (PCI-адрес для NVRAM),
разметка исключает её из кандидатов replace-агента. На хосте нет
sgdisk/parted — пишем GPT напрямую. Проверка агента: наличие раздела.
"""
import random
import struct
import sys
import uuid
import zlib

path = sys.argv[1]
SECTOR = 512

size = 20 * 1024 * 1024  # 20 МБ
with open(path, "wb") as f:
    f.truncate(size)

total_lba = size // SECTOR
first_usable = 34
last_usable = total_lba - 34

# GUID раздела: Microsoft basic data (0700)
type_guid = uuid.UUID("EBD0A0A2-B9E5-4433-87C0-68B6B72699C7").bytes_le
part_guid = uuid.UUID(int=random.getrandbits(128)).bytes_le
part_first = 2048
part_last = last_usable

entry = struct.pack(
    "<16s16sQQQ72s",
    type_guid, part_guid, part_first, part_last,
    0, b"\x00" * 72,
)
entries = entry + b"\x00" * (128 * 128 - len(entry))
entries_crc = zlib.crc32(entries) & 0xFFFFFFFF

disk_guid = uuid.UUID(int=random.getrandbits(128)).bytes_le

def header(this_lba, other_lba, entries_lba):
    hdr = struct.pack(
        "<8sIIIIQQQQ16sQIII",
        b"EFI PART",      # signature
        0x00010000,       # revision
        92,               # header size
        0,                # crc32 (placeholdr)
        0,                # reserved
        this_lba,
        other_lba,
        first_usable,
        last_usable,
        disk_guid,
        entries_lba,
        128,              # number of entries
        128,              # entry size
        entries_crc,
    )
    crc = zlib.crc32(hdr) & 0xFFFFFFFF
    return hdr[:16] + struct.pack("<I", crc) + hdr[20:]

with open(path, "r+b") as f:
    # защитный MBR
    mbr = bytearray(512)
    mbr[446:462] = struct.pack("<B3sB3sII",
                               0x00, b"\x00\x02\x00", 0xEE, b"\xFF\xFF\xFF",
                               1, min(total_lba - 1, 0xFFFFFFFF))
    mbr[510:512] = b"\x55\xAA"
    f.seek(0)
    f.write(mbr)
    # таблица разделов (LBA 2)
    f.seek(2 * SECTOR)
    f.write(entries)
    # основной заголовок (LBA 1)
    f.seek(1 * SECTOR)
    f.write(header(1, total_lba - 1, 2))
    # резервный заголовок (последний LBA) + резервная таблица
    f.seek((total_lba - 33) * SECTOR)
    f.write(entries)
    f.seek((total_lba - 1) * SECTOR)
    f.write(header(total_lba - 1, 1, total_lba - 33))

print(f"GPT записана: {path} ({total_lba} секторов, раздел {part_first}-{part_last})")
