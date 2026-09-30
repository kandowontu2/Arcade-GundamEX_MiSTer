# Mobile Suit Gundam EX Revue hardware target

The 1994 Banpresto board is part of Seta's P0-113A family. It is closely
related to the later *Guardians / Denjin Makai II* hardware but differs in its
clock, map, inputs, nonvolatile storage, ROM population, and display geometry.

| Function | Device / mapping |
|---|---|
| Main CPU | TMP68301 / 68HC000, 32.53047 MHz / 2 |
| Video | NEC DX-101 / Allumer X1-020 |
| Sound | Seta X1-010, 32.53047 MHz / 2 |
| EEPROM | 93C46, 64 x 16, through TMP68301 parallel GPIO |
| CRT raster | 512 x 256 total; 384 x 224 visible |
| Main program ROM | `000000-1fffff`, 2 MiB |
| Work RAM | `200000-20ffff`, 64 KiB |
| Extra program ROM | `500000-57ffff`, 512 KiB |
| DIP switches | `600000-600003` |
| Players/system | `700000-70000b` |
| Watchdog | `70000c` |
| Coin control | `800000` |
| X1-010 registers | `b00000-b03fff` |
| Sprite RAM | `c00000-c3ffff`, 256 KiB |
| Palette RAM | `c40000-c4ffff`, xRGB555 |
| Extra palette window | `c50000-c5ffff` |
| Video registers | `c60000-c6003f` |
| Sample bank registers | `e00010-e0001f` |
| TMP68301 registers | `fffc00-ffffff` |

The fourth action button is read through the extra player ports at `700008`
and `70000a`. The language jumper is bit 5 of the system port. EEPROM CS, SK,
and DI are driven by TMP68301 parallel-port bits 2, 1, and 0; DO returns on bit
3.

## MiSTer memory plan

The physical graphics address bus spans 32 MiB, but only three 16-bit lanes in
each of its first three 8 MiB banks are populated. The fourth lane and final
8 MiB bank read as zero. The MRA therefore transfers a compact 18 MiB graphics
stream. The FPGA loader expands each 48-bit group to 64 bits while writing
MiSTer's SDRAM, and the graphics arbiter supplies zero for the untouched last
bank. The compact request is executed as four independent SDRAM write cycles;
this conservative sequence works with both plug-in SDRAM modules and integrated
BGA memory.

Program ROM and the 2 MiB X1-010 sample image reside in MiSTer's DDR3 behind
independent caches. The extra CPU ROM is stored compactly immediately after
the 2 MiB main program and translated from CPU address `500000`. The writable
extra-palette window is located separately in DDR3. Sprite, palette, and work
RAM use on-chip memory.

The complete MRA stream is `0x1680080` bytes:

| Compact stream range | Contents |
|---|---|
| `0000000-027ffff` | 2 MiB main plus 512 KiB extra program |
| `0280000-147ffff` | 18 MiB populated graphics data |
| `1480000-167ffff` | 2 MiB X1-010 samples |
| `1680000-168007f` | 128-byte factory EEPROM image |

No Linux-side helper or ROM preprocessing is required.

On current MiSTer Main versions, the MRA stages this compact stream directly
at physical DDR address `0x30000000`. An FPGA-side adaptor then replays the
bytes through the same game-specific unpacker: program and sample data settle
in a separate runtime region beginning at `0x32000000`, graphics expand into
SDRAM, and the factory EEPROM initializes on chip. Keeping the ranges separate
prevents staged graphics bytes from contaminating work RAM. If Main supplies
ordinary `ioctl_wr` byte writes instead, the adaptor transparently passes them
through, so one RBF/MRA pair supports both loading paths.

## Service and cheat controls

The MRA exposes the board's original active-low Service Mode, Debug Mode,
Freeze, Show Targets, and Free Play DIP switches. The core OSD also provides a
service/test override for SW1:8 and maps the momentary service input to the
controller's Service button.

Coin Chute A and Coin Chute B intentionally have different rate choices. The
original Gundam EX Revue PCB assigns ordinary whole-credit ratios to chute A
and several mixed ratios (including 2C/3C, 2C/5C, and 3C/5C) to chute B.

The MRA defines cheats for the game's documented work-RAM values for credits
(`2034ef`), round time (`2035a2-2035a3`), P1 energy (`204569`), and P2 energy
(`2045bf`). The standard `C,Cheats;` menu downloads selected codes through
`ioctl_index=255`. Each 16-byte code contains four big-endian 32-bit fields:
Flags, CPU byte Address, Compare, Data. `<cheats size="16" max="8">` tells
MiSTer Main the engine's limit. A new transfer replaces the complete selected
set; Main's two-byte empty transfer clears it. Partial/reordered packets are
discarded, and other download channels are ignored.

`gd_mra_cheats.sv` adapts Martin Donlon's M92 engine to the 68000's big-endian
byte lanes. It overrides only work-RAM CPU reads; writes remain unmodified.
Flags bit 0 enables comparison, bits 6:4 select byte/word/longword size (1/2/4),
and bits 9:8 select replace/OR/AND (0/1/2). Word and longword addresses must
be aligned. Longword comparison is rejected because one CPU read provides
only 16 bits. Invalid flags or out-of-range addresses cannot alias into RAM.
Later matching codes take priority, and comparison uses the original RAM data.

Codes are disabled during a selection transfer and runtime reset. The code
table itself survives warm reset and is cleared on a new ROM download/cold
reset. Cheats default to off; enable them after the game boots and disable
them before entering its startup RAM test.

## Video and timing

The core advances fx68k phase events from the 62.5 MHz system clock with a
fractional accumulator, producing the board's 16.265235 MHz CPU rate. Video is
generated as a 512 x 256 raster with a 384 x 224 visible window. One pixel
enable occurs every eight system clocks, giving a 7.8125 MHz pixel rate and
approximately 59.60 Hz vertical refresh.

The renderer retains the DX-101 implementation developed for the related
P0-113A hardware: buffered display-list traversal, sprites, floating tilemap
windows, global transforms, palette lookup, raster interrupt support, and
rowscroll history. Gundam EX Revue hardware validation will determine which
game-specific modes need further refinement.

## EEPROM behavior

The synthesizable 93C46 accepts the board's x16 Microwire command format:
READ, WRITE, ERASE, EWEN, EWDS, ERAL, and WRAL, including sequential reads.
The MRA's `eeprom.bin` initializes all 64 words during ROM download. Writes
survive ordinary core reset but are not currently exported to an SD-card save
file, so they are lost when the core is unloaded or the MiSTer is powered off.

## Reference status

Public MAME source was used as behavioral documentation, particularly for the
board map, clocks, ROM wiring, input ports, and EEPROM GPIO. MAME currently
marks the game as having imperfect timing and documents known slowdown/music
tempo uncertainty. This project does not assume those timing behaviors are
hardware-correct; validation against original-board footage or measurements
may require independent refinements.
