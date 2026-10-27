# V2 Single-Source Capture Status And Recovery

Date: 2026-10-19. Scope: first incremental release on the user's fixed
FPGA/Orange Pi division. This is not completion of all FPGA functionality.

## Implementation

- New `source/rtl/video_capture_status.v` observes the selected, normalized
  RGB565 source's VS/DE **before** `img_proc`. The latter counts active pixels
  into a fixed raster and could otherwise hide short/long physical rows.
- Checks every DE segment against configured 1280 pixels and every frame
  against 720 segments. Equal total pixel count does not excuse a short row
  followed by a long row.
- A rising VS opens the first frame; the next rising VS closes it. Repeated
  high VS is not multiple frames. A last DE segment ending on VS is included.
  No DE before the first VS is interpreted as a complete frame.
- Source ID is logical channel 0 for the currently selected camera. Frame ID
  starts at zero and increments at each closing boundary, valid or invalid.
  Source disable, when observed in the video domain, cancels an unfinished frame;
  global reset starts a new
  ID/counter/time epoch. There is no persistent boot/session ID yet.
- Acquisition time is a synchronized sample of a free-running 32-bit
  millisecond counter at source VS opening, not exposure time, absolute time
  or camera synchronization. It wraps modulo 2^32 milliseconds. Reference
  frequency is configured as 50 MHz, matching the current 20 ns system-clock
  constraint; actual timing remains a hardware measurement.
- A request/acknowledge mailbox transfers a stable completed-source report
  into `sys_clk`. Acquisition does not wait for status consumption. If the
  mailbox is busy, the report is omitted, the drop counter advances and later
  IDs reveal the gap; good/bad totals continue to include those frames.
- With the source ready, 250 reference-clock milliseconds without a completed
  source report asserts timeout, clears health and resets `img_proc`. The
  watchdog works even if the pixel clock stops. This is a frame-boundary
  watchdog, not a measured 250 ms physical guarantee or an I2C reinitializer.
- Monitoring remains alive during timeout. A returning closing boundary clears
  timeout, even if its geometry is bad. A frame touched by timeout is marked
  invalid; subsequent complete frames restore health. Processing reset asserts
  asynchronously through the release synchronizer and deasserts after two
  pixel-clock edges. Existing `img_proc` then waits for an input VS.
- HDMI synchronization remains running once the old framebuffer starts it.
  RGB is black while source health is false. After health returns, the display
  guard waits for two HDMI VS rising edges before showing pixels. Original
  heartbeat and configuration LEDs keep their existing meaning.

### Internal Status Layout

This is an internal RTL tuple, **not a frozen network protocol or a currently
readable host register bank**. The top retains it with `syn_keep`; no user
should be asked to read these fields through a nonexistent interface.

| Snapshot bits | Meaning |
| --- | --- |
| 31:0 | Completed source frame ID |
| 63:32 | Source opening time in relative milliseconds |
| 95:64 | Active pixels, saturating on overflow |
| 111:96 | DE segments, saturating in the running counter |
| 119:112 | Error bitmap |
| 127:120 | Logical source ID |
| 159:128 | Good-frame total, modulo 2^32 |
| 191:160 | Bad-frame total, modulo 2^32 |
| 223:192 | Omitted mailbox reports, modulo 2^32 |
| 255:224 | Reserved zero |

Errors: bit 0 wrong row width; bit 1 wrong row count (computed at closing VS);
bit 2 DE overlapping VS; bit 3 pixel/row/column counter saturation; bit 4 frame
touched by timeout; bits 5..7 reserved. The top also retains a separate timeout
episode counter and a one-reference-cycle snapshot-valid strobe.

The Gray timestamp passes through two video-domain registers. Mailbox data
stays fixed until acknowledged; request/acknowledge use two-stage synchronizers.
Functional asynchronous-clock simulation does not prove metastability MTBF,
Gray-bus physical skew or full CDC/reset signoff under the existing FDC.
Source-ready disable/re-enable is tested with the video clock running. A
disable pulse entirely inside a stopped-clock interval is not a supported
runtime reconfiguration handshake in this version. The current top uses the
camera's configuration-done level, not a user-configurable capture enable;
ordinary clock outage/restart with ready held high is covered by both tests.

## Important Boundaries

The clean RGB/DE/VS tuple still feeds the existing DDR writer. S3a/S3b and
`img_proc.v` are unchanged by this release. There is no new crop, scaler,
network port, feature stream, semantic detection, button function or LED rule.

