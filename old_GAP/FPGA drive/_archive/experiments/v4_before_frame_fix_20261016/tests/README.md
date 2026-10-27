# Road-Marking Regression

Active baseline: `bitstreams/4_road_markings_filtered_cmos1.sbit`.
On 2026-10-16 the user rejected version 5 after board testing (excessive green
overlays and a blurry image). Its cause remains undiagnosed. Changed sources,
tests, outputs, and reports were archived under
`experiments/v5_roi23_rejected_20261016/` before restoring version 4 behavior.
Neither named bitstream was overwritten.

This is a road-paint candidate extractor, not semantic road segmentation, lane
numbering, solid/dashed classification, or a safe-to-change-lane decision.
The three fixtures were supplied by the user. They are visual regression
examples without ground-truth annotations; nonzero masks are not accuracy scores.

## Current Hardware Display

- `MODE=4`, `DIAG_CYCLE=0`: original RGB565, green white-paint candidates, cyan
  yellow-paint candidates. There is no all-object red-edge overlay in this mode.
- `MODE=5`: the same candidates on black.
- `MODE=0/1/2/3`: original / grayscale / median / Sobel diagnostics.
- `MODE=6/7`: row-buffer diagnostics.
- Camera port: CMOS1. Output: 1280 x 720.

Detection starts at zero-based row 405 (`720 * 9 / 16`), as in version 4.
Rows 0..404 remain unpainted. The version 5 lower-two-thirds gate is not active.
The image is not cropped or scaled by this gate. A centered road trapezoid
further limits the candidates:

`half_width = 320 + 3*depth`, `depth = max(0, y-405)`.

The existing eight-pixel left/right and two-row bottom processing margins remain.
These coordinates refer to the camera frame, not the road image inside a browser.
There is no automatic browser-picture or road-content bounding-box detector.
The road must fill most of the camera view; a small picture surrounded by a
desktop or monitor bezel is not equivalent to the fixtures. Camera color cast,
exposure, perspective, shadows, and worn paint require on-board validation.
Faint lines can be missed and textured pavement can still produce candidates.
Dim yellow paint can pass the neutral/white test instead of the yellow test.

White candidates require smoothed luma at least 112 and an initial eight-pixel
one-sided contrast of 20. Yellow candidates use RGB channel differences, with
`R+32 >= G`. Candidate support propagates at most +/-6 pixels per row,
saturates at 7, and requires 6 connected rows.
This does not bridge virtual lines across dashed gaps or select one lane per side.

There is no version 5 multiscale, two-sided neutral-background test.
Before painting, only supported yellow candidates pass a horizontal-width
filter. Gaps up to four pixels are closed for measurement only. Whole runs
wider than `min(96, 64 + floor(max(0, y-405)/8))` pixels are suppressed, including
their leading/trailing edges. Original candidate holes are not painted.
White candidates are not width-filtered. This is a width heuristic, not
connected-component area or semantic foliage removal: separated small blobs
and narrow false candidates can remain. Broad diagonal yellow hatch bars can
also be suppressed.

## Reference And RTL Tests

From the project directory, use Python with NumPy and Pillow:

```powershell
python tests/road_marking_model.py --vectors --filter-fixture
```

This runs deterministic synthetic positive/negative tests, resizes all fixtures
to 1280 x 720, and writes candidate overlays, masks, and integer vectors under
`tests/output`. Overlays are a standalone integer model, not camera captures.

The HDL test exercises `lane_detect` with precomputed smoothed-luma input. It
checks all pixels, DE/VS delay (119 clocks), all three paint modes, and a following
blank frame without resetting RAM. This is a unit test, not an end-to-end test of
the camera, `img_proc` line buffers, DDR3, or HDMI.
The fourth fixture covers perforated wide blobs, thin double lines, exact/over-limit
widths at different depths, a right-edge blob, white paint, and per-pixel mode
changes. The version 5 precision fixture is retained only in the archive.
The user's new monitor photos already contain overlays and were not treated as
raw RGB fixtures or ground-truth accuracy labels.

