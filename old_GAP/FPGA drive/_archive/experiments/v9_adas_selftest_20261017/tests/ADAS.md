# Versions 8 And 9: Lane Status And Synthetic Self-Test

These are experimental image-space heuristics. They do not implement pedestrian
or obstacle recognition, physical speed/range measurement, vehicle control or
an FPGA/MCU physical transport. Board observations and accuracy measurements
are pending. See `../bitstreams/8_9_acceptance.md` for the burn/check sequence.

## Processing Contract

Version 8 uses CMOS1. It retains the version 4 detector and version 6 frame
repair, with the version 7 crosswalk candidate enabled. The new geometry module
reads aligned white/yellow masks, not the green/cyan annotation. It does not
change those masks or broaden the old row-405 lane ROI.

At 1280x720, `lane_geometry.v` examines rows 405..711 and columns 128..1151.
Mask runs may span holes of at most four pixels; accepted width is 2..64.
Each row chooses the nearest candidate on either side of image center, excluding
the center +/-24 region. Rows with more than six runs are rejected. Adjacent
accepted rows may move by at most 12 pixels.

Four eight-row bands are centered at y=496,560,624,688. Each needs six hits and
at most 64 pixels of x spread; its anchor is the midpoint of its x extrema.
A side needs two usable bands, a last anchor at y>=624, and 32 supporting rows.
A lane pair additionally needs both near-band anchors and width 256..1024.
Bands intersecting the current crosswalk candidate are excluded. A narrow
double-yellow divider is not an ego lane merely because it contains two lines.

Continuous/solid candidates need 75% of ROI rows and an internal maximum gap
<=8 rows. Dashed candidates need at least two runs of 12 consecutive supported
rows and an internal gap >=12. Other cases are unknown. A crosswalk candidate
suppresses both type classifications. These thresholds do not establish legal
lane boundaries or traffic rules.

Offset is image center minus lane center at the near band, in pixels. Positive
means the image-center proxy is to the right. The warning requires three
consecutive same-direction frames with abs(offset)*6 >= lane width. It clears
on an invalid pair or a below-threshold frame. Invalid results use explicit
validity flags; a zero value must not be interpreted as a valid centered lane.

The HUD is applied after the crosswalk overlay. Results are frozen at the next
output VS, so geometry belongs to the previous complete frame. It adds no pixel
pipeline register, but the existing frame buffering/display path still has
latency. Its measured end-to-end delay and physical frame rate are unknown.
New boundaries are thin blue/orange lines with no filled road area. Text is
`L/R`, `S/D/?/-`, `OFF`, `Z`, frame ID, and `EXPERIMENT`. There is no camera-stall
overlay: a camera stopping completely can leave the DDR display frozen.

`img_proc.ADAS_ENABLE=0` is the reusable module default; the board top selects 1.
The separate `adas_packet.v` is tested with image snapshots but is not wired to
a physical top-level transport. Wire format and C/Python APIs: `../host/README.md`.

## Synthetic Source

Version 9 selects `SELF_TEST=1` in the board top. It uses the existing 25 MHz PLL
output, bypassing camera pixels, pixel clock and configuration-done gating.
DDR, HDMI, PLL and board power are still required. No new pin assignments are
made. The six phases are centered, right offset, left offset, dashed, crosswalk,
and blank. Each lasts 120 input frames; the internal raster is 1296x736 with
1280x720 active pixels. The nominal phase duration is about 4.58 seconds at
25 MHz, not a measured monitor frame rate. `TEST` stays visible in every phase.

The final working top defaults back to `SELF_TEST=0`. The final generic PDS
outputs come from version 9; use the explicitly named bitstreams and archived
reports, not a generic output filename, to identify a version.

## Verified Evidence

The final runs recorded on 2026-10-17 use the current RTL. Dates are the local
timestamps emitted by the build/simulation tools.

| Test/log | Scope | Result |
| --- | --- | --- |
| `lane_geometry_v8.log` | 21 geometry cases plus interruption, blanking, reset | PASS |
| `lane_geometry_road_v8.log` | 3 original photo masks, 2,764,800 mask pixels | PASS |
| `adas_packet_v8.log` | 114 exact bytes, independent CRC, backpressure, atomic capture, busy-drop, reset | PASS |
| `img_proc_adas_v8.log` | 14 full frames, 12,902,400 exact RGB pixels, 14 snapshots, 532 packet bytes | PASS |
| `adas_test_pattern_v8.log` | Six phases, 5,529,600 active pixels traversed, raster and phase wrap | PASS |
| `img_proc_selftest_v9.log` | Source through pipeline, 2 frames, 1,837,824 exact pixels outside watermark, 2 snapshots | PASS |
| `img_proc_zebra_v8_compat.log` | ADAS disabled, 4,608,000 exact pixels, 5 crosswalk results | PASS |
| `adas_protocol_python_v8.log` | 11 Python framing, CRC, freshness and software-simulation tests | PASS |
| `adas_protocol_c_unit_v8.log`, `adas_protocol_c_pipeline_v8.log` | C decodes 3- and 14-packet RTL captures, 304 single-bit corruptions each, rollover/freshness | PASS |
| `adas_demo_v8.log` | Three explicitly software-only scenarios, no actuator output | PASS |
| `adas_artifacts_v8.log` | Packet payload equality, four exact previews, complete TEST watermark preview | PASS |

