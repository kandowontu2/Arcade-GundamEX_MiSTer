# v1.0.5 release validation

## Production build

- Quartus Prime Lite 17.0.0 Build 595, Cyclone V `5CSEBA6U23I7`.
- Full compile completed 2026-10-05 20:03:38 EDT in 40 minutes 56 seconds:
  zero errors, 136 warnings. This is not a warning-free build.
- 28,229 ALMs; 39,982 registers; 551/553 RAM blocks; 45 DSP blocks.
- Standard assembler RBF and explicit compressed CPF export are byte-identical.
- RBF length: 4,314,820 bytes.
- RBF SHA256: `852303fbf087041eba26ed3e997298fc6a5bb5531aaa5e3cb0701774629b979c`.
- All fingerprinted project, RTL, IP and framework files remained unchanged
  between compile and release packaging. No private test macro is present.

## Internal timing and fitted capture

All 33 reported internal timing entries have nonnegative slack and zero TNS.

| Reported quantity | Minimum slack |
|---|---|
| Setup, all clocks | +0.488 ns |
| Hold, all clocks | +0.200 ns |
| Recovery | +4.418 ns |
| Removal | +1.116 ns |
| Minimum pulse width | +1.122 ns |
| Core 62.5 MHz setup | +2.278 ns |
| Core 62.5 MHz hold | +0.248 ns |

`scripts/audit_sdram_f0.tcl` passed: 16 fitted falling captures (`ddio_ina`),
16 low-data rising-edge retimers (`dataout_l`), and a 16.000 ns core period.
The paired I/O primitive retains 16 unused high-half registers; the open
`dataout_h` output has no timed register fanout ("Nothing to report").
The three reported F0-to-client paths have zero violations and worst setup
slack +7.771 ns.

External SDRAM board I/O remains unconstrained by the inherited SDC. These
internal checks do not measure the board data window or certify electrical
margin on every system.

## Functional and package checks

- 21 production simulation runs passed: the 17 existing focused benches plus
  full/narrow pin-storage tests with behavioral and installed Intel models.
- The pin tests write/read 32 KiB, four banks and 32 physical rows, exercise
  scalar/DMA reads, refresh, row changes and controller reset.
- Negative control: the old v1.0.4 rising controller passes the full-cycle
  fixture but fails the narrow fixture as expected. Production F0 passes both.
  These windows are deliberate stimuli, not calibrated board models.
- Independent board-lane ROM expansion matches the separate compact-MRA
  expansion: 24 MiB, CRC32 `22645D45`, SHA256
  `f0d60fe0f660308288ec5cdf7ad8e6dd4fee4ef715708109cfc288493638580e`.
- MRA semantics are unchanged except for the timestamp: original ROM CRCs,
  fast-DDR address, coin tables, buttons, service controls and cheats retained.
- Packaging checks undated naming, source/release MRA byte identity, author
  credit, checksums, source hygiene and every install-ZIP payload byte.

The private comparison results are documented separately in
[SDRAM_COMPATIBILITY.md](SDRAM_COMPATIBILITY.md). Exact production hardware
retesting remains outstanding; the earlier private fit is not the new RBF.
