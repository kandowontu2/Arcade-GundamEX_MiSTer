# Graphics SDRAM compatibility

## Evidence

Fluxxant tested the private Gundam paired-edge comparison build on the affected
integrated-memory system and supplied full-image results plus gameplay images:

| Measurement | Reported CRC32 |
|---|---|
| Independently known graphics image | `22645D45` |
| Accepted loader writes | `22645D45` |
| Rising output (R0) read sweep | `A9761A57` |
| Falling output (F0) read sweep | `22645D45` |

The accepted byte count was `01800000`: the populated physical 24 MiB range.
F0 passed; gameplay used F0 and Fluxxant reported that it appeared perfect.
R0 failed. This establishes a capture-path difference in that comparison,
not an invalid ROM archive or a need to change game DIP switches.

The independent `tools/verify_capture_image.py` oracle maps each of the nine
graphics ROMs directly into its board lane, validates its source CRC, zeroes
the fourth 16-bit lane and excludes the unpopulated final 8 MiB. It computes:

- CRC32: `22645D45`
- SHA256: `f0d60fe0f660308288ec5cdf7ad8e6dd4fee4ef715708109cfc288493638580e`

A separately implemented compact-MRA assembler expands to the same image.
No ROM image or game data is distributed.

## Production implementation

`rtl/gd_sdram.sv` uses ALTDDIO_IN's fixed `dataout_l` for every scalar and
DMA read. The input is sampled on the falling edge and retimed to the rising
edge inside the primitive. `dataout_h` is unused.
Quartus retains the paired cell's unused high-half registers, but the audit
finds no timed fanout from them; they are not a selectable rising path.
CAS-3/BL4, read-valid pipe, request/ack latency, packed loader writes, bounded
refresh and rendering are
unchanged. The controller remains at 62.5 MHz with the same inverted
ALTDDIO_OUT forwarded clock as the private Gundam comparison.

The ordinary rising register was already I/O-packed. The experiment does
not prove a specific trace delay, SDRAM specification violation, or an
original fabric-register placement defect. The falling path is the measured
working alternative, not an inferred electrical diagnosis.

There is no runtime calibration, two-edge sweep, diagnostic screen, edge
menu or CRC gameplay gate. One normal production RBF/MRA pair is intended
for both DE10-Nano plug-in SDRAM and compatible integrated-memory systems.
No DIP or phase setting is required.

## Validation boundaries

The supplied hardware confirmation belongs to the private comparison fit,
not the newly refitted diagnostic-free v1.0.5 bitstream. Production validation
is separately recorded in [RELEASE_VALIDATION.md](RELEASE_VALIDATION.md).
Confirm the exact release on both affected hardware and an ordinary MiSTer
before requesting upstream acceptance.

Behavioral and installed Intel simulation models exercise actual pin writes
and stored-data readback. Full-cycle and deliberately narrow return windows
test capture alignment but are not calibrated electrical board models.

As a negative control, the unchanged v1.0.4 rising controller passes the
full-cycle fixture but fails the narrow fixture against stored-data
expectations. Production F0 passes both. This demonstrates that the regression
discriminates capture behavior; it does not measure the physical board window.

TimeQuest and the fitted-register audit check internal clock and client paths.
The inherited SDC does not constrain external SDRAM board I/O timing. Positive
internal slack is not a proof of electrical margin or universal compatibility.
