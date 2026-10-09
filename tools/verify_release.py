#!/usr/bin/env python3
"""Check dated RBF naming, MRA identity, source hygiene and ZIP layout."""
# SPDX-License-Identifier: GPL-3.0-or-later
import argparse
import datetime
import hashlib
import pathlib
import re
import subprocess
import xml.etree.ElementTree as ET
import zipfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
CORE = "Arcade-GundamEX"
MRA = "Mobile Suit Gundam EX Revue.mra"
DOCS = {"README.txt": "RELEASE_NOTES.md", "CREDITS.md": "CREDITS.md",
        "LICENSE": "LICENSE", "SHA256SUMS.txt": "SHA256SUMS.txt"}


def release_rbf_name(releases: pathlib.Path) -> str:
    rbfs = list(releases.glob("*.rbf"))
    assert len(rbfs) == 1, "Keep exactly one current release RBF"
    name = rbfs[0].name
    match = re.fullmatch(rf"{re.escape(CORE)}_(\d{{8}})\.rbf", name)
    assert match, "RBF must use Arcade-GundamEX_YYYYMMDD.rbf for updater discovery"
    datetime.datetime.strptime(match[1], "%Y%m%d")
    return name


def verify(version: str, archive: pathlib.Path | None) -> None:
    rbf = release_rbf_name(ROOT / "releases")
    deploy = {f"_Arcade/cores/{rbf}": f"releases/{rbf}",
              f"_Arcade/{MRA}": f"releases/{MRA}"}
    assert {p.name for p in (ROOT / "releases").iterdir()} == {rbf, MRA}, "Unexpected release files"
    data = (ROOT / "releases" / MRA).read_bytes()
    assert data == (ROOT / "mra" / MRA).read_bytes(), "MRA copies differ"
    mra = ET.fromstring(data)
    assert mra.findtext("rbf") == CORE, "MRA target must remain undated"
    assert mra.findtext("name") == "Mobile Suit Gundam EX Revue", "Private MRA name"
    assert mra.find("about").attrib["author"] == "OpenAI Codex and kandowontu", "Author credit"
    rom = mra.find("rom")
    assert rom.attrib == {"index": "0", "address": "0x30000000", "zip": "gundamex.zip", "md5": "none"}, "ROM loading changed"
    parts = rom.findall(".//part")
    assert len(parts) == 16 and all(re.fullmatch(r"[0-9a-f]{8}", p.attrib["crc"]) for p in parts), "Source ROM CRCs"
    cheats = mra.find("cheats")
    assert cheats.attrib == {"size": "16", "max": "8"} and len(cheats) == 4, "Cheat format"
    assert all(re.fullmatch(r"[0-9A-Fa-f]{32}", "".join(c.itertext()).replace(" ", "").strip()) for c in cheats), "Cheat packets"
    top = (ROOT / "GundamEX.sv").read_text()
    assert f'"v,{version};"' in top and '"Gundam EX Revue;;"' in top, "OSD identity"
    assert not any(x in top for x in ("Capture Test", "GUNDAM_SDRAM_CAPTURE_TEST")), "Private test in top"
    tracked = subprocess.check_output(["git", "-C", str(ROOT), "ls-files"], text=True).splitlines()
    for name in tracked:
        assert not name.startswith(("testing/", "diagnostics/", "db/", "output_files/", "roms/", "captures/")), name
        assert not name.endswith((".zip", ".sof", ".out", ".log")), name
        if name.startswith(("rtl/", "sys/")) or name in ("GundamEX.sv", "files.qip", "GundamEX.qsf"):
            assert "GUNDAM_SDRAM_CAPTURE_TEST" not in (ROOT / name).read_text(errors="replace"), name
    assert 1000000 < (ROOT / "releases" / rbf).stat().st_size < 7000000, "Unexpected compressed bitstream size"
    sums = {}
    for line in (ROOT / "SHA256SUMS.txt").read_text().splitlines():
        digest, name = line.split("  ", 1)
        sums[name] = digest
    assert set(sums) == set(deploy), "Checksum paths"
    for name, local in deploy.items():
        assert hashlib.sha256((ROOT / local).read_bytes()).hexdigest() == sums[name], name
    if archive:
        with zipfile.ZipFile(archive) as source:
            expected = deploy | DOCS
            assert set(source.namelist()) == set(expected), "ZIP must be rooted at _Arcade, without stale files"
            assert source.testzip() is None, "Corrupt ZIP"
            for name, local in expected.items():
                assert source.read(name) == (ROOT / local).read_bytes(), f"ZIP payload mismatch: {name}"
    print(f"PASS v{version} dated RBF ({rbf}), undated MRA target, credits, ROM metadata, source hygiene, checksums and install layout")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--version", required=True)
    parser.add_argument("--zip", type=pathlib.Path)
    args = parser.parse_args()
    verify(args.version, args.zip)
