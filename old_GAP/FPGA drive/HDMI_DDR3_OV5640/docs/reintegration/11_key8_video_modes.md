# V4 KEY8 Video Modes

Date: 2026-10-19. Scope: six frame-atomic HDMI diagnostic views, not a new
semantic-recognition, crop/resize or network release. User programs the board.

## Behavior And Connections

Boot selects original RGB565. Each debounced press advances:

| Presses modulo 6 | View | Meaning |
| --- | --- | --- |
| 0 | Original | Exact buffered color, no candidate paint or HUD |
| 1 | Grayscale | Existing RGB luma, packed back into RGB565 |
| 2 | Filter | Existing 3x3 grayscale median, replicated image borders |
| 3 | Sobel | Saturated absolute horizontal + vertical gradient |
| 4 | Color candidates | Existing supported white/yellow road-ROI candidates, green/cyan paint; no HUD |
| 5 | Legacy diagnostic | Candidate paint plus existing lane geometry/HUD and zebra diagnostic |

The last mode is an old heuristic diagnostic, not validated final road semantics
or Orange Pi driving decisions. A scene with no candidates can look unchanged
in mode 4. Mode 2 remains grayscale; it is not a color denoiser.

`video_mode_key.v` adapts the archived v11 release/repress debounce behavior.
It uses 1,000,000 reference cycles (20 ms at configured 50 MHz), requires a
stable release before another event, and never auto-repeats a held key.
The six-state Gray ring 000/001/011/010/110/100 crosses through two video-domain
registers. `img_proc` freezes the request at its buffered frame header, then
freezes HUD enable again at the delayed lane-output header. Very fast successive
presses between frame headers may only display the latest requested view.
Capture recovery resets the receiving pipeline but retains the reference-domain
request; full FPGA reset returns to original.

Selected path:

```text
CMOS1 -> existing RGB565 normalization -> img_proc row/window buffer
  -> selected base + aligned lane pipeline + optional diagnostic overlays
  -> selected RGB/DE/VS and aligned display frame ID/acquisition time
  -> existing V3 complete-frame DDR ownership -> existing HDMI
```

Independent `clean_rgb/de/vs` and clean frame tags are still generated before
diagnostic paint at the RTL interface; they are not an additional external
port/cache, and unused parallel signals may be pruned by synthesis.
However, **this release's single DDR display cache contains
the selected diagnostic view in modes 1..5**, not simultaneous clean-color and
feature frames. In mode 0 its pixels are exact clean color, with the same
additional lane-pipeline control delay used by every mode. Future color
transport must explicitly use the clean branch or a separately managed cache;
it must not assume the current selected display cache is always color.

Production changes: `source/rtl/video_mode_key.v`, `img_proc.v`,
`hdmi_ddr_ov5640_top.v`, plus its source entries in `flow.tcl` and
`HDMI_DDR3_OV5640.pds`; the FDC adds only KEY8. No PLL, DDR IP/parameters,
S3a/S3b repair or old archive is replaced.

## KEY8 Evidence

Matching archived hardware evidence (read-only):

- Workspace-parent `_archive/experiments/v11_lane_interaction_20261018/`
  `hardware_review/manual_pages_32_33_text.txt`: manual physical pp32-33,
  printed pp31-32, table 3-8 gives KEY8=H17 and active-low user keys.
- Same directory `README.md`, `vendor_key_led_test.fdc` and recorded user
  confirmation bind the supplied MES50HP baseboard, A3V3 pull-up and LVCMOS33.
  The vendor single-key example alone does not verify every key.
- Current FDC had no H17 allocation. New input `key8_n` is H17/LVCMOS33/3.3V.
  This is documentation/configuration evidence, not a new voltage measurement.

## Checks And Evidence

Full image/DDR RTL simulation: PASS. Evidence directory:
`E:/FPGA drive/tmp/video_modes/20261019_203915_564_752fce00/`.
`result.json`, `inputs_before.json`, `inputs_after.json`, `commands.json` and
per-test logs bind this result to the current inputs, unchanged during the run.