With the local Vivado 2018.3 simulator, from `tests`:

```powershell
D:\Xilinx\Vivado\2018.3\bin\xvlog.bat --sv ../source/rtl/lane_detect.v ../source/rtl/img_proc.v road_marking_tb.v
D:\Xilinx\Vivado\2018.3\bin\xelab.bat road_marking_tb --O3 -s road_marking_sim
cmd /c 'D:\Xilinx\Vivado\2018.3\bin\xsim.bat road_marking_sim -runall -testplusarg "VECTORS=output/road_1.hex" -testplusarg "MODE=1" -log road_1_sim.log'
cmd /c 'D:\Xilinx\Vivado\2018.3\bin\xsim.bat road_marking_sim -runall -testplusarg "VECTORS=output/road_2.hex" -testplusarg "MODE=2" -log road_2_sim.log'
cmd /c 'D:\Xilinx\Vivado\2018.3\bin\xsim.bat road_marking_sim -runall -testplusarg "VECTORS=output/road_3.hex" -testplusarg "MODE=0" -log road_3_sim.log'
cmd /c 'D:\Xilinx\Vivado\2018.3\bin\xsim.bat road_marking_sim -runall -testplusarg "VECTORS=output/road_4.hex" -testplusarg "MODE=1" -testplusarg "SWITCH_MODE=1" -log road_4_sim.log'
```

Each run must contain `PASS: 1843200 pixels` and no fatal errors. Candidate pixel
counts must match `output/results.json`. Compilation alone is not a test pass.

Version 4 baseline counts, reproduced by the restored model and RTL on 2026-10-16:

| Fixture | Mode | Compared pixels, including blank frame | White | Yellow |
| --- | --- | --- | --- | --- |
| road_1 | overlay | 1,843,200 | 10,375 | 0 |
| road_2 | mask | 1,843,200 | 2,299 | 17,179 |
| road_3 | base | 1,843,200 | 11,987 | 29,548 |
| filter_fixture | switching | 1,843,200 | 3,339 | 21,800 |

All four restored RTL runs passed, totaling 7,372,800 compared pixels. Counts
match the original version 4 logs. The new logs are `road_v4_restore_1_sim.log`
through `road_v4_restore_4_sim.log`. Candidate counts are not precision/recall scores.
This check uses separate snapshots and waveform/log names for concurrent runs;
the commands above reproduce the cases sequentially.

## Build And Board Check

Run `build.bat` and inspect `report_timing/hdmi_ddr_ov5640_top.rtr`, including
unconstrained inputs. The tool's `All Constraints Met` summary only applies to
the constraints present; camera input-delay warnings remain a separate issue.
The retained version 4 build used multi-corner hold repair in `flow.tcl`, with a
200 ps repair target and up to 16 iterations, and reports `All Constraints Met`.
Constraints were not relaxed. Its log is `build_road_markings_filtered_holdfix.txt`.
Camera input-delay warnings still remain.
These results do not certify the unconstrained camera interface.

Program the retained `bitstreams/4_road_markings_filtered_cmos1.sbit` on CMOS1.
SHA256: `ED53C960F810528BEC0A641565A00B1A6FED9C2E6FCFAEDAC1AF64F32D613467`.
No PDS rebuild or board programming was performed for this baseline switch.
The main `generate_bitstream/hdmi_ddr_ov5640_top.sbit`, `report_timing/`, and
other PDS generated outputs still belong to version 5 until a new full build;
do not attribute those reports or that generic binary to the restored source.
The rejected version 5 named binary is retained for comparison, not recommended.

For each fixture, fill the camera view with the road, check marking alignment
and missed/false candidates, then move the camera and change illumination.
Also test an indoor/no-road scene. Do not use candidate colors as evidence of
lane semantics or deploy the output for real vehicle control.