The six-phase source test compares all non-watermark RGB pixels, checks a
watermark pixel each frame, and checks coordinates/counts for every active pixel.
The separate artifact check verifies every watermark pixel in one captured
full-pipeline frame. C compiled with C99 and `-Wall -Wextra -Werror` on the PC;
this is not an MCU cross-compilation or a physical communication measurement.

Pipeline sequence: centered; right offset x4; blank x2; dashed x2; crosswalk x3;
blank x2. Row gaps vary from one to three clocks. The tests cover appearance and
clearing of warnings/crosswalks, RGB preservation, masks and one-frame annotation
delay. The integer geometry/HUD oracle is separate from RTL. Original mask
generation uses the unchanged version 4 Python detector model.

The three original photos produce flags 0x43,0x43,0x40, all with pair invalid.
Their centered dividers/hatching do not establish the current ego lane. These
are model/RTL consistency tests, not labeled accuracy tests. A `NO PAIR` result
must not be changed to a positive just to make a demonstration look successful.

`output/adas/card_*.png` are six unannotated synthetic camera test cards.
`rtl_preview_0..3.png` are RTL outputs (transition, right warning, dashed,
crosswalk). `rtl_selftest.png` is deliberately a transition: shifted image,
prior centered geometry, and permanent TEST watermark. None is a board photo.

## Reproduction

Run from the project directory with Python 3.10+, NumPy and Pillow:

```powershell
python tests/road_marking_model.py --vectors --filter-fixture
python tests/zebra_fixtures.py
python tests/adas_fixtures.py
python tests/test_adas_protocol.py --vectors -v
```

The generated full-frame HEX fixtures are large and intentionally omitted from
the archive. Keep the three raw PNG fixtures. From `tests`, compile the modules
and benches with the installed simulator:

```powershell
$bin = 'D:/Xilinx/Vivado/2018.3/bin'
$rtl = @('lane_detect', 'img_proc', 'zebra_detect', 'zebra_overlay', 'lane_geometry', 'adas_overlay', 'adas_packet', 'adas_test_pattern') | ForEach-Object { "../source/rtl/$_.v" }
$benches = @('lane_geometry_tb', 'lane_geometry_road_tb', 'adas_packet_tb', 'img_proc_adas_tb', 'adas_test_pattern_tb', 'img_proc_selftest_tb', 'img_proc_zebra_tb')
$files = $benches | ForEach-Object { "$_.v" }
& "$bin/xvlog.bat" --sv @rtl @files
if ($LASTEXITCODE) { throw 'xvlog failed' }
foreach ($bench in $benches) {
    $snapshot = "${bench}_repro"
    & "$bin/xelab.bat" $bench --O3 -s $snapshot
    if ($LASTEXITCODE) { throw "xelab failed: $bench" }
    & "$bin/xsim.bat" $snapshot -runall -log "$snapshot.log"
    if ($LASTEXITCODE -or !(Select-String -Path "$snapshot.log" -Pattern 'PASS:') -or (Select-String -Path "$snapshot.log" -Pattern 'Fatal:|ERROR:')) {
        throw "Simulation failed: $bench"
    }
}
```

`--O3` has two dashes. XSim can return exit code zero after `$fatal`, so inspect
the log as above. The old Webtalk path warning is unrelated to test assertions.
Then from the project root:

```powershell
python tests/verify_adas_artifacts.py
python host/adas_protocol.py tests/output/adas/rtl_pipeline_packets.bin
gcc -std=c99 -Wall -Wextra -Werror host/adas_protocol.c tests/adas_protocol_c_test.c -o tests/output/adas/adas_protocol_c_test.exe
tests/output/adas/adas_protocol_c_test.exe tests/output/adas/rtl_packets.bin
tests/output/adas/adas_protocol_c_test.exe tests/output/adas/rtl_pipeline_packets.bin
python host/adas_demo.py --demo
```

Run `build.bat` separately for the selected top parameter. Always inspect the
new build log, new bitstream timestamp and matching `.rtr`. Existing hold repair
is retained. `All Constraints Met` applies only to the existing constraints;
unconstrained-interface warnings remain and are not waived by these tests.
Do not overwrite the named versions or automatically program a board.
