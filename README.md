# Mobile Suit Gundam EX Revue for MiSTer

An open-source native FPGA implementation of Banpresto's 1994 arcade game
*Mobile Suit Gundam EX Revue* for the MiSTer DE10-Nano platform.

The board belongs to the same Seta P0-113A family as *Guardians / Denjin Makai
II*, but it is not a ROM swap. This core adds Gundam EX Revue's CPU clock,
memory map, fourth action button, EEPROM interface, video geometry, larger
sample ROM, and sparse graphics-ROM arrangement.

The included MRA loads an original `gundamex.zip` directly. No Linux helper,
preprocessing script, expanded ROM image, or renamed ROM files are required.
No copyrighted game ROMs are included in this project.

## Status

Version 1.0.0 boots and runs on a DE10-Nano with video, stereo audio, both
players, service functions, and direct MRA loading. The release build uses a
21-line DX-101 render reservoir plus open-page graphics SDRAM transfers to
prevent the repeated/corrupt scanlines previously seen in battle scenes. The
complete focused RTL regression suite passes and Quartus Prime Lite 17.0 closes
timing.

The core uses the standard MiSTer framework directly. It contains no Jotego or
JTFRAME code, runtime, branding, or background assets. During ROM transfer the
core draws no custom loading picture; MiSTer's normal transfer overlay is shown
over a neutral black video background.

## Install

1. Copy `GundamEX_20260824c.rbf` to `/media/fat/_Arcade/cores/`.
2. Copy `Mobile Suit Gundam EX Revue.mra` to `/media/fat/_Arcade/`.
3. Put a legally obtained, unmodified `gundamex.zip` in
   `/media/fat/games/mame/`.
4. Launch **Mobile Suit Gundam EX Revue** from MiSTer's Arcade menu.

The MRA verifies the source archive by filename and CRC and assembles the
memory image while MiSTer loads the core.

## Controls and service functions

| Game control | MiSTer default |
|---|---|
| Attack 1 | A |
| Attack 2 | B |
| Attack 3 | X |
| Attack 4 | Y |
| Start | Start |
| Coin | Select |
| Service | R |

Player 1 and Player 2 are supported. Movement accepts the mapped D-pad or the
left analog stick with a signed dead zone and digital-input priority.

The OSD exposes the game's original DIP switches, including service mode,
debug mode, freeze, target display, and free play. **Test / service mode** is a
second convenient override that directly asserts the board's active-low test
switch. The P0-113A English/Japanese language jumper is also available in the
Hardware submenu.

The two coinage menus represent the PCB's physical Coin Chute A and Coin Chute
B DIP tables. Their choices are intentionally different: chute B includes the
original mixed-credit 2C/3C, 2C/5C, and 3C/5C rates.

The **Cheats** submenu provides independently selectable infinite credits,
infinite time, P1 infinite energy, and P2 infinite energy. These are native HDL
work-RAM clamps and do not require MiSTer scripts or external cheat files.

The **Scandoubler Fx** setting leaves native 15-kHz analog RGB active when set
to **None**. MiSTer's `forced_scandoubler=1` setting and the HQ2x/CRT choices
produce scandoubled output where required.

**Dither blend** is enabled by default. It averages only confirmed one-pixel
A/B/A checkerboards, preventing the instruction artwork's intentional CRT
dither from aliasing into wide vertical bands under non-integer HDMI scaling.
Set it to **Off** for completely raw source pixels, including direct analogue
setups where the display itself performs the blend.

The **CRT Geometry** submenu provides signed H Size, H Offset, V Size, and V
Offset controls. Leave the master switch **Off** for the untouched native
stream. **PVM** V-size mode retimes line cadence while keeping every source
line unique; **Cabinet** mode keeps native sync timing and simulates the tube's
vertical geometry. Because this is a core-side stage, adjusted geometry is
visible on HDMI as well as analog RGB.

**Rotation** supports normal and 180-degree output without using a DDR frame
buffer. **CPU speed** offers the native 16.27 MHz board rate, 20.33 and 30.00
MHz overclocks, and the default 24.40 MHz compensated mode. Video, audio, and
TMP68301 timer rates stay native in every CPU mode.

## Implemented hardware

- Toshiba TMP68301-compatible 68HC000 subsystem at 16.265235 MHz
- TMP68301 interrupt controller, timers, and parallel GPIO
- 93C46 x16 serial EEPROM with factory-image loading and write persistence
  for the current core session
- NEC DX-101 / Allumer X1-020-compatible sprite and tile renderer
- Seta X1-010-compatible 16-voice PCM audio and 2 MiB sample banking
- 384 x 224 visible image on a 512 x 256 raster
- Direct compact MRA assembly of 2.5 MiB program, 18 MiB populated graphics,
  2 MiB samples, and the 128-byte EEPROM image
- Compact four-word graphics loading with conservative independent SDRAM write
  cycles for compatibility with plug-in modules and integrated BGA memory
- Transparent reconstruction of the graphics bus's missing fourth 16-bit lane
  and wholly unpopulated final 8 MiB bank
- MiSTer SDRAM/DDR3, HDMI, analog video, audio, controller, DIP, reset, and OSD
  integration

See [`docs/HARDWARE.md`](docs/HARDWARE.md) for the board map and implementation
notes.

## Build

The project targets the Cyclone V `5CSEBA6U23I7` and Quartus Prime Lite 17.0:

```powershell
quartus_sh --flow compile GundamEX
```

The v1.0.0 release build uses 27,193 ALMs, 551 RAM blocks, and 45 DSP
blocks. It closes the 62.5 MHz core domain with +2.285 ns setup slack; the
worst setup slack anywhere in the design is +0.327 ns and worst hold slack is
+0.247 ns.

## Tests

The focused RTL tests use Icarus Verilog 11 or newer:

```powershell
./sim/run_unit_tests.ps1
```

The suite covers analog conversion, conditional HDMI dither blending, DDR and
SDRAM transfers, compact ROM
loading with missing-lane expansion, the 93C46 command interface, raster
timing, raster interrupts, rowscroll replay, graphics arbitration, DX-101
rendering, display-list buffering, and TMP68301 behavior. The ROM layout can
also be checked against a local archive:

```powershell
python ./tools/verify_rom_layout.py "$HOME/Downloads/gundamex.zip"
```

## Source and licensing

Core RTL is distributed under GPL-3.0-or-later. Bundled upstream components
retain their original notices and terms. See [`CREDITS.md`](CREDITS.md) and
[`LICENSE`](LICENSE). ROM files are neither included nor licensed by this
project.
