# MiSTer-devel preparation

This is a prepared independent repository, not a submitted or accepted
MiSTer-devel contribution. No PR is submitted by the release workflow.

## Repository and distribution

- [x] Public repository named `Arcade-GundamEX_MiSTer`, default branch `main`.
- [x] Source-only development files in `rtl/`, `sys/`, `sim/`, `tools/`
  and `scripts/`; required generated PLL IP and upstream notices retained.
- [x] One current dated RBF and undated MRA in `releases/`:
  `Arcade-GundamEX_20261005.rbf` and
  `Mobile Suit Gundam EX Revue.mra`.
- [x] Source MRA in `mra/`; release copy checked for byte identity.
- [x] ZIP rooted at `_Arcade/`, with the RBF in `_Arcade/cores/`.
- [x] MRA targets `Arcade-GundamEX`; original ROM filename/CRCs, fast-loader
  address, buttons, DIP switches, service controls and MRA cheats retained.
- [x] Contributor name is **kandowontu**. **kandowontu2** is the hosting
  account, not a replacement author credit.
- [x] GPL license, third-party credits and pinned provenance documented.
- [x] No game ROMs, private diagnostics, captures, fitter databases or logs
  are tracked or included in the normal install package.
- [x] Build, regression, audit and packaging commands documented.

The `releases/`, `rtl/` and `sys/` layout is consistent with existing
[MiSTer-devel arcade repositories](https://github.com/MiSTer-devel/Arcade-IremM92_MiSTer).
Individual maintainers may request additional changes; this is not an official
acceptance checklist.

The [official template](https://github.com/MiSTer-devel/Template_MiSTer#source-structure)
requires `<core_name>_YYYYMMDD.rbf`. The distribution collector's
[`uniq_files_with_stripped_date` and `get_latest_release`](https://github.com/MiSTer-devel/Distribution_MiSTer/blob/main/.github/download_distribution.py)
ignore undated binaries. The 2026-10-09 packaging refresh fixes this without
changing the v1.0.5 bitstream or dating the MRA target. A source-list/database
entry is still needed for updater inclusion; none has been submitted.

## Before an eventual fork/transfer

- [ ] Confirm the exact published v1.0.5 RBF on an ordinary MiSTer and the
  affected integrated-SDRAM system, not just the earlier private test fit.
- [ ] Exercise HDMI and native analog video, both players, audio, service
  mode, cheats, warm reset and cold ROM loading; record Main version and
  SDRAM hardware.
- [ ] Retain the documented external-I/O timing limitation unless measured
  board timing and appropriate constraints are supplied.
- [ ] Agree repository ownership, naming and licensing expectations with
  MiSTer-devel maintainers; change hosting URLs only when the destination exists.
- [ ] Add updater database integration only after the destination and release
  policy are agreed.

The publishing script builds local ZIPs only. It creates neither GitHub forks
nor PRs and does not write to MiSTer-devel repositories.
