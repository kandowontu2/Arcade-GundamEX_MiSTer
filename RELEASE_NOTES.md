# Mobile Suit Gundam EX Revue MiSTer v1.0.5

This release adopts the working falling-edge graphics SDRAM capture path
identified in Fluxxant's full-image comparison. One shared build is supplied
for ordinary MiSTer and compatible integrated-memory systems.

## Install

1. Extract `Arcade-GundamEX_MiSTer_v1.0.5.zip` to the MiSTer SD-card root.
   It installs `_Arcade/Mobile Suit Gundam EX Revue.mra` and
   `_Arcade/cores/Arcade-GundamEX_20261005.rbf`.
2. Keep your legally obtained, supported `gundamex.zip` in `games/mame/`.
3. Launch **Arcade > Mobile Suit Gundam EX Revue**.

Replace both RBF and MRA. No ROM preprocessing, DIP changes or alternative
hardware-specific download is required. Game ROMs are not included.

## Packaging refresh - 2026-10-09

The existing RBF is now dated for MiSTer's updater/distribution conventions.
Its SHA256 remains
`852303fbf087041eba26ed3e997298fc6a5bb5531aaa5e3cb0701774629b979c`:
this is a filename/package correction, not a new FPGA build. The MRA remains
unchanged and still targets `Arcade-GundamEX` without a date or extension.
The ZIPs and checksums have been refreshed; the attached source ZIP includes
the packaging/helper/documentation fixes, while the original v1.0.5 tag is
unchanged. Re-download the install ZIP if you previously downloaded v1.0.5.
Remove the old undated `Arcade-GundamEX.rbf` from `_Arcade/cores/` to avoid
duplicate local files; it is the same bitstream. Dated naming does not itself
add this independent repository to an updater database.

## Changes

- Fixed F0 ALTDDIO_IN capture for every scalar and graphics DMA read, with the
  same 62.5 MHz memory clock, CAS-3/BL4 pipeline, writes and refresh.
- Removed the private experiment from the production project: no test screen,
  edge selector, CRC sweep, startup comparison or gameplay gate.
- Retained fast DDR/legacy loading, MRA cheats, service/DIP menus, stereo audio,
  both players, analog-stick conversion, CRT geometry and 180-degree rotation.
- Added stored-data pin regressions, installed Intel-model tests, a fitted
  capture audit, checked packaging and MiSTer-devel preparation notes.
- Preserved **kandowontu** contributor credit and added **Fluxxant** for
  integrated-SDRAM testing. Full third-party credits remain in `CREDITS.md`.

## Validation and known limits

The earlier private test returned `22645D45` for both accepted graphics
writes and the F0 read sweep; R0 returned `A9761A57`. Fluxxant reported clean
gameplay. The diagnostic-free production bitstream is a new Quartus fit,
validated by the production regression suite, fitted-register audit and
internal timing checks; those do not constitute hardware confirmation of the
exact new RBF. Exact-release DE10-Nano/affected-system retesting remains the
final upstream-readiness check.

The inherited SDC leaves external SDRAM board I/O timing unconstrained.
Internal timing closure does not certify electrical margin on every system.
See `docs/RELEASE_VALIDATION.md` and `docs/SDRAM_COMPATIBILITY.md` in the source.

Cheats should be enabled after boot and disabled before startup RAM tests.
EEPROM writes survive warm reset only, not unloading or power-off.
Native 15-kHz analog output uses **Scandoubler Fx: None** unless your display
requires scandoubling. Geometry defaults to Off for the native raster.

The repository is prepared for a possible MiSTer-devel fork/transfer, with
dated RBFs, undated MRAs in `releases/` and SD-card-root ZIP paths. No PR has been
submitted and no MiSTer-devel acceptance is implied.