**Source geometry valid is not DDR frame committed.** The old writer changes
bank at VS and the old reader selects banks from its own VS count; this release
does not fix frame ownership. A partially written frame can still exist in
memory, and valid source geometry alone does not prevent tearing, reader/writer
collision or incomplete-frame publication. HDMI blacking and the two-boundary
wait are display guards, not a proof of memory correctness or atomic recovery.
Do not use the snapshot as the ID of the currently displayed/DDR-read frame.

## Actual Checks

1. Directed RTL, asynchronous 10 ns/14 ns clocks:
   `E:/FPGA drive/tmp/video_capture_status/20261019_192436_269_e2e208c8/`
   `result.json`: PASS, **203 checks, 25 delivered reports**. Coverage:
   configuration gating, continuous valid frames, short/long row,
   same-pixel-total malformed geometry, missing/extra rows, early/held/empty
   VS, DE/VS collision, last-line closure, column saturation and row 65536
   closing on VS (saturated row report, no wrap), stopped pixel
   clock, running clock without VS, timeout recovery, mailbox overload,
   source disable/re-enable, mid-frame global reset and display guard.
   `capture_status_tb/frames.csv` records the actual metadata.
2. Integrated monitor-reset + `img_proc` clean color:
   same run, `capture_full_color_tb/simulation.log`: PASS, **3 x 1280x720,
   2,764,800 pixels**, all RGB values and row lengths correct; three matching
   source reports and no false watchdog timeout. This test does not instantiate
   the DDR controller/PHY or the physical camera.
   `capture_recovery_color_tb/simulation.log` also passes: **8 complete
   32x6 frames** across a stopped pixel clock and a mid-frame global reset.
   All 1600 observed active pixels match, including 1536 in complete frames
   and 64 from explicitly aborted partial frames. No partial frame is
   counted as complete. This exercises the actual reset-connected `img_proc`,
   not only a monitor model.
3. First directed run:
   `E:/FPGA drive/tmp/video_capture_status/20261019_191522_337_725fa3d8/`
   failed the testbench's one-report-per-boundary expectation on immediately
   repeated empty frames. The normal-case driver now allows VS deassertion and
   mailbox acknowledgement; a separate overload case verifies immutable
   pending data, dropped-report count, continued acquisition and frame-ID gaps.
   No production RTL change was made to suppress that expected mailbox drop.
4. `git diff --check` initially flags CRLF as trailing whitespace, including
   preexisting V1 changes. With `core.whitespace` including `cr-at-eol`, the
   check passes. No broad line-ending conversion or user-change cleanup.
5. Original clean-color regression:
   `E:/FPGA drive/tmp/s4_clean_video/20261019_191720_834_f9020953/`
   PASS: six 720p frames / 5529600 pixels, diagnostic-isolation 184320 pixels
   and legacy early-sync 49920 pixels. Its tested `img_proc` and main clean DDR
   bindings remain unchanged by the later status-counter correction.
6. The expanded simulation attempt
   `E:/FPGA drive/tmp/video_capture_status/20261019_192235_778_d7bff43a/`
   could not load its DUT: ModelSim `vopt` reported `VirtualAlloc()` failure,
   exit 12, during the concurrent PDS run. This is a tool-resource failure,
   not RTL coverage or a behavioral PASS. The final PASS above ran after PDS
   exited. No other application was terminated and no pagefile was changed.
7. Initial PDS build
   `E:/FPGA drive/tmp/v2_capture_status_build/20261019_191749_401_0feb157b/`
   completed through Bitstream with existing constraints met, but was correctly
   marked **INVALID_INPUT_CHANGED**, since the source-side row-overflow
   correction was made after the build's isolated copy. Its artifacts are
   preserved; **do not program this earlier image**. The final build uses the
   expanded simulation's current input hashes.

## Final PDS Result

Current-input build:
`E:/FPGA drive/tmp/v2_capture_status_build/20261019_192508_695_fd822c5f/`

- `result.json`: **PASS**. Compile, synthesis, map, PNR, routed timing and
  bitstream artifacts exist. Process exit 0. Original inputs and copied design
  inputs remain unchanged throughout this build.
- `inputs.json`, `recipe.json`, `simulation_evidence.json`, `worktree.patch`
  bind the copied source/IP/FDC/configuration, actual tool, expanded RTL PASS
  and dirty tracked changes. The new untracked production source is included
  in the copied source tree and manifest, not merely named in a Git patch.
- PDS 2022.2-SP6.1, PGL50H-6FBG484, top `hdmi_ddr_ov5640_top`.
- Final `report_timing/hdmi_ddr_ov5640_top.rtr`: multi-corner,
  `Design Summary : All Constraints Met.` Setup and hold failing endpoint
  counts are zero in the reported domains/corners. DDR slow-corner setup
  WNS **2.064 ns**, fast-corner hold WHS **0.121 ns**.
