# v1.0.6 release validation

## Exact production build

Quartus Prime Lite 17.0.0 Build 595 completed full compilation on
2026-10-30 at 15:10:31 EDT, with zero errors and 135 warnings (17 minutes
3 seconds). Target: Cyclone V `5CSEBA6U23I7`, top `sys_top`, revision
`GundamEX`. No private capture-test synthesis macros are enabled.

The standard assembler RBF, compressed CPF export and repository release
RBF are byte-identical: 4,316,308 bytes, SHA256
`8f2aceeed53b168e08b817d4e64f400a70a993276e9ca0a2bf720b565c26cc03`.
Build ID is `261030`. The repository/standalone name is
`Arcade-GundamEX_20261030.rbf`; the install ZIP uses the identical bytes as
`_Arcade/cores/GundamEX_20261030.rbf`, matching Distribution's stripped prefix.
All 97 fitted-source fingerprints are checked again by the package gate.

Fitted resources: 27,944 / 41,910 ALMs, 39,824 registers, 551 / 553 RAM
blocks, 4,390,334 block-memory bits, 45 / 112 DSP blocks, 3 / 6 PLLs and
145 pins. RAM-block headroom remains very small.

## Timing and SDRAM audit

All 33 internal timing-summary entries have nonnegative slack and zero
total negative slack. Minimum slack in each category:

| Check | Minimum slack |
| --- | ---: |
| Setup | +0.490 ns |
| Hold | +0.202 ns |
| Recovery | +4.019 ns |
| Removal | +0.747 ns |
| Minimum pulse width | +1.122 ns |

The unchanged 62.5 MHz core clock has +2.726 ns setup and +0.247 ns hold
slack. The fitted F0 audit passed: sixteen `ddio_ina` input captures and
sixteen `dataout_l` retimers, a 16.000 ns core-clock period, and three timed
client setup paths with zero violations and worst slack +7.789 ns. Sixteen
unused `dataout_h` registers are retained; no timed fanout was found from
their outputs. They are not claimed to have been pruned.

The inherited SDC does not constrain external SDRAM board I/O. This is an
internal timing/capture audit, not certification of electrical margins on
all SDRAM modules, integrated-memory boards, or analog video connections.

Local evidence is in `output_files/v1.0.6-build.log`,
`GundamEX.fit.summary`, `GundamEX.sta.summary`, `sdram-f0-audit.log`,
`sdram-f0-client-paths.rpt` and `v1.0.6-fitted-source.json`. Generated
reports, fitter databases, screenshots and ROM images are not distributed.

## Regressions and ROM layout

- 23 RTL simulation runs passed, including both installed Intel SDRAM models.
- 14 release/metadata/cleanup Python tests passed.
- Native-raster CRT bypass, PVM and Cabinet tests covered zero, enlarged and
  reduced V Size with active-high sync throughout the processing chain.
- 8,192 sprite vectors matched the legacy reference and drawing-stage admission.
- Independent physical-board and compact-MRA graphics expansion matched at
  24 MiB, CRC32 `22645D45`, SHA256
  `f0d60fe0f660308288ec5cdf7ad8e6dd4fee4ef715708109cfc288493638580e`.

The sprite bench accepted 2,320 and rejected 5,872 descriptors with no
legacy/prefilter/drawing-stage disagreement. CRT cases produced more than
85,000 defined nonblack pixels per measured frame, with four VSync lines
and a 377-clock HSync counter value under the bench's pixel-edge sampling
convention. A temporary negative-control source without normalization failed
as expected. MRA semantic comparison confirmed that only lookup, rotation
and timestamp changed; ROM definitions, CRCs, cheats, DIP tables, buttons
and credits did not change.

## Live-device smoke test

Testing uses the same SHA256-verified release RBF on the user's MiSTer.
The unit reports Linux `6.18.38-MiSTer`; the installed Main binary's SHA256
is `ba8746d91ced547845b743b7826d827cfd6c488de0bcf8b27112d8d77f8a7e27`.
The physical SDRAM module/model is not identified by this remote test.
Cold MRA launch reached the game title. A 180-degree rotation control case
visibly rotated it, confirming that the temporary core configurations were
actually applied. With CRT Geometry enabled, both PVM and Cabinet modes
produced visible source frames at V Size 0, +3 and -3 (neutral H Size and
H/V offsets). Both nonzero Cabinet cases and the repeated negative PVM case
were followed through to attract-mode gameplay. The first negative PVM
snapshot caught a plain title-transition background; the later gameplay
capture confirms that it was not a persistent blank picture.

The service override reached the game's original color/grid test screen.
This was a startup/configuration smoke test, not a full manual service-menu
walkthrough. Remote synthetic Enter did not advance the screen, so physical
controller/service navigation is not claimed as newly verified here. RTL
input-conversion tests passed separately.

Each case used a fresh MRA load with a temporary saved configuration, not
live OSD navigation. After a brief SSH outage, the original configuration
state was restored (the test-created CFG was removed because none existed
beforehand). The final MRA reload again reached attract-mode gameplay with
the new RBF. No global MiSTer video or input mappings were changed. Source
captures were visually inspected, but no full-playthrough artifact-free claim
is made.

## Scope and remaining limits

MiSTer source-frame captures do not prove the physical HDMI/analog signal,
OSD presentation, audio quality, every frame of a playthrough, or compatibility
on the affected SuperStation One. Those require tester confirmation of this
exact fit. No board-dependent DIP or capture-edge setting is introduced.

EEPROM changes persist through game reset but are replaced by the factory
image at relaunch. Persistent NVRAM and a full `sys/` refresh are separate
follow-ups, not features of this release. The older v1.0.5 validation remains
in its tag. No PR has been submitted to MiSTer-devel.
