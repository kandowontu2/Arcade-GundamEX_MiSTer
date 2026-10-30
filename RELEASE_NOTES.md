# Mobile Suit Gundam EX Revue MiSTer v1.0.6

This release fixes CRT vertical-sizing sync polarity, corrects MRA lookup and
rotation metadata, and shares sprite geometry calculations without changing
the rendering pipeline stages. There is one shared build, with no
board-dependent memory-phase setting.

## Install

1. Extract `Arcade-GundamEX_MiSTer_v1.0.6.zip` to the MiSTer SD-card root.
   It installs `_Arcade/Mobile Suit Gundam EX Revue.mra` and
   `_Arcade/cores/GundamEX_20261030.rbf`.
2. Keep your supported, legally obtained `gundamex.zip` in `games/mame/`.
3. Launch **Arcade > Mobile Suit Gundam EX Revue**.

Use the ZIP's installed filename, which matches MiSTer Distribution. The
repository and standalone asset retain the standard
`Arcade-GundamEX_20261030.rbf` name; the payload is identical. If installing
that standalone asset manually, rename it to `GundamEX_20261030.rbf` so an
older unprefixed test copy cannot take precedence during MRA lookup.
Other Gundam games are separate cores and should not be removed.

## Changes

- Normalize native active-low H/V sync before both CRT processing stages.
  Bypass also supplies positive sync to MiSTer's mixer, without changing its
  pixels, blanking or pixel enable.
- Correct both MRAs to target `GundamEX` and declare horizontal rotation.
  Original ROM CRCs, DIP tables, buttons, cheats and contributor credits remain.
- Share sprite source-line, signed/wrapped vertical bounds, height and width
  calculations between the visibility scan and drawing stage; preserve stages.
- Add root `clean.bat` using the standard template cleanup commands, anchored
  to its own project directory.
- Add native-raster PVM/Cabinet sizing tests, 8,192 sprite-equivalence vectors,
  MRA lookup tests and isolated Windows cleanup tests.
- Preserve fixed falling-edge graphics SDRAM capture, fast/legacy loading,
  service menus, analog inputs, audio and 180-degree rotation.

## Validation

The new production fit passed all 33 internal timing checks and the fitted
falling-edge SDRAM capture audit. All 23 RTL regression runs and 14 packaging,
metadata and cleanup tests passed, including 8,192 sprite-equivalence vectors.
The exact release RBF booted on the user's MiSTer with visible attract-mode
gameplay, service-screen access, 180-degree rotation and all six PVM/Cabinet
zero/positive/negative V Size configurations. Original settings were restored.
Full results and test scope are in `docs/RELEASE_VALIDATION.md`.

The inherited SDC leaves external SDRAM board I/O timing unconstrained.
Internal closure cannot certify electrical margin on every board. Screenshot
checks cannot certify the electrical analog output or every gameplay frame.
This exact refit still needs independent SuperStation One/analog confirmation.
See `docs/RELEASE_VALIDATION.md` for exact-build evidence and limitations.

## Known limits and credits

EEPROM changes survive reset but are replaced on relaunch; persistent NVRAM
and a full framework refresh are not included in this focused update.
Cheats should be disabled during startup RAM checks. Native 15-kHz analog
output normally uses **Scandoubler Fx: None**, with CRT Geometry initially Off.

Credit remains **kandowontu**; **kandowontu2** is the hosting account only.
Full third-party, FPGA IP, hardware-reference and tester credits are included
in `CREDITS.md` and `UPSTREAM.md`. No game ROMs or private diagnostics are in
the release. No PR has been submitted to MiSTer-devel.
