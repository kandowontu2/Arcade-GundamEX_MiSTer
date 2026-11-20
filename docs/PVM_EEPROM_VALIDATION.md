# v1.0.7: PVM position, labels, EEPROM persistence

These changes are included in v1.0.7. No MiSTer-devel PR has been submitted.
The v1.0.6 release/timing evidence is retained in its Git tag. Current fit
evidence is in `RELEASE_VALIDATION.md`.

## Implemented behavior

- `crt_vsize` supplies the running frame total: latched PVM output lines while
  retiming, measured native lines for Cabinet/bypass. `crt_adjust` wraps
  negative V Offset using that total, and its history covers larger totals.
- Both MRAs and fallback OSD labels use Weak Attack, Medium Attack, Strong
  Attack, Throw, preserving A/B/X/Y ordering, ROM CRCs, DIP and cheat tables.
- Both MRAs declare a 128-byte index-4 EEPROM save, before the ROM node.
- `gd_eeprom_nvram` stages a full save transfer, waits for factory replay,
  restores before runtime release, and ignores unrelated or malformed data.
- All Microwire write/erase operations dirty the image. A frozen upload
  snapshot cannot mix generations; writes during upload request a later save.
  Main's normal OSD save path is used, without a Linux helper or script.

## Tests completed

- Real bundled HPS interface: factory default without a save, protected writes,
  WRITE/ERASE/WRAL/ERAL, repeated saves, actual upload-request poll/rearm,
  incomplete uploads, atomic snapshots with a concurrent game write, cold
  restore before factory replay, late restore, short/overlong/reordered data,
  and ROM/DIP/cheat channel isolation. All 128 saved bytes compare exactly.
- 48 signed-offset cases: V Offset -8 through +7 at 247, 256 and 265 lines;
  12,288 output-line assertions passed. The 247-line -1 case advances sync by
  one line. A fixed-256 negative-tap control failed as expected.
- 16 Python metadata/release/cleanup tests passed.
- The complete native-raster chain also passed the settled PVM +3 / V Offset
  -1 check: 247 output HSync lines and the expected one-line sync advance.
  Six zero/enlarge/shrink PVM/Cabinet picture-presence cases passed as well.

- All 25 RTL regression runs passed, including both installed Intel SDRAM
  simulation models, alongside the 16 Python metadata/cleanup tests.

The new production fit passed: zero errors, all 33 internal timing checks
nonnegative, fitted F0 audit passed, and all 98 source fingerprints unchanged.
Exact resource/slack/hash evidence is in `RELEASE_VALIDATION.md`.
The exact RBF/MRA are installed on the user's MiSTer. Boot/attract gameplay,
PVM +3 / V Offset -1 picture presence and service-screen access were observed.
Persistent virtual controls resolved the initial remote-input difficulty.

Actual EEPROM persistence was then confirmed on that SAME production RBF:
standalone 68000 software wrote all 64 words using the real TMP68301 EEPROM
GPIO, Main automatically saved all 128 bytes on OSD entry, and two complete
Menu-core/relaunch cycles each passed all-word CPU serial readback. Unique
state markers advanced only after those comparisons passed; both subsequent
autosaved images matched all 128 expected bytes. No expected image was
written to the host save file by the test tools. Exact hashes and protocol
scope are recorded in `RELEASE_VALIDATION.md`.

The temporary software/MRA/save were removed, original settings restored,
virtual devices destroyed and the normal game reloaded. Analog output and
SuperStation One behavior still require independent tester confirmation.

## Usage and limitations

Use a matching new RBF and MRA. The old published RBF does not implement the
new EEPROM channel. Main saves in `config/nvram/` using the MRA filename.
After editing board settings, open the MiSTer OSD and wait for Saving to
complete before leaving the core or powering off; Save settings is also an
explicit save path. Abrupt power loss before flushing is not covered.

Sources checked: [Main arcade loader](https://github.com/MiSTer-devel/Main_MiSTer/blob/master/support/arcade/mra_loader.cpp),
[Main OSD save handling](https://github.com/MiSTer-devel/Main_MiSTer/blob/master/menu.cpp),
[MiSTer NVRAM documentation](https://mister-devel.github.io/MkDocs_MiSTer/developer/mra/).
