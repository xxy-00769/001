# Version 7: Experimental Crosswalk Candidates

This adds a bounded FPGA feature while the user is remote. It is not a validated
semantic crosswalk detector, pedestrian detector, distance estimate, or driving
decision. The main board comparison remains version 4. Version 6's frame fix
is preserved, and the named version 4/6 binaries must not be overwritten.

## Pipeline

`zebra_detect.v` reads the original centered RGB565 pixels in `img_proc`, before
green/cyan paint is applied. It never consumes the colored lane mask.
`zebra_overlay.v` consumes the existing delayed lane image and the new results.
Neither module buffers or resizes the image. No extra output pipeline clock is
added. Existing lane detection, camera, DDR, and HDMI settings are unchanged.

`img_proc.ZEBRA_ENABLE` defaults to 0. The version 7 top explicitly selects 1.
Only display mode 4 draws the experimental icon and rectangle; other modes
retain their existing pixel output. Setting the parameter to 0 removes the
new modules at elaboration and restores the version 6 processing path.

## Algorithm Contract

- Nominal input: 1280x720 RGB565, rising VS before active pixels, at least one
  idle clock between rows. Coordinates and lengths are 11-bit (width <=2047).
- Separate crosswalk ROI: rows 240..719 and columns 128..1151. This does NOT
  alter the version 4 lane detector's row-405 ROI or crop the displayed image.
- White bars: minimum expanded RGB channel 144, channel spread at most 48.
- Bar width: 12..160 pixels; dark gap: 8..160 pixels with at least eight
  immediately preceding pixels having all RGB channels <=112.
- At least four consecutive bars. Adjacent bar widths differ by no more than
  a factor of two, and their complete span is at least 256 pixels.
- Require at least 12 consecutive qualifying rows; each bounding endpoint may
  drift by at most 32 pixels between adjacent rows. Retain the longest group
  in the frame; equal-length later groups win. Coordinates include endpoints.
- A complete positive frame sets `candidate`. A spatially overlapping positive
  in the next complete frame sets `confirmed`. A negative/malformed frame clears
  both; a partial frame abandoned by a new VS also clears confirmation.
- `result_valid` pulses for one clock after the last row ends (or when a new
  VS abandons an incomplete frame). Geometry and flags stay stable otherwise.
  There is no wall-clock camera-stall watchdog.

The intended initial pattern is repeated longitudinal white bars, viewed from
the approaching road direction. It does not cover all crosswalk orientations or
styles. Shadows, worn paint, large perspective changes, partial occlusion and
small/far-away crossings can be missed. Fences, tiles and other repeated white
objects in the ROI can be false positives. These are engineering thresholds,
not calibrated physical dimensions or measured precision/recall.

## Display Contract

- A 32x24 four-stripe icon at (16,16): grey=no candidate, amber=one candidate
  frame, magenta=two consecutive overlapping candidate frames.
- Confirmed candidates get a one-pixel magenta outline. The interior is never
  filled. Existing green/cyan pixels outside these annotations are preserved.
- Results are latched only at the next output frame start, avoiding mid-frame
  geometry changes. A rectangle belongs to the previous complete input frame;
  a scene change can therefore leave it visible for one more displayed frame.
- The DDR/HDMI path adds its own existing display delay. This test does not
  measure camera-to-monitor latency or prove the physical board's frame rate.

## Reproduction

From the project root:

```powershell
python tests/zebra_fixtures.py
```

This creates six unannotated 1280x720 board cards under `tests/output/zebra/`.
It also uses the unchanged version 4 integer model to generate the expected
lane-painted pixels for the full-pipeline positive test. Cards are synthetic
functional checks, not representative accuracy data.

From `tests`, using the installed Vivado simulator:

```powershell
D:\Xilinx\Vivado\2018.3\bin\xvlog.bat --sv ../source/rtl/zebra_detect.v ../source/rtl/zebra_overlay.v ../source/rtl/lane_detect.v ../source/rtl/img_proc.v zebra_detect_tb.v zebra_overlay_tb.v zebra_road_tb.v img_proc_zebra_tb.v img_proc_overlay_tb.v
D:\Xilinx\Vivado\2018.3\bin\xelab.bat zebra_detect_tb --O3 -s zebra_detect_v7
D:\Xilinx\Vivado\2018.3\bin\xsim.bat zebra_detect_v7 -runall -log zebra_detect_v7.log
D:\Xilinx\Vivado\2018.3\bin\xelab.bat zebra_limits_tb --O3 -s zebra_limits_v7
D:\Xilinx\Vivado\2018.3\bin\xsim.bat zebra_limits_v7 -runall -log zebra_limits_v7.log
D:\Xilinx\Vivado\2018.3\bin\xelab.bat zebra_road_tb --O3 -s zebra_road_v7
D:\Xilinx\Vivado\2018.3\bin\xsim.bat zebra_road_v7 -runall -log zebra_road_v7.log
D:\Xilinx\Vivado\2018.3\bin\xelab.bat zebra_overlay_tb --O3 -s zebra_overlay_v7
D:\Xilinx\Vivado\2018.3\bin\xsim.bat zebra_overlay_v7 -runall -log zebra_overlay_v7.log
D:\Xilinx\Vivado\2018.3\bin\xelab.bat img_proc_zebra_tb --O3 -s img_proc_zebra_v7
D:\Xilinx\Vivado\2018.3\bin\xsim.bat img_proc_zebra_v7 -runall -log img_proc_zebra_v7.log
D:\Xilinx\Vivado\2018.3\bin\xelab.bat img_proc_overlay_tb --O3 -s img_proc_v7_disabled
cmd /c 'D:\Xilinx\Vivado\2018.3\bin\xsim.bat img_proc_v7_disabled -runall -testplusarg "VECTORS=output/road_4.hex" -log img_proc_v7_disabled.log'
```

Check PASS lines and absence of Fatal/Error, not only process exit codes.
`img_proc_zebra_tb` also writes a P6 PPM of the confirmed positive output at
`tests/output/zebra/rtl_confirmed.ppm`. This is RTL simulation, not a board photo.

## Test Inventory

- Detector: positive/negative colors, broad white area, two lane lines, ROI,
  minimum bar/gap widths, short support, final-row support, row discontinuity,
  frame-to-frame overlap, malformed row, interrupted frame, blanking and reset.
- Full-width limits: seven cases cover maximum width/gap and exact minimum
  span, plus one-pixel violations and three-bar rejection. Total detector cases: 30.
- Existing road photographs: all three produce no crosswalk candidate, across
  2,764,800 input pixels. These few negatives are not an accuracy benchmark.
- Overlay: 76,800 compared pixels; same-cycle VS/result, frame-frozen geometry,
  disabled output, no filled rectangle, and blanking pass-through.
- Full pipeline: 4,608,000 expected pixels over three positive and two negative
  frames; independent version 4 paint oracle, result coordinates, confirmation,
  one-frame display delay, and clearing without reset. Row gaps vary from 1..3.
- Feature disabled: 1,843,200 expected pixels using the existing fourth fixture
  followed by a blank frame. RGB, Gaussian luma, ROI and paint counts checked.

All six simulation runs passed on 2026-10-16. The confirmed RTL PNG was visually
checked: icon and thin boundary render correctly, with no region fill. No real
crosswalk-positive photo was supplied or used for accuracy evaluation.

All board observations are still pending. Timing/build evidence and the exact
named artifact are recorded in `../bitstreams/7_zebra_acceptance.md` after build.