| Check | Actual result |
| --- | --- |
| Key controller | 55 directed checks, zero errors |
| Runtime image views | 8 complete 1280x720 frames / 7372800 selected pixels, zero errors; another 7372800 independent clean pixels exact |
| Candidate isolation | 6096 candidate paint pixels, zero upper-ROI/HUD changes in mode 4 |
| Legacy diagnostic visibility | Each mode-5 frame: 6152 lower-ROI changed pixels and 11856 upper-ROI/HUD changed pixels |
| Native DDR integration, selected original view | 6 complete frames / 5529600 exact pixels; each last row has 1280 correct pixels |
| Existing owner fault/recovery coverage | 230400 write beats, 345680 read beats, 3 published frames, 1 malformed raw frame rejected, 2560 fault-black pixels |
| Static binding / whitespace | Selected RGB/DE/VS/tag bindings and unique H17 assignment pass; `git diff --check` passes with CRLF-aware settings |

The initial run `20261019_203853_775_a6786e2d` failed at Verilog compilation:
`lane_vs` was referenced before its declaration. The declaration was moved
above its use; the complete current run above then passed. Neither an initial
compile failure nor a software reference is counted as an RTL test pass.
ModelSim warns about unconnected observation outputs in testbenches and the
unchanged generated RAM primitive's WWCONF port; these are retained in logs.

Synthesis review found that PDS automatically recoded `mode_gray` into six
one-hot state bits. That invalidated the intended registered Gray CDC source.
The first build `20261019_204410_416_ea815445` was deliberately stopped after
synthesis; its exit -1 and intermediate artifacts are not a release.
Only this agent's batch build was stopped, not the user's GUI PDS.

`mode_gray` now has `syn_encoding = "original"` per installed
`D:/PDS/PDS_2022.2-SP6.1/doc/ADS_Synthesis_User_Guide.pdf`, section 5.8,
physical pp73-74. This preserves the exact user encoding, rather than asking
the tool to invent another Gray encoding with a possibly different wrap.
Current input-bound evidence is
`E:/FPGA drive/tmp/video_modes/20261019_204949_809_3bc5e988/result.json`:
key RTL was recompiled/retested (55 checks PASS); unchanged video/DDR cases
were reused only after comparing every dependency hash other than the key
module and driver, with original log paths and log SHA256 recorded.
Neither reused video/DDR bench instantiates the key module.

The first reuse attempt `20261019_204853_244_22d121e9` stopped before testing
because the driver's loop used PowerShell's reserved `$input` variable.
Renaming it fixed the evidence check; no DUT behavior was changed for this
driver error.

Replacement full PDS build: PASS, including compile, synthesis, mapping,
placement/routing, multi-corner timing and bitstream generation. Evidence:
`E:/FPGA drive/tmp/v4_key8_video_modes_build/20261019_205011_596_12a24176/`.
Its actual `synthesize/formal.pvf` encoding table preserves all six mappings
000->000, 001->001, 010->010, 011->011, 100->100, 110->110, with exactly three
destination state bits. `device_map/hdmi_ddr_ov5640_top.pcf` confirms
`key8_n LOC=H17 VCCIO=3.3 IOSTANDARD=LVCMOS33`. The release wrapper confirms
both original inputs and copied design inputs stayed unchanged.

Final routed `report_timing/hdmi_ddr_ov5640_top.rtr`: All Constraints Met.

| Clock domain | Slow setup slack (ns) | Fast hold slack (ns) |
| --- | --- | --- |
| sys_clk | +13.186 | +0.239 |
| DDR core | +2.017 | +0.253 |
| CMOS1 16-bit / image processing | +3.070 | +0.201 |
| HDMI pixel | +9.012 | +0.267 |

These are STA results under the existing constraints, not measured video
frequencies/FPS. Existing no-clock warnings in camera configuration and
unconstrained external IO remain. KEY8 is an asynchronous synchronized input,
not a source-synchronous timed input. Broad asynchronous clock groups remain;
this release is not full IO/CDC signoff. No constraints were relaxed to pass.
`wr_cmd_trans.v` still hashes to the accepted S3a value
`2B99C581904A5C61FAA6EA8BF06065482A724A72C01CB4EF56FE86E53443F659`.

