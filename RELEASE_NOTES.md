# Mobile Suit Gundam EX Revue MiSTer v1.0.7

This release adds hardware-confirmed EEPROM persistence, fixes PVM vertical
positioning, and corrects the four action labels. Source, credits and review
guidance are included. No PR has been submitted to MiSTer-devel.

## Install

Extract the matching install ZIP at the MiSTer SD-card root. It supplies
`_Arcade/cores/GundamEX_20261119.rbf` and
`_Arcade/Mobile Suit Gundam EX Revue.mra`. Keep your legally obtained
`gundamex.zip` in `games/mame/`, then launch the MRA from Arcade.

The repository/standalone RBF uses `Arcade-GundamEX_20261119.rbf` with identical
bytes. Rename that standalone file to `GundamEX_20261119.rbf` for manual
installation, matching Distribution and preventing an older unprefixed test
file from taking precedence. Other Gundam games are separate cores.

Install the new RBF and MRA together: the old published RBF does not implement
the new EEPROM NVRAM channel. Source ROM CRCs and factory EEPROM data are
unchanged. No game ROMs are included.

## Changes

- Negative PVM V Offset wraps using the running frame length, including size
  slew. At V Size +3 the frame is 247 lines; V Offset -1 advances sync one
  line instead of delaying it by eight. Cabinet and bypass use native totals.
- Both MRAs and fallback OSD labels now read Weak Attack, Medium Attack,
  Strong Attack and Throw. The default A/B/X/Y assignment order is unchanged.
- The 128-byte 93C46 image saves/restores through standard MiSTer arcade NVRAM.
  Saved data is staged and applied after factory-ROM replay, before CPU
  startup. Incomplete/reordered transfers and unrelated indices are ignored.
- WRITE, ERASE, WRAL and ERAL request a save. Each upload uses an atomic
  snapshot, with later writes requesting another save rather than being lost.

## Saving board settings

After changing settings in the game's service menu, open the MiSTer OSD and
let **Saving...** finish before changing cores or switching off power.
**Save settings** is also an explicit save path. Main uses
`config/nvram/Mobile Suit Gundam EX Revue.nvm`, restored on subsequent launches.
There is no helper script. Sudden power loss before the OSD flush is not
covered; renaming the MRA changes the associated save filename.

## Validation and limits

All 25 RTL runs, 16 metadata/cleanup tests, 33 internal timing checks and the
fitted SDRAM audit passed. The exact RBF booted on the user's MiSTer, including
PVM +3 / V Offset -1 and service-screen access; original settings were restored.
EEPROM persistence was confirmed on the actual device: CPU writes through
the EEPROM GPIO, automatic OSD saves and two full Menu-core/relaunch cycles
with all 128 bytes verified. No alternate FPGA build or pre-seeded save was
used. Temporary verification files were removed and normal gameplay restored.
Full scope is in `docs/PVM_EEPROM_VALIDATION.md` and
`docs/RELEASE_VALIDATION.md`. Physical analog CRT and
SuperStation One behavior require confirmation of this exact bitstream.
External SDRAM board I/O remains unconstrained by the inherited SDC.

A full framework refresh remains a separate follow-up. Cheats should be
turned off for startup RAM checks. Native analog output normally uses
Scandoubler Fx: None, with CRT Geometry initially Off.

Credit remains **kandowontu**; **kandowontu2** is only the hosting account.
Third-party, FPGA IP and tester credits are retained in `CREDITS.md` and
`UPSTREAM.md`. Maintainers can start with `docs/REVIEW_GUIDE.md` and
`docs/UPSTREAM_READINESS.md`. No private capture diagnostics or game ROMs are
distributed. Repository preparation does not imply MiSTer-devel acceptance
or registration with the default updater database.