- The PNR log still contains the internal `Hold violation fix failed`
  substep message; it is not deleted or described as absent. Final routed
  STA, not that intermediate sentence alone, supplies the numbers above.
  Existing `STA-3011` no-clock warnings (camera I2C/configuration etc.),
  unused CMOS2 constraints, inferred clock and IO/CDC coverage limitations
  remain. **FullIOSignoff=false**, no FDC changes to hide them.
- `release.json`: **2,101,696 bytes**. SHA256:
  `BFD551B6A89645664C39697DD2439ACF582BB277E1CAD738A310707169901CBF`.
- **Programmed=false, FlashWritten=false, BoardTest=false.**

Only this release is the current V2 handoff:

```text
E:/code/BackupPortal/tmp/v2_capture_status_build/20261019_192508_695_fd822c5f/V2_capture_status_cmos1.sbit
```

## Changed Files

- Added `source/rtl/video_capture_status.v`: source observation, mailbox,
  watchdog, pipeline-reset release and display guard.
- Modified `source/rtl/hdmi_ddr_ov5640_top.v`: instantiate these blocks; gate
  HDMI RGB only, retain clean tuple into the existing framebuffer.
- Modified `flow.tcl` and `HDMI_DDR3_OV5640.pds`: add the one new RTL source.
- Added `tools/video_capture_status/`: three directed/integrated benches,
  unique-output ModelSim runner and README.
- Modified `tools/s4_clean_video/build.ps1`: optional release-name argument;
  old default remains unchanged. No programming action added.
- Added this report and `docs/development/fpga_completion.md`; updated the
  current evidence index `docs/development/project_context.md`.

Preexisting root README, S3a/S3b changes, `img_proc.v`, FDC, PLL/DDR IP,
camera registers, archives, ignored outputs and earlier evidence were not
cleaned or rewritten. Git HEAD remains
`6f68d09149f3fcf3927174887f80cea9225fae50`; no staging/commit was performed.

## Build And Board Handoff

Open `E:/FPGA drive/HDMI_DDR3_OV5640/HDMI_DDR3_OV5640.pds`.
Top remains `hdmi_ddr_ov5640_top`, `SELF_TEST=0`, CMOS1 selected. The new source
is already listed in both this PDS and `flow.tcl`; do not add it twice.
No FDC, pin, PLL, DDR IP or camera-register changes.

The agent builds in an independent directory and does not program JTAG/Flash.
The original generic project bitstream is not the new release. Use only the
release path/hash recorded after a successful current build below.

Keep the existing powered-off wiring arrangement: selected camera remains on
CMOS1, existing HDMI output goes to the monitor, power as before. Ethernet is
not used by this version. Never hot-plug the camera to manufacture a fault.

Manual checks after selecting the exact V2 SBIT:

1. Normal startup can be black briefly while source frames and two HDMI
   boundaries are accepted. It should then show the same clean moving color
   video, without old lane paint or HUD.
2. Run the same scene for at least five minutes. Look for permanent black,
   flicker, repeated blanking, new color errors, displaced rows or frozen image.
3. Power off, wait, then repeat normal startup with the same wiring. For JTAG
   configuration, download the exact V2 image again after power-on: otherwise
   an old Flash image may run instead. This checks restart behavior, not V2
   Flash persistence. No Flash programming is needed for this release check.
4. A controllable-source outage/restart is a separate test only if a safe way
   to stop camera output is available. Covering a lens is **not** loss of
   pixel/frame clock. Do not claim board recovery from only a normal video.

Feedback: exact programmed path or hash, JTAG/Flash choice, time to first image,
whether normal video stays stable, and a short startup/problem recording.
If PDS is rerun manually, send compile errors and final routed timing report,
including warnings/unconstrained coverage rather than only a green status.
The internal counters are not yet readable on the PC.

## Next Required Work

Subsequent user feedback on 2026-10-19: normal video has no apparent problems,
and development may continue. This is user-reported normal-video observation,
not agent programming, independent bitstream readback, watchdog fault testing,
or comprehensive physical DDR acceptance. V3 development is recorded in
`10_frame_ownership_v3.md`.

See `docs/development/fpga_completion.md`. The next data-integrity increment is
DDR completed-frame publication and bank ownership under independent input/
output rates. Configurable crop/downscale follows it. This avoids presenting
monitoring, old feature source files or standalone UDP code as all FPGA work.
