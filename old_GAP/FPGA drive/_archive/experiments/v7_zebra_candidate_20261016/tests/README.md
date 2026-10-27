# Road-Marking Regression

Version 7 adds an opt-in, independent crosswalk-candidate detector and a small
frame-frozen annotation. See `ZEBRA.md` for its contract, limitations and tests.
The current board top enables it; `img_proc` defaults it off so the regressions
below retain their original expectations. Lane RTL and its model are unchanged.
The named version 4/6 bitstreams are retained; current generic build outputs
belong to version 7. No version 7 board observation is available yet.

Active baseline: `bitstreams/4_road_markings_filtered_cmos1.sbit`.
On 2026-10-16 the user rejected version 5 after board testing (excessive green
overlays and a blurry image). Its cause remains undiagnosed. Changed sources,
tests, outputs, and reports were archived under
`experiments/v5_roi23_rejected_20261016/` before restoring version 4 behavior.
Neither named bitstream was overwritten. Working RTL now additionally contains
the version 6 frame-buffer fix described below; the detector and reference
model remain version 4. Version 4 stays the board comparison baseline.

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
The original baseline switch did not rebuild or program the board. The later
frame fix is built separately as version 6; current generic PDS outputs belong
to that build, not the retained version 4 binary.
The rejected version 5 named binary is retained for comparison, not recommended.

For each fixture, fill the camera view with the road, check marking alignment
and missed/false candidates, then move the camera and change illumination.
Also test an indoor/no-road scene. Do not use candidate colors as evidence of
lane semantics or deploy the output for real vehicle control.

## Version 6 Frame Integrity Fix

The user's monitor photo showed candidate colors on buildings, trees, and UI
text. Investigation reproduced a separate deterministic pipeline defect: the
old whole-line-period RAM address wraps every 4096 clocks during long blanking,
replaying old DE/pixels. It also fails to explicitly emit the last image row.
The legacy 12-row probe produced 20,480 pixels instead of 15,360 in its first
frame, then emitted 2,560 stale pixels after a frame sync with no new input.
See `img_proc_frame_before.log`. This demonstrates a stream defect, but does
not prove it is the sole cause of all false candidates or photographic blur.

`img_proc.v` now rotates three active-pixel row banks. The two completed banks
are read while the third receives the current row; read-during-write data from
the write bank is not used. RGB and the 3x3 Gaussian window share a center.
All borders are replicated. A single final-row drain completes each frame,
even if input VS has already begun the next frame. An output frame pulse is
generated immediately before the first buffered output pixel. It is a one-clock
marker for the existing frame writer, not a copy of the camera VS pulse width.
The configured stream is 1280 x 720, with at least one blank clock between rows.
Malformed/truncated camera frames are not part of this regression contract.

No changes were made to `lane_detect.v`, camera settings, top-level routing,
timing constraints, or the version 4 model. Whole-pipeline latency includes the
line lookahead; 119 clocks remains the latency of `lane_detect` alone.

New tests:

- `img_proc_fullframe_tb`: three distinct 1280 x 720 frames, variable horizontal
  gaps, long vertical gaps, exact RGB preservation and frame pixel counts.
- `img_proc_early_sync_tb`: three 13-row frames with VS immediately after the
  last active row and only one clock after the VS pulse before the next input.
  This exercises overlapping old-row drain/new-frame input and bank rotation
  across heights not divisible by three.
- `img_proc_overlay_tb`: raw RGB from a reference vector fixture passes through
  `img_proc` and `lane_detect`. Every prepared RGB/luma sample, ROI coordinate,
  output RGB/mask, frame count, and upper-ROI exclusion is checked. A following
  blank frame tests stale history without reset.

From `tests`, compile and run with the same Vivado simulator:

```powershell
D:\Xilinx\Vivado\2018.3\bin\xvlog.bat --sv ../source/rtl/lane_detect.v ../source/rtl/img_proc.v img_proc_frame_tb.v img_proc_overlay_tb.v
D:\Xilinx\Vivado\2018.3\bin\xelab.bat img_proc_fullframe_tb --O3 -s img_proc_fullframe_v6
cmd /c 'D:\Xilinx\Vivado\2018.3\bin\xsim.bat img_proc_fullframe_v6 -runall -log img_proc_fullframe_v6.log'
D:\Xilinx\Vivado\2018.3\bin\xelab.bat img_proc_early_sync_tb --O3 -s img_proc_early_sync
cmd /c 'D:\Xilinx\Vivado\2018.3\bin\xsim.bat img_proc_early_sync -runall -log img_proc_early_sync.log'
D:\Xilinx\Vivado\2018.3\bin\xelab.bat img_proc_overlay_tb --O3 -s img_proc_overlay_v6_3
cmd /c 'D:\Xilinx\Vivado\2018.3\bin\xsim.bat img_proc_overlay_v6_3 -runall -testplusarg "VECTORS=output/road_3.hex" -log img_proc_overlay_v6_3.log'
D:\Xilinx\Vivado\2018.3\bin\xelab.bat img_proc_overlay_tb --O3 -s img_proc_overlay_v6_4
cmd /c 'D:\Xilinx\Vivado\2018.3\bin\xsim.bat img_proc_overlay_v6_4 -runall -testplusarg "VECTORS=output/road_4.hex" -log img_proc_overlay_v6_4.log'
```

Final-source RTL regression passed on 2026-10-16:

| Test | Compared pixels | Result |
| --- | --- | --- |
| Three full RGB frames | 2,764,800 | Exact RGB and frame counts |
| Early VS, three 13-row frames | 49,920 | No dropped or replayed pixels |
| Road 3 plus blank frame | 1,843,200 | White 11,987; yellow 29,548 |
| Width-filter fixture plus blank frame | 1,843,200 | White 3,339; yellow 21,800 |

Total: 6,501,120 compared pixels. The two overlay cases also compare all prepared
RGB/luma samples and ROI coordinates, not just candidate counts. Final logs are
`img_proc_fullframe_v6.log`, `img_proc_early_sync.log`,
`img_proc_overlay_v6_3.log`, and `img_proc_overlay_v6_4.log`.

The final build log is `build_frame_integrity_v6_final.txt`.
The full build completed and its 2026-10-16 22:41:03 timing report states
`All Constraints Met`; existing camera input-delay warnings remain unresolved.
The retained test artifact is `bitstreams/6_road_framefix_v4_cmos1.sbit`, SHA256
`599C5A26752885DA38A8A8ECCA0D3FB53F3CA30854753DF0F0E20D4C83B942B9`.
Final sources, regression logs, and the report are archived under
`experiments/v6_framefix_20261016/` for traceability.
The earlier `build_frame_integrity_v6.txt`
and `*_fixed*.log` runs precede the early-VS refinement and are not the final
version 6 artifact. No board programming is performed automatically.

These tests cover the image-processing RTL, not a physical camera, DDR controller,
or HDMI transmitter. Compare the separately named version 6 test bitstream
against retained version 4 using the same scene, framing, focus, and lighting.
