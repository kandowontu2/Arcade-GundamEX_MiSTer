# Changelog

## 1.0.4 - 2026-09-30

- Fixed a black screen after direct-DDR ROM staging. The bundled MiSTer
  interface increments its address on download stop; the adapter now retains
  the active-transfer byte count instead of replaying one extra byte and
  failing the game-specific ROM-layout check.
- Added regression coverage through the actual bundled `hps_io` file-transfer
  protocol, including aligned, partial-word, repeated, and empty transfers.
- Retained compatibility with ordinary byte streaming and frameworks that
  leave the stop address unchanged, plus the MRA-defined cheats from v1.0.3.

## 1.0.3 - 2026-09-29

- Restored the author/contributor credit to kandowontu while retaining the
  current repository URLs under kandowontu2.
- Moved the four cheat definitions into the MRA's standard `<cheats>` block
  and replaced the fixed status-bit controls with MiSTer's `C,Cheats;` menu.
- Adapted Martin Donlon/Kitrinx's Irem M92 cheat engine for big-endian 68000
  work-RAM reads and standard index-255 selection downloads.
- Added complete-set replacement, empty-selection clearing, warm-reset
  retention, new-ROM clearing, packet validation, and an eight-code limit.
- Added regression coverage using the actual MRA code bytes, including lane
  order, compare/OR/AND operations, malformed transfers and code-table bounds.

## 1.0.2 - 2026-09-29

- Adopted the MiSTer-devel arcade repository layout with tracked distributable
  files in `releases/`.
- Standardized the release core and MRA target on the undated
  `Arcade-GundamEX.rbf` filename and packaged the install ZIP from the MiSTer
  SD-card root.
- Replaced the internal tester version string with the public `1.0.2` version.
- Added MiSTer Main fast DDR staging with automatic legacy streaming fallback,
  based on Martin Donlon's IGS PGM/F2 ROM-loader adaptor.

## 1.0.1 - 2026-09-29

- Added deterministic digital dither handling for the button instruction
  screen. The universal output now always requires a seven-pixel A/B run before
  averaging, avoiding ordinary sprite art while preventing HDMI scaler
  aliasing. Removing the selector also prevents saved status from an older test
  build from silently restoring raw output.
- Restored conservative CAS-3 graphics reads and bounded refresh priority for
  compatibility with both standard MiSTer SDRAM modules and SuperStation One's
  integrated BGA SDRAM.

## 1.0.0 - 2026-08-24

- Changed the 62.5 MHz graphics SDRAM read path from CAS 3 to the standard
  low-frequency MiSTer CAS-2 profile, saving one controller clock on every
  cache miss, and safely reduced refresh interference during dense rows.
- Clarified that the original PCB's Coin Chute A and B DIP tables deliberately
  expose different credit-rate choices.
- Replaced the loader's back-to-back SDRAM writes with four independent
  ACTIVE/WRITE/auto-precharge cycles for integrated-BGA compatibility.
- Reworked graphics SDRAM into an open-page DMA controller, cutting same-page
  eight-byte row latency from 19 to 11 core clocks.
- Expanded the completed-scanline reservoir to 21 lines and preserved it while
  the DX-101 display-list buffer temporarily owns sprite RAM.
- Added optional CRT H/V size and H/V offset controls with PVM and native-sync
  cabinet vertical modes.
- Added resource-light 180-degree rotation inside DX-101 scanout.
- Clarified the existing native, compensated, and overclocked CPU-rate choices
  as CPU speed/turbo controls; video, audio, and TMP68301 timing remain native.
- Added regression coverage for renderer pause retention, 180-degree target
  mapping, and cold/same-page/cross-page SDRAM DMA latency.

## 0.1.0 - 2026-08-22

- Started a standalone MiSTer core for *Mobile Suit Gundam EX Revue* from the
  proven Seta P0-113A / DX-101 implementation.
- Added the game's 16.265235 MHz CPU timing and complete program, RAM, input,
  sound, video, bank-register, and TMP68301 address map.
- Added both players' fourth action button and the board's English/Japanese
  language jumper.
- Added TMP68301 parallel GPIO and a synthesizable 93C46 x16 EEPROM, including
  MRA factory-image loading and serial read/write/erase commands.
- Added direct loading from an unmodified `gundamex.zip` without a helper
  script. The compact stream reconstructs unpopulated video-ROM lanes in FPGA
  memory and avoids transferring the empty final graphics bank.
- Expanded program and sample addressing for the extra 512 KiB program ROM and
  2 MiB X1-010 sample ROM.
- Changed the native raster to 512 x 256 total with 384 x 224 visible pixels.
- Added ROM-layout, compact-loader, and EEPROM tests; updated the full
  regression suite for Gundam EX Revue's memory and raster geometry.
- Completed a clean Quartus Prime Lite 17.0 build with positive setup and hold
  slack.
