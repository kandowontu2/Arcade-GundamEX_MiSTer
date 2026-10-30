# v1.0.6 review fixes - 2026-10-30

## Changes

- `gd_crt_geometry` contains the existing vertical/horizontal geometry stages
  and read-clock accumulator. It normalizes the native raster's active-low
  sync before either stage. The mixer receives positive sync even in bypass;
  bypass RGB, CE and blanking remain the original signals. Raster counters,
  CPU timing, interrupts and the geometry-stage algorithms are unchanged.
- Both MRAs now use `<rbf>GundamEX</rbf>` and
  `<rotation>horizontal</rotation>`. The dated RBF keeps its `Arcade-` prefix
  in the source repository. The install ZIP strips it, as Distribution does,
  so older unprefixed test builds cannot shadow this build. ROM definitions,
  per-ROM CRCs, DIP switches, buttons, author credits and cheats are unchanged.
- The root `clean.bat` retains all cleanup commands from the pinned MiSTer
  template and anchors execution to the script directory. It was tested in an
  isolated fixture, not run against the active project's validation outputs.
- The visibility prefilter and drawing stage use shared combinational helpers
  for source-line transformation, signed/wrapped first line, pixel height and
  tile width. Existing state boundaries and the active-record pipeline remain.

## Regression commands and scope

```powershell
python tools/test_verify_release.py
python tools/verify_release.py --version 1.0.6
./sim/run_unit_tests.ps1 -QuartusDirectory "C:/Users/kando/intelFPGA_lite/17.0/quartus"
quartus_map GundamEX --analysis_and_elaboration --read_settings_files=on --write_settings_files=off
```

The metadata checks reject the old MRA prefix and missing rotation, check byte
identity of both MRAs, and cover both source/distributed binary name forms.
The sprite bench compares 8,192 deterministic vectors against an independent
pre-refactor reference and exercises the actual drawing admission stage,
including fixed/global/local/floating combinations and signed/wrapped Y.
The CRT bench uses the native 512x256 raster, checks measured positive sync
pulse widths, and checks nonblack defined pixels for bypass plus zero,
enlarged and reduced V Size in both PVM and Cabinet modes.

### Results

- 14 Python release/metadata/cleanup tests passed, including executing the
  batch script in an isolated Windows fixture from a separate caller directory.
- All 23 RTL simulation runs passed, including both installed Intel-model
  SDRAM tests. The sprite geometry bench accepted 2,320 and rejected 5,872
  descriptors, with no disagreement between the legacy reference, prefilter
  and drawing stage.
- CRT integration passed bypass and all six PVM/Cabinet zero/enlarge/shrink
  cases. Each active case produced more than 85,000 defined nonblack pixels
  per measured frame. Measurement reported four VSync lines and a 377-clock
  HSync counter value (including the module's pixel-edge sampling convention),
  rather than the long inactive intervals.
- A temporary negative-control copy without sync normalization failed the
  integration bench as expected. The temporary source was removed.
- The initial Quartus 17 analysis/elaboration check passed; the subsequent
  production fit completed with zero errors and 135 warnings. All 33 internal
  timing checks have nonnegative slack and zero total negative slack. The
  fitted F0 capture audit also passed without changing the 62.5 MHz core clock.
- MRA semantic comparison confirmed that only lookup, rotation and timestamp
  changed; ROMs, buttons, DIP switches, cheats and author credits are unchanged.

The new fit, exact RBF hash, source fingerprints, live-device results and
remaining validation limits are recorded in `docs/RELEASE_VALIDATION.md`.
The existing v1.0.5 release and tag are retained; v1.0.6 is a separate build.

## Separate follow-ups (not included)

- EEPROM currently retains changes through reset, but the factory image is
  loaded on each new ROM download. Persistent NVRAM needs a 128-byte HPS
  upload/download path, restore-after-factory-load ordering and a matching MRA
  NVRAM declaration. Merely adding metadata would not implement persistence.
- `sys/` remains at the recorded vendored baseline. A separately validated
  framework refresh should include upstream scaler-recovery commit
  [`baaeff6`](https://github.com/MiSTer-devel/Template_MiSTer/commit/baaeff609b69e3d4b424ae9b5f4fa6f2c6907aa4)
  and analog-audio commit
  [`afd7808`](https://github.com/MiSTer-devel/Template_MiSTer/commit/afd7808770dfb6e7ac44e11db9b6b69b5779ab17).
  Neither patch was mixed into this focused review fix.
