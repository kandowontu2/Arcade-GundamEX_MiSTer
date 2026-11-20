# v1.0.7 release validation

This records the exact v1.0.7 release fit, regressions and live-device checks.
No MiSTer-devel PR has been submitted. Historical v1.0.6 validation remains
in its Git tag, not as duplicate build archives. The maintainer entry point is
`REVIEW_GUIDE.md`.

## Exact production fit

Quartus Prime Lite 17.0.0 Build 595 completed full compilation on 2026-11-19
at 22:42:21 America/New_York, with zero errors and 135 warnings (33 minutes
23 seconds). Target: Cyclone V `5CSEBA6U23I7`, top `sys_top`, revision
`GundamEX`. Build date ID: `261119`; OSD configuration version: `1.0.7`.

The assembler and compressed CPF RBF exports are byte-identical: 4,344,128
bytes, SHA256 `76a8e8e0c292b56e968fdd032da0df1374a05cbc5a9146b8a01433336ee29b26`.
The repository/standalone file is `Arcade-GundamEX_20261119.rbf`; the install
ZIP/device use identical bytes as `_Arcade/cores/GundamEX_20261119.rbf`.
All 98 fitted-source fingerprints match the files used during compilation.
No private diagnostic synthesis macros are enabled.

Fitted resources: 29,048 / 41,910 ALMs, 42,127 registers, 550 / 553 RAM
blocks, 4,390,109 block-memory bits, 45 / 112 DSP blocks, 3 / 6 PLLs and
145 pins. RAM-block headroom remains small.

## Internal timing and capture audit

All 33 timing-summary entries have nonnegative slack and zero total negative
slack. Minimum slack by category:

| Check | Minimum slack |
| --- | ---: |
| Setup | +0.452 ns |
| Hold | +0.247 ns |
| Recovery | +3.818 ns |
| Removal | +1.049 ns |
| Minimum pulse width | +1.122 ns |

The unchanged 62.5 MHz core clock has +2.139 ns setup and +0.247 ns hold
slack. The fitted F0 audit passed: sixteen `ddio_ina` input captures and
sixteen `dataout_l` retimers, a 16.000 ns core period, and three timed client
setup paths with zero violations and worst slack +8.351 ns. Sixteen unused
`dataout_h` registers remain, with no timed fanout from their outputs; they
are not claimed to have been pruned.

The inherited SDC does not constrain external SDRAM board I/O. These checks
are not certification of electrical margins on every module or integrated
memory board, and do not validate physical analog video.

## Regressions

- All 25 RTL regression runs passed, including both installed Intel SDRAM
  simulation models and existing ROM loading, graphics, audio-bus and cheat
  path tests. No simulator runtime failure was reported.
- All 16 Python metadata/release/cleanup tests passed.
- New real-HPS-interface EEPROM tests roundtrip all 128 bytes, restore before
  and after factory replay, reject malformed/unrelated transfers, exercise
  all write/erase commands, validate upload-request poll/rearm, preserve an
  atomic snapshot during a game write, and retain unsaved changes after an
  incomplete upload. The cold-reload test overwrites the saved values with
  factory bytes before restoring, so retained on-chip data cannot fake a pass.
- New signed-offset tests passed 48 combinations (-8 through +7 at 247,
  256 and 265 lines), with 12,288 output-line assertions. A fixed-256 tap
  negative control failed as expected.
- The complete native-raster chain passed all six PVM/Cabinet size-presence
  cases, then settled to V Size +3 / V Offset -1: 247 output lines and sync
  advanced by exactly one line. It also checks the frame-total sideband.
- The independent 24 MiB physical-board expansion and compact MRA expansion
  still agree: CRC32 `22645D45`, SHA256
  `f0d60fe0f660308288ec5cdf7ad8e6dd4fee4ef715708109cfc288493638580e`.
- MRA semantic comparison confirms unchanged ROM definitions/CRCs, DIP
  tables, cheats and default A/B/X/Y order. Changes are labels, NVRAM and
  timestamp; both MRA copies are byte-identical.

Detailed feature-test scope is in `PVM_EEPROM_VALIDATION.md`. Local logs are
`output_files/v1.0.7-build.log`, `v1.0.7-tests.log`, `v1.0.7-rom-oracle.log`,
`v1.0.7-f0-audit.log` and `v1.0.7-fitted-source.json`, plus the Quartus fit and
timing summaries. Generated reports, device captures, fitter databases,
private test helpers and game/save images are not part of the source package.

