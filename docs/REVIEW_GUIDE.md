# Maintainer review guide - v1.0.7

This is an independent core prepared for review, not an accepted MiSTer-devel
submission. No PR, transfer or updater-database change has been submitted.
Contributor credit remains **kandowontu**; **kandowontu2** is the hosting account.

## Entry points

- `GundamEX.qpf`, `GundamEX.qsf`, `files.qip`: Quartus project and source list.
  `sys/sys_top.v` is the framework top; `GundamEX.sv` implements `emu`.
- `rtl/gd_core.sv`: CPU, memory, video, audio and EEPROM integration.
- `rtl/gd_crt_geometry.sv`: normalized active-high sync through vertical sizing
  and horizontal/vertical positioning. Native raster counters stay unchanged.
- `mra/Mobile Suit Gundam EX Revue.mra`: ROM metadata, DIP switches, controls,
  cheats and NVRAM. The `releases/` copy must remain byte-identical.
- `CREDITS.md`, `UPSTREAM.md`, `LICENSE`: authors, pinned dependencies,
  behavioral references and retained per-component licensing notices.

## Changes since v1.0.6

Review `git diff v1.0.6..v1.0.7 -- rtl GundamEX.sv files.qip mra sim tools`.

1. PVM positioning: `crt_vsize` exports its actual latched output frame total;
   `crt_adjust` uses it for negative V Offset wrap. The +3 size / -1 offset
   case is 247 lines and advances sync by one line, not an eight-line delay.
2. EEPROM: `gd_eeprom_nvram.sv` stages index-4 downloads and restores after
   factory replay while holding runtime reset. `gd_93c46.sv` exposes a frozen
   128-byte upload snapshot and reports all write/erase operations. Top-level
   HPS wiring supplies Main's standard save-request path, without modifying
   the vendored framework. Incomplete uploads retain the dirty request.
3. Controls: both MRAs and fallback OSD labels use Weak Attack, Medium Attack,
   Strong Attack and Throw. ROM CRCs, default A/B/X/Y order, DIP tables and
   cheats are unchanged.

## Reproduce the checks

Run from the repository root with Python 3, Icarus Verilog 11+ and Quartus
Prime Lite 17.0 installed. Change the Quartus path to the local installation.

```powershell
python tools/test_verify_release.py
python tools/verify_release.py --version 1.0.7
./sim/run_unit_tests.ps1 -QuartusDirectory "C:/intelFPGA_lite/17.0/quartus"
./scripts/build_release.ps1 -Version 1.0.7 -QuartusDirectory "C:/intelFPGA_lite/17.0/quartus"
```

The build helper repeats regressions, compiles, audits fitted falling-edge
SDRAM capture and checks matching compressed RBF exports. Packaging commands
and the optional legally obtained ROM checks are in the root README.
Generated reports and vendor simulation libraries are not redistributed.

## Evidence and remaining checks

`RELEASE_VALIDATION.md` records the exact bitstream hash, resources, all 33
nonnegative internal timing checks, 25 RTL runs, 16 Python tests and fitted
SDRAM audit. `PVM_EEPROM_VALIDATION.md` details the new protocol/offset tests.
The unchanged release RBF also passed actual CPU EEPROM writes, automatic
OSD saves and all-128-byte readback after two complete Menu/relaunch cycles
on the user's MiSTer. Temporary test software and saves are not distributed.

Physical analog output and SuperStation One still need independent checks
of this exact fit. The inherited SDC does not constrain external SDRAM board
I/O; internal timing closure is not an electrical compatibility guarantee.
The framework remains pinned rather than silently refreshed. RAM usage is
550/553 blocks. These limits and eventual ownership/updater decisions remain
explicit in `UPSTREAM_READINESS.md`.

Repository artifacts use one dated `Arcade-GundamEX_20261119.rbf` and an
undated MRA in `releases/`. The install ZIP follows Distribution's naming:
`_Arcade/cores/GundamEX_20261119.rbf` and `_Arcade/Mobile Suit Gundam EX Revue.mra`.
The MRA target is `GundamEX`. Source ZIPs contain required source, tests,
documentation and IP notices, not ROMs, captures or private build databases.