### Release

- File:
  `E:/FPGA drive/tmp/v4_key8_video_modes_build/20261019_205011_596_12a24176/V4_KEY8_video_modes_cmos1.sbit`
- Size: 2101696 bytes.
- SHA256:
  `74CDE8193FF3F3FEF4B4A643FF132F7CA16FFF09989E6BCC4448965CBE7887B7`
- Identity/checks: `release.json`, `result.json`, `inputs.json`,
  `simulation_evidence.json`, `recipe.json`, `pds_console.log`, and routed RTR
  in that same build directory.
- Existing PDS entry:
  `E:/FPGA drive/HDMI_DDR3_OV5640/HDMI_DDR3_OV5640.pds`.
  Top: `hdmi_ddr_ov5640_top`, CMOS1 selected, `SELF_TEST=0`.
  The new key RTL is already included in both PDS and `flow.tcl`.
  Reopen/reload the project if the GUI was open before this change; no manual
  source addition is required. The delivered SBIT needs no further compile.

Reproduce the isolated build, without programming:

```powershell
./tools/s4_clean_video/build.ps1 `
  -SimulationResult E:/FPGA drive/tmp/video_modes/20261019_204949_809_3bc5e988/result.json `
  -ReleaseName V4_KEY8_video_modes_cmos1 `
  -OutputParent E:/FPGA drive/tmp/v4_key8_video_modes_build
```

No JTAG scan/configuration, Flash write, hardware test or power-cycle acceptance
was performed. Board acceptance and road-scene diagnostic usefulness remain
pending. Stop after this scoped delivery; crop/resize/network are not started.

Targeted assets:

- `tools/video_modes/key_tb.sv`: asynchronous clocks, bounce/hold/repress,
  wrap, full reset while held, capture-domain reset, one-bit Gray transitions.
- `tools/video_modes/video_tb.sv`: eight full 1280x720 frames, independent
  grayscale/median/Sobel reference, exact original and independent clean
  outputs, visible candidate/diagnostic paint, no HUD in candidate mode,
  mid-frame request changes, first/last row/column, delayed frame tags, reset.
- `tools/frame_ownership/full_frame_tb.sv`: existing native-controller/generated
  line-RAM regression, now with an optional `DISPLAY_PATH=1` parameter.
  Default historical behavior remains unchanged. New runner selects the actual
  delayed display output in original mode, with diagnostics compiled in.
- `tools/video_modes/run.ps1`: unique output directories, hash manifests,
  simulator logs, acceptance markers, top binding and H17 uniqueness checks.
- Existing `tools/s4_clean_video/build.ps1` performs an isolated full PDS build.
  Its old `run.ps1` top-binding check describes V1's direct clean-cache wiring;
  it is not the acceptance entry for this selectable-view release.

Native DDR-port memory BFM simulation does not validate the physical PHY.
Tests do not establish road-detection accuracy, full IO/CDC timing signoff or
on-board key/HDMI operation.

## User Board Acceptance

Use the new V4 named SBIT recorded below, not an older generic output.
Keep the already-working CMOS1 camera and HDMI output wiring; use onboard KEY8,
not the REST/reload key. No external button wiring is needed.

1. Boot: smooth original color, no lane paint or HUD.
2. Press/release KEY8 at roughly one-second intervals through all six views.
   Grayscale/filter/Sobel should be plainly different; candidate paint depends
   on the scene. Legacy mode should restore the old diagnostic overlay.
3. Hold KEY8 for two seconds: only one advance. Release, then press: one more.
4. Cycle back to original: no residual HUD, pixel shifts, missing bottom row,
   split-mode frames, freezing or persistent black screen.

Send which press/mode fails, a short video of the cycle, and the loaded SBIT
filename/hash. For display faults include whether KEY8 still changes the view
and whether reset recovers it. No unavailable internal counters are requested.