## Live-device scope

The exact RBF/MRA were installed with permission on the user's MiSTer at
192.168.1.176, kernel `6.18.38-MiSTer`. Main SHA256 was
`ba8746d91ced547845b743b7826d827cfd6c488de0bcf8b27112d8d77f8a7e27`;
the physical SDRAM model was not identified remotely. The RBF upload was
read back and SHA256-verified. Cold MRA
launch reached the Banpresto logo and attract-mode gameplay. A temporary
configuration with PVM V Size +3 and V Offset -1 also reached visible
attract-mode gameplay. The service override reached the original color/grid
test screen. These source-frame captures were visually inspected.

The initial short-lived synthetic keyboard was replaced with a persistent
virtual USB controller/keyboard. Coin input and service-screen navigation
then worked. Main's OSD pixel buffer was read non-invasively to identify the
Save settings item; that action exported a 128-byte factory image exactly.

### End-to-end EEPROM persistence on the actual MiSTer

The SAME production RBF, SHA256 above, passed an additional hardware test.
A temporary private MRA supplied original standalone 68000 diagnostic
software using Main's in-memory ROM patches. The game ROM archive, production
RBF and production MRA were not modified. The 91,596-byte software probe's
SHA256 was `4dc65cf6790b16481826be3b87eef214a418be33389f97eb27d58d1a55154a2a`.
No alternate FPGA build, private HDL port, or pre-seeded NVRAM file was used.

1. With no private save file present, the actual fx68k CPU wrote a distinct
   64-word pattern through the TMP68301 parallel port's CS/SK/DI EEPROM pins.
   The pattern included both endpoint words and differed from factory data.
   Opening the OSD automatically created Main's 128-byte `.nvm`; every byte
   matched the independently generated expected pattern.
2. The FPGA was reconfigured to `/media/fat/menu.rbf`, with `CORENAME=MENU`
   confirmed, then relaunched using the SAME private MRA/production RBF.
   Before any state update, the 68000 serially read and compared all 64 words.
   Only a complete match advanced EEPROM word 33 from `1357` to `2468`.
   Opening the OSD automatically saved the new image; all 128 bytes matched.
3. The Menu/relaunch cycle was repeated. Another complete CPU serial read
   check advanced word 33 to `369c`; the third automatic save again matched
   all 128 expected bytes. The final file was re-read after an SD `sync`.

| Hardware stage | EEPROM state word | Saved-image SHA256 |
| --- | --- | --- |
| CPU writes, first OSD autosave | `1357` | `4752d5ac825c8f7ba767982f6e54790d393f10ed5f674c81a21930ad987db8be` |
| First Menu/relaunch, CPU verifies, autosave | `2468` | `eca91e8040e7ee9acd0ca2b0218db353d3baffb5798051c1e8ae96e6ff853cc2` |
| Second Menu/relaunch, CPU verifies, autosave | `369c` | `fef948cca9a54067b5def9da3071d39eadc91bc2c148530dea7e28618c6f1c00` |

This tests actual CPU EEPROM writes, dirty-triggered OSD autosaving, the real
SD-file download, restore-after-factory ordering and serial readback after
FPGA memory was cleared by reconfiguration. The orchestration never wrote
an expected image into the private `.nvm` file. It is not merely a host-file
hash comparison, nor a simulation substituted for hardware. The state word
intentionally changes per stage; the rest of the pattern remains constant.

After testing, the original game's EEPROM/configuration state was restored
(neither file existed originally, so only test-created files were removed).
The private verification MRA, save, optional CFG and directory were removed;
the virtual input devices were destroyed. Normal Gundam EX Revue was reloaded
and visually confirmed in attract-mode gameplay. The installed RBF hash was
verified unchanged. No private test software/save/ROM image is distributed.

These checks do not certify abrupt-power-loss durability, physical
HDMI/analog electrical behavior, every
gameplay frame, audio quality or SuperStation One compatibility. Independent
hardware confirmation is still needed for this exact refit.

## Saving behavior

Main uses its standard arcade NVRAM path. After changing board settings,
open the MiSTer OSD and let Saving finish before leaving the core or removing
power; Save settings also explicitly writes the image. Sudden power loss
before this flush is not covered. The EEPROM survives ordinary game reset.
A full framework refresh remains outside this update.
