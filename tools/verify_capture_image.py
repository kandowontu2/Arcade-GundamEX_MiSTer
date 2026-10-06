#!/usr/bin/env python3
"""Independent ROM oracle for the populated 24 MiB graphics SDRAM range.

Uses the board's three ROM_LOAD64_WORD lanes directly, not the FPGA loader or
the compact-MRA assembler. No ROM or expanded image is written to disk.
"""
# SPDX-License-Identifier: GPL-3.0-or-later
import argparse
import hashlib
import pathlib
import xml.etree.ElementTree as ET
import zipfile
import zlib


def cross_check_compact(archive: pathlib.Path, direct_crc: int, direct_sha: str) -> None:
    """Cross-check separately implemented compact-stream assembly in memory."""
    from verify_rom_layout import assemble
    compact = assemble(archive)[0x280000:0x1480000]
    expanded = bytearray(0x1800000)
    for lane in range(6):
        expanded[lane::8] = compact[lane::6]
    if zlib.crc32(expanded) != direct_crc or hashlib.sha256(expanded).hexdigest() != direct_sha:
        raise ValueError("Independent board-lane oracle and compact-MRA expansion disagree")

BANKS = (
    ("ka001009.u16", "ka001012.u15", "ka001006.u21"),
    ("ka001010.u18", "ka001013.u17", "ka001007.u22"),
    ("ka001011.u20", "ka001014.u19", "ka001008.u23"),
)


def verify(archive: pathlib.Path, mra: pathlib.Path) -> tuple[int, str]:
    parts = {p.attrib["name"]: int(p.attrib["crc"], 16)
             for p in ET.parse(mra).findall(".//part")}
    crc = 0
    sha = hashlib.sha256()
    with zipfile.ZipFile(archive) as source:
        for names in BANKS:
            physical_bank = bytearray(0x800000)
            for lane, name in enumerate(names):
                data = source.read(name)
                if len(data) != 0x200000 or zlib.crc32(data) != parts[name]:
                    raise ValueError(f"Unsupported or corrupt graphics ROM: {name}")
                physical_bank[2 * lane::8] = data[0::2]
                physical_bank[2 * lane + 1::8] = data[1::2]
            crc = zlib.crc32(physical_bank, crc)
            sha.update(physical_bank)
    return crc, sha.hexdigest()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("archive", type=pathlib.Path)
    parser.add_argument("--mra", type=pathlib.Path,
                        default=pathlib.Path("mra/Mobile Suit Gundam EX Revue.mra"))
    parser.add_argument("--cross-check-compact", action="store_true",
                        help="also compare the separately implemented compact MRA expansion")
    args = parser.parse_args()
    crc, sha = verify(args.archive, args.mra)
    print("Physical graphics bytes: 0x1800000 (24 MiB)")
    print(f"CRC32: {crc:08X}")
    print(f"SHA256: {sha}")
    print("Final unpopulated 8 MiB excluded; fourth lane in each row is zero.")
    if args.cross_check_compact:
        cross_check_compact(args.archive, crc, sha)
        print("PASS independent board lanes and compact-MRA expansion agree.")
