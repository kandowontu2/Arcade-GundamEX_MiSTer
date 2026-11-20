# MiSTer-devel preparation

This is a prepared independent repository, not a submitted or accepted
MiSTer-devel contribution. No PR is submitted by the release workflow.

## Repository and distribution

- [x] Public repository named `Arcade-GundamEX_MiSTer`, default branch `main`.
- [x] Source-only development files in `rtl/`, `sys/`, `sim/`, `tools/`
  and `scripts/`; required generated PLL IP and upstream notices retained.
- [x] One current dated RBF and undated MRA in `releases/`:
  `Arcade-GundamEX_20261119.rbf` and
  `Mobile Suit Gundam EX Revue.mra`.
- [x] Source MRA in `mra/`; release copy checked for byte identity.
- [x] Both MRAs declare standard 128-byte index-4 NVRAM before ROM replay;
  action labels match the control card and preserve the default mapping.
- [x] ZIP rooted at `_Arcade/`, with the identical RBF installed under
  `_Arcade/cores/GundamEX_20261119.rbf`, matching Distribution's stripped prefix.
- [x] MRA targets `GundamEX` and declares horizontal rotation; original ROM filename/CRCs, fast-loader
  address, buttons, DIP switches, service controls and MRA cheats retained.
- [x] Contributor name is **kandowontu**. **kandowontu2** is the hosting
  account, not a replacement author credit.
- [x] GPL license, third-party credits and pinned provenance documented.
- [x] No game ROMs, private diagnostics, captures, fitter databases or logs
  are tracked or included in the normal install package.
- [x] Build, regression, audit and packaging commands documented.
- [x] Root-level template `clean.bat` retained; review entry points and
  known validation limits collected in `REVIEW_GUIDE.md`.

The `releases/`, `rtl/` and `sys/` layout is consistent with existing
[MiSTer-devel arcade repositories](https://github.com/MiSTer-devel/Arcade-IremM92_MiSTer).
Individual maintainers may request additional changes; this is not an official
acceptance checklist.

The [official template](https://github.com/MiSTer-devel/Template_MiSTer#source-structure)
requires `<core_name>_YYYYMMDD.rbf`. The distribution collector's
[`uniq_files_with_stripped_date` and `get_latest_release`](https://github.com/MiSTer-devel/Distribution_MiSTer/blob/main/.github/download_distribution.py)
ignore undated binaries. Current packaging retains the fitted build date in
the RBF filename without dating the MRA target. A source-list/database entry
is still needed for updater inclusion; none has been submitted.

## Before an eventual fork/transfer

- [x] Exact v1.0.7 release RBF loaded on the user's MiSTer with verified upload
  hash, cold MRA boot, source-frame attract gameplay, PVM +3 / V Offset -1
  and the service startup screen. See the current validation document.
- [ ] Confirm the exact v1.0.7 RBF on an ordinary MiSTer and the
  affected integrated-SDRAM system, not just the earlier private test fit.
- [ ] Exercise HDMI and native analog video, both players, audio, service
  mode, cheats, warm reset and cold ROM loading; record Main version and
  SDRAM hardware.
- [x] Confirm actual CPU EEPROM writes, dirty-triggered OSD autosave and all
  128 restored bytes after two Menu-core/relaunch cycles on the user's device,
  using the unchanged production RBF. Restore settings and remove test files.
- [ ] Retain the documented external-I/O timing limitation unless measured
  board timing and appropriate constraints are supplied.
- [ ] Agree repository ownership, naming and licensing expectations with
  MiSTer-devel maintainers; change hosting URLs only when the destination exists.
- [ ] Add updater database integration only after the destination and release
  policy are agreed.

The publishing script builds local ZIPs only. It creates neither GitHub forks
nor PRs and does not write to MiSTer-devel repositories.
