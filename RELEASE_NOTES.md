# Mobile Suit Gundam EX Revue MiSTer v1.0.4

This is a native MiSTer FPGA implementation of Banpresto's 1994 *Mobile Suit
Gundam EX Revue* arcade hardware. It loads an unmodified `gundamex.zip`
directly; no ROM conversion script is required.

## Install

1. Extract the release ZIP directly to the root of the MiSTer SD card. The
   files will land in `_Arcade` and `_Arcade/cores`.
2. Put a complete, supported `gundamex.zip` in `games/mame`. ROM data is not
   included with this package.
3. Open **Arcade > Mobile Suit Gundam EX Revue** on MiSTer.

## v1.0.4 changes

- Fixes the black screen caused by an extra byte at the end of fast DDR ROM
  loading. The adapter now captures the byte count before `hps_io` advances
  its address on the stop command.
- Adds tests using the actual bundled HPS interface, including aligned,
  partial-word, repeated, and empty staged transfers, plus compatibility with
  unchanged stop addresses and ordinary byte streaming.
- Keeps the same universal build and undated filenames; no per-device build
  or ROM conversion script is needed.

## Included v1.0.3 cheat support

- Cheat definitions now live in the MRA and appear through the standard MiSTer
  **Cheats** menu. Infinite credits/time and P1/P2 infinite energy remain
  independently selectable.
- Uses the Irem M92 16-byte cheat protocol with a big-endian 68000 adaptation,
  including original Martin Donlon/Kitrinx credits and license notice.
- Removing a selection immediately removes its read override. Selected codes
  survive warm reset and clear on new-ROM loading; stale status-bit selections
  from older builds are ignored.
- Regression tests consume the release MRA's actual code packets and check
  selection replacement/clearing, byte lanes, flags and transfer isolation.

Install both the new RBF and MRA. Enable cheats after the game boots; disable
them before running the game's startup RAM test. On-device confirmation of
the individual cheat effects is still pending.

## Included v1.0.2 loading and layout work

- Uses the MiSTer-devel arcade layout, including tracked artifacts in
  `releases/` and an SD-card-root ZIP containing `_Arcade` and
  `_Arcade/cores`.
- Standardizes the public core filename and MRA target on the undated
  `Arcade-GundamEX.rbf` name.
- Replaces the internal tester version string with the public `1.0.2` version.
- Adds fast DDR-staged ROM loading on current MiSTer Main while retaining an
  automatic ordinary-stream fallback for older installations.

## Included v1.0.1 compatibility work

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

The exact FPGA build in this archive passed all 17 focused RTL regression
tests, ROM-layout verification, Quartus Prime Lite 17.0 compilation, and
TimeQuest timing analysis with no timing violations. Worst setup slack is
`+0.510 ns`, 62.5 MHz core setup slack is `+2.473 ns`, and worst hold slack is
`+0.240 ns`.

The matching RBF and MRA were installed and checksum-verified on a DE10-Nano.
Fast DDR loading reached attract-mode gameplay, confirmed by a live MiSTer
capture, including a repeat launch, and kandowontu confirmed that it is
working on the device. The same core also booted using ordinary streaming
while isolating the loader fault. This is not a complete playthrough or a
test of all individual cheat effects; SuperStation One retesting remains
pending.

## Build identity

- RBF: `Arcade-GundamEX.rbf`
- RBF SHA-256: recorded in the accompanying `SHA256SUMS.txt`
- Supported ROM archive name: `gundamex.zip`

## Credits and licensing

FPGA implementation and MiSTer integration: OpenAI Codex. Hardware testing,
project direction, and validation: kandowontu. The original game and hardware
are by Banpresto and their original developers and engineers. This independent
preservation project is not affiliated with or endorsed by Banpresto.

See `CREDITS.md` and `LICENSE` in the source repository for component authorship,
hardware-reference acknowledgements, and licensing details. ROM files are not
included.
