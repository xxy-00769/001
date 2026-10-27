# Road-Marking Regression

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

The upper third (zero-based rows 0..239) is never painted. Detection is restricted
to the lower two-thirds of the complete 1280 x 720 camera frame, starting at row
240. The image is not cropped or scaled by this gate. Within that vertical
range, a centered road trapezoid further excludes distant side objects:

`half_width = 40 + depth + floor(depth/2) + 2*max(0, y-360)`, `depth = max(0, y-240)`.

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
`R+12 >= G` to reject more green-biased pixels. Candidate support propagates
at most +/-6 pixels per row, saturates at 15, and requires 10 connected rows.
This does not bridge virtual lines across dashed gaps or select one lane per side.

Both types also need darker neutral background independently on each side,
sampled at horizontal offsets 8, 16, 32, 64, and 96. Eligible background samples
have RGB range at most 64, `G<=R+20`, `G<=B+20`, and smoothed luma 24..192.
The center must exceed the darkest eligible sample on each side by at least
20 (white) or 12 (yellow). This is a background-color/contrast heuristic, not
semantic asphalt segmentation. Bright pavement, strong color cast, broad
markings, intersections, and displaced/curved roads can still be missed.

Before painting, supported candidates of either color pass a horizontal-width
filter. Gaps up to four pixels are closed for measurement only. Whole runs
wider than `min(96, 12 + floor(max(0, y-240)/4))` pixels are suppressed, including
their leading/trailing edges. Original candidate holes are not painted.
Measurement precedes the two-sided test, so that test cannot thin a perforated
wide blob into accepted short runs. This is a width heuristic, not connected-component
area or semantic foliage removal: separated small blobs and narrow false
candidates can remain. Broad diagonal yellow hatch bars can also be suppressed.

## Reference And RTL Tests

From the project directory, use Python with NumPy and Pillow:

```powershell
python tests/road_marking_model.py --vectors --filter-fixture --precision-fixture
```

This runs deterministic synthetic positive/negative tests, resizes all fixtures
to 1280 x 720, and writes candidate overlays, masks, and integer vectors under
`tests/output`. Overlays are a standalone integer model, not camera captures.

The HDL test exercises `lane_detect` with precomputed smoothed-luma input. It
checks all pixels, DE/VS delay (207 clocks), all three paint modes, and a following
blank frame without resetting RAM. This is a unit test, not an end-to-end test of
the camera, `img_proc` line buffers, DDR3, or HDMI.
The fourth fixture covers perforated wide blobs, thin double lines, exact/over-limit
widths at different depths, a right-edge blob, and white paint.
The fifth fixture covers the upper-third exclusion, newly enabled rows 240..404,
road-trapezoid exclusions, cool-tinted pavement, colored backgrounds, broad panels,
outer white markings, short speckles, and per-pixel mode changes.
The RTL checker also independently rejects any mark in rows 0..239.
The user's new monitor photos already contain overlays and were not treated as
raw RGB fixtures or ground-truth accuracy labels.

With the local Vivado 2018.3 simulator, from `tests`:

```powershell
D:\Xilinx\Vivado\2018.3\bin\xvlog.bat --sv ../source/rtl/lane_detect.v ../source/rtl/img_proc.v road_marking_tb.v
D:\Xilinx\Vivado\2018.3\bin\xelab.bat road_marking_tb --O3 -s road_marking_sim
cmd /c 'D:\Xilinx\Vivado\2018.3\bin\xsim.bat road_marking_sim -runall -testplusarg "VECTORS=output/road_1.hex" -testplusarg "MODE=1" -log road_1_sim.log'
cmd /c 'D:\Xilinx\Vivado\2018.3\bin\xsim.bat road_marking_sim -runall -testplusarg "VECTORS=output/road_2.hex" -testplusarg "MODE=2" -log road_2_sim.log'
cmd /c 'D:\Xilinx\Vivado\2018.3\bin\xsim.bat road_marking_sim -runall -testplusarg "VECTORS=output/road_3.hex" -testplusarg "MODE=0" -log road_3_sim.log'
cmd /c 'D:\Xilinx\Vivado\2018.3\bin\xsim.bat road_marking_sim -runall -testplusarg "VECTORS=output/road_4.hex" -testplusarg "MODE=2" -log road_4_sim.log'
cmd /c 'D:\Xilinx\Vivado\2018.3\bin\xsim.bat road_marking_sim -runall -testplusarg "VECTORS=output/road_5.hex" -testplusarg "MODE=1" -testplusarg "SWITCH_MODE=1" -log road_5_sim.log'
```

Each run must contain `PASS: 1843200 pixels` and no fatal errors. Candidate pixel
counts must match `output/results.json`. Compilation alone is not a test pass.

Verified locally on 2026-10-16:

| Fixture | Mode | Compared pixels, including blank frame | White | Yellow |
| --- | --- | --- | --- | --- |
| road_1 | overlay | 1,843,200 | 11,179 | 320 |
| road_2 | mask | 1,843,200 | 1,850 | 17,242 |
| road_3 | base | 1,843,200 | 7,150 | 26,216 |
| filter_fixture | mask | 1,843,200 | 3,291 | 21,700 |
| precision_fixture | switching | 1,843,200 | 2,004 | 816 |

All five RTL runs passed, totaling 9,216,000 compared pixels. Candidate counts
are not precision/recall scores. The autumn preview retains the central double
yellow and outer white markings, but still contains some false/missed candidates.
Local verification used separate snapshots for simultaneous runs and distinct
waveform/log names; the commands above reproduce them sequentially.

## Build And Board Check

Run `build.bat` and inspect `report_timing/hdmi_ddr_ov5640_top.rtr`, including
unconstrained inputs. The tool's `All Constraints Met` summary only applies to
the constraints present; camera input-delay warnings remain a separate issue.
The final ROI build uses multi-corner hold repair in `flow.tcl`, with a
200 ps repair target and up to 16 iterations, and reports `All Constraints Met`.
Constraints were not relaxed. Its log is `build_road_markings_roi23.txt`.
Camera input-delay warnings still remain.
These results do not certify the unconstrained camera interface.

The named test image is `bitstreams/5_road_roi23_precision_cmos1.sbit`; the build's
original output is `generate_bitstream/hdmi_ddr_ov5640_top.sbit`. Older named
bitstreams, including versions 3 and 4, are not overwritten.

For each fixture, fill the camera view with the road, check marking alignment
and missed/false candidates, then move the camera and change illumination.
Also test an indoor/no-road scene. Do not use candidate colors as evidence of
lane semantics or deploy the output for real vehicle control.
