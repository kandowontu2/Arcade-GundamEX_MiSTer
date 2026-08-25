# Mobile Suit Gundam EX Revue MiSTer v1.0.0

This is a native MiSTer FPGA implementation of Banpresto's 1994 *Mobile Suit
Gundam EX Revue* arcade hardware. It loads an unmodified `gundamex.zip`
directly; no ROM conversion script is required.

## Install

1. Extract this archive directly to the root of the MiSTer SD card. The files
   will land in `_Arcade` and `_Arcade/cores`.
2. Put a complete, supported `gundamex.zip` in `games/mame`. ROM data is not
   included with this package.
3. Open **Arcade > Mobile Suit Gundam EX Revue** on MiSTer.

## Highlights

- Native TMP68301/68000-compatible CPU, DX-101/X1-020 graphics, X1-010 sound,
  board RAM, interrupts, inputs, EEPROM, and direct MRA ROM loading.
- Standard MiSTer ROM-transfer overlay with no custom raster/grid screen and
  no Jotego/JTFRAME runtime, branding, or assets.
- Compact graphics loading uses conservative independent SDRAM writes for
  compatibility with plug-in modules and integrated BGA memory.
- Gameplay graphics reads use the standard low-frequency MiSTer CAS-2 SDRAM
  profile, reducing every uncached eight-byte row fetch by one core clock to
  give dense scanlines more rendering headroom.
- CRT horizontal/vertical size and offset adjustments, cabinet-oriented
  vertical modes, 180-degree rotation, and optional CPU turbo modes.
- OSD cheats for infinite credits, time, P1 energy, and P2 energy. All cheats
  default to off.
- Board service/test mode is available from the OSD and the mapped Service
  control. The MRA also exposes the board's Debug, Freeze, Show Targets, and
  Free Play switches.
- Coin Chute A and B retain the original PCB's intentionally different
  coinage-rate tables.

## Validation

The exact FPGA build in this archive passed the complete focused RTL regression
suite, Quartus Prime Lite 17.0 timing analysis, and extended hardware gameplay
testing. Worst setup slack is
`+0.327 ns`, 62.5 MHz core setup slack is `+2.285 ns`, and worst hold slack is
`+0.247 ns`.

## Build identity

- RBF: `GundamEX_20260824c.rbf`
- RBF SHA-256:
  `913091ee42410a0232395a473e039e65d3c5ec01ac343aee258d27322032635b`
- Supported ROM archive name: `gundamex.zip`

## Credits and licensing

FPGA implementation and MiSTer integration: OpenAI Codex. Hardware testing,
project direction, and validation: kandowontu. The original game and hardware
are by Banpresto and their original developers and engineers. This independent
preservation project is not affiliated with or endorsed by Banpresto.

See `CREDITS.md` and `LICENSE` in this archive for component authorship,
hardware-reference acknowledgements, and licensing details. ROM files are not
included.
