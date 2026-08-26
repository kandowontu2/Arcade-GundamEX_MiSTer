#!/usr/bin/env python3
"""Build and verify the exact byte stream described by the Gundam EX MRA."""

from __future__ import annotations

import argparse
import hashlib
import pathlib
import zipfile


PROGRAM_PAIRS = (
    ("ka002002.u2", "ka002004.u3"),
    ("ka002001.u4", "ka002003.u5"),
)
EXTRA_PROGRAM = "ka001005.u77"
GRAPHICS_BANKS = (
    ("ka001009.u16", "ka001012.u15", "ka001006.u21"),
    ("ka001010.u18", "ka001013.u17", "ka001007.u22"),
    ("ka001011.u20", "ka001014.u19", "ka001008.u23"),
)
SAMPLES = "ka001015.u28"
EEPROM = "eeprom.bin"


def interleave_program(even: bytes, odd: bytes) -> bytes:
    if len(even) != len(odd):
        raise ValueError("program ROM pair has unequal lengths")
    output = bytearray(len(even) * 2)
    output[0::2] = even
    output[1::2] = odd
    return bytes(output)


def interleave_graphics(lanes: tuple[bytes, bytes, bytes]) -> bytes:
    if len({len(lane) for lane in lanes}) != 1:
        raise ValueError("graphics ROM lanes have unequal lengths")
    output = bytearray((len(lanes[0]) // 2) * 6)
    for lane_number, lane in enumerate(lanes):
        # MAME ROM_LOAD64_WORD: preserve each 16-bit ROM word and compact the
        # board's three populated lanes. The FPGA loader inserts lane 4 zeros.
        output[lane_number * 2 :: 6] = lane[0::2]
        output[lane_number * 2 + 1 :: 6] = lane[1::2]
    return bytes(output)


def word_swap(data: bytes) -> bytes:
    if len(data) & 1:
        raise ValueError("word-swapped ROM has an odd byte count")
    output = bytearray(len(data))
    output[0::2] = data[1::2]
    output[1::2] = data[0::2]
    return bytes(output)


def assemble(archive: pathlib.Path) -> bytes:
    with zipfile.ZipFile(archive) as rom_zip:
        read = rom_zip.read
        program = b"".join(interleave_program(read(a), read(b)) for a, b in PROGRAM_PAIRS)
        program += word_swap(read(EXTRA_PROGRAM))
        graphics = b"".join(
            interleave_graphics(tuple(read(name) for name in bank))
            for bank in GRAPHICS_BANKS
        )
        image = program + graphics + read(SAMPLES) + read(EEPROM)

    expected_size = 0x1680080
    if len(image) != expected_size:
        raise ValueError(f"assembled size is 0x{len(image):x}, expected 0x{expected_size:x}")
    return image


def source_parts_md5(archive: pathlib.Path) -> str:
    """Hash raw source parts in manifest order for archive diagnostics only."""
    digest = hashlib.md5()
    with zipfile.ZipFile(archive) as rom_zip:
        read = rom_zip.read
        for pair in PROGRAM_PAIRS:
            for name in pair:
                digest.update(read(name))
        digest.update(read(EXTRA_PROGRAM))
        for bank in GRAPHICS_BANKS:
            for name in bank:
                digest.update(read(name))
        digest.update(read(SAMPLES))
        digest.update(read(EEPROM))
    return digest.hexdigest()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("archive", type=pathlib.Path)
    parser.add_argument("--write", type=pathlib.Path, help="optionally save the assembled stream")
    args = parser.parse_args()
    image = assemble(args.archive)
    if args.write:
        args.write.write_bytes(image)
    print(f"size=0x{len(image):x}")
    # MiSTer validates the final ROM image after applying MRA interleaving,
    # swaps, repeats, and inline data. This is the value for <rom md5="...">.
    print(f"mra_md5={hashlib.md5(image).hexdigest()}")
    print(f"source_parts_md5={source_parts_md5(args.archive)}")
    print(f"sha256={hashlib.sha256(image).hexdigest()}")


if __name__ == "__main__":
    main()
