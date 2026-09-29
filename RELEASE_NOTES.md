# Mobile Suit Gundam EX Revue MiSTer v1.0.1

This is a native MiSTer FPGA implementation of Banpresto's 1994 *Mobile Suit
Gundam EX Revue* arcade hardware. It loads an unmodified `gundamex.zip`
directly; no ROM conversion script is required.

## Install

1. Extract the release ZIP directly to the root of the MiSTer SD card. The
   files will land in `_Arcade` and `_Arcade/cores`.
2. Put a complete, supported `gundamex.zip` in `games/mame`. ROM data is not
   included with this package.
3. Open **Arcade > Mobile Suit Gundam EX Revue** on MiSTer.

## v1.0.1 changes

- Uses conservative CAS-3 graphics reads and bounded refresh priority for
  compatibility with standard MiSTer SDRAM modules and SuperStation One's
  integrated BGA SDRAM.
- Applies deterministic, selective treatment to long one-pixel A/B dither
  runs, preventing the button-explanation artwork from becoming wide bands on
  SuperStation One HDMI without filtering ordinary sprite detail.
- Prevents saved status from older test builds from restoring the incompatible
  raw video path.
- Retains analog controls, CRT geometry, rotation, turbo modes, cheats, service
  mode, stereo sound, and the original Coin Chute A/B DIP tables.

## Validation

The exact FPGA build in this archive passed the complete focused RTL regression
suite, ROM-layout verification, Quartus Prime Lite 17.0 compilation, and
TimeQuest timing analysis with no timing violations. Worst setup slack is
`+0.566 ns`, 62.5 MHz core setup slack is `+2.598 ns`, and worst hold slack is
`+0.150 ns`.

## Build identity

- RBF: `GundamEX_20260830b.rbf`
- RBF SHA-256:
  `73cecce929ab4734108debac6b75c10c554c75ac8b36ead036a9b941cb96014f`
- Supported ROM archive name: `gundamex.zip`

## Credits and licensing

FPGA implementation and MiSTer integration: OpenAI Codex. Hardware testing,
project direction, and validation: kandowontu2. The original game and hardware
are by Banpresto and their original developers and engineers. This independent
preservation project is not affiliated with or endorsed by Banpresto.

See `CREDITS.md` and `LICENSE` in this archive for component authorship,
hardware-reference acknowledgements, and licensing details. ROM files are not
included.
