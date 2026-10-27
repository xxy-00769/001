# Stage 2: Actual Video Buffer / DDR Integration

## Frozen After Architecture Change

The user's latest request supersedes the old stage sequence: use FPGA + external
ARM, complete the competition's functional loop first, and perform hardware /
interface confirmation as the new stage 1. This directory is historical research,
not a prerequisite for the external-ARM route. Do not resume its simulations
without a concrete need and an explicit stage decision.

The agent-owned run `runs/20261017_215255_512_s1_candidate/` was stopped while
still incomplete when the direction changed. Its log is retained; it is NOT a
pass or an RTL failure verdict. Earlier failed runs and isolated candidate fixes
are retained, with no changes copied into the main RTL. No bitstream was made.
`verification.json` records partial evidence only; stage acceptance remains false.
See `../../reports/阶段一_FPGA_ARM架构核对_2026-10-17.md` for current work.

Date: 2026-10-17 (Asia/Shanghai). Isolated continuation of stage 2.
No road model, recognition feature, bitstream, JTAG download or Flash operation.
The existing stage-1/stage-2 evidence and all main RTL remain unchanged.

## Acceptance Defined Before Results

- Full 1280x720 RGB565 frames, 1650x750 total timing, including blanking.
- Zero mismatched, missing, repeated or unknown video pixels after explicit
  first-frame prefill; frame identity is part of the pixel pattern.
- Zero native video write mismatches, including burst boundaries.
- No out-of-window memory access; video and accelerator use separate windows.
- Both circular memories hold 8192 RGB565 pixels. Observed occupancy must stay
  within [0,8192], with positive read margin while displaying.
- Each line transfer must complete before the next line demand. The nominal
  line period is 4444.44 UI cycles (100 MHz UI, 37.1265 MHz pixel clock).
- Accelerator requests must complete during the stated video load. Acceptance
  limit is one line period per request, including deliberately held responses.
  This is a measured workload gate, not a universal starvation guarantee.
- Clock/phase variation, gapped native data, reset and cancel lifecycle tests
  must pass before the stage can be accepted.
- The existing encrypted DDR regression remains separate evidence. This new
  BFM suite alone cannot certify the full controller/PHY path or a board.

`verification.json` will distinguish partial evidence from full acceptance.
Do not count a simulation that only compiles or emits `RESULT` as a pass.

## Actual Path

```text
RGB565 generator / camera-domain timing
  -> isolated fram_buf / wr_buf candidates
  -> wr_fram_buf: 4096x32 write / 512x256 read, independent clocks
  -> wr_cmd_trans -> wr_ctrl
  -> road_ddr_bridge v_* -> native-channel memory BFM
  -> road_ddr_bridge v_* -> rd_ctrl / wr_cmd_trans
  -> rd_buf / rd_fram_buf: 512x256 write / 4096x32 read
  -> RGB565 output / display-domain timing
```

The vendor RAM wrappers, implementation RTL and installed GTP_DRM18K primitive
models are used directly. They are NOT replaced with ideal FIFOs. The actual
design uses circular dual-port memories, not asynchronous FIFOs with full/empty
ports. The testbench must therefore measure their production/consumption budget.
Clock-domain event synchronization and independent ping-pong counters are also
the actual project implementation, not a new idealized frame queue.

Each RGB565 line is 80 native 256-bit beats, split into five 16-beat bursts.
Native addresses are 32-bit words: line stride 640; frame banks begin at
0 and 0x00400000 (0 / 16 MiB). Live data in each bank is 1,843,200 bytes.
Accelerator traffic starts at native address 0x00800000 (32 MiB).
The BFM rejects video accesses outside either exact frame allocation.

The original wrapper's WVALID/B/RREADY signals are not used to invent native
responses. The bridge forwards native data-request/last to the real wr_ctrl;
read returns are unstallable. Accelerator writes require bridge readback.

## Reproduce

From the project root:

```powershell
./experiments/road_video_ddr_20261017/tests/run.ps1 -Scenario 0 -Frames 3
./experiments/road_video_ddr_20261017/tests/run.ps1 -Scenario 1 -Frames 3
./experiments/road_video_ddr_20261017/tests/run.ps1 -Scenario 2 -Frames 3
./experiments/road_video_ddr_20261017/tests/run_control.ps1
```

Default integration runs use this experiment's framebuffer/control candidates.
`-OriginalControl` selects all four original project modules. Main project files
are never edited. Candidate changes are:

- Qualify `rd_cmd_done` with the actual `read_en` final-beat return.
- Start `rd_buf.wr_line` at zero: the VS prefetch itself increments it. Starting
  at one suppresses the final prefetch and loses the last display line.
- Clear framebuffer `init_done`, read-bank counter, capture enable and frame
  interrupt enable on common reset, so previous initialization cannot survive it.

The `fram_buf.v` copy had legacy GBK comment bytes; its encoding was converted
to UTF-8 to enable the isolated edit. No main-project encoding was changed.

- Scenario 0: matched pixel clocks, native command/read stalls, contiguous writes.
- Scenario 1: additionally gapped native write-data requests.
- Scenario 2: display clock about 2% faster, preserving active geometry.
- Scenario 3 (`-Frames 1`): complete video epoch, common reset, fresh tagged
  frame identities and full prefill/output again.

Every run gets a fresh timestamped directory. No prior logs are overwritten.
ModelSim uses `-novopt`, with only its deprecation warning suppressed.
Vendor missing-WWCONF warnings remain visible. A required GTP_GRS global reset
instance is supplied in the testbench; the first elaboration failure is retained.
No vendor IP has been patched to get the simulation to run.

The capture/verification script checks both prior stage manifests, their
source/evidence hashes and the existing protected-main-file manifest. It also
captures all main source files and this experiment's test sources. A changed
input invalidates that run's evidence.

## Remaining Scope

This is an integration experiment, not a complete stage-2 acceptance yet.
Reset/cancel/fault recovery, a continuous full vendor-DDR integration run,
bounded recovery on missing returns, and actual camera clock/phase limits still
need evidence. Main-engine frame publication/reset and ring ownership must not
be assumed correct merely because prior synthetic v_* bursts passed.

## Reproduced Completion Bug

The directed 80-return test deliberately waits 17 UI clocks before returning
the last beat. Original `wr_cmd_trans` asserts line completion whenever its
data counter equals 79, including clocks with no data return. The downstream
`rd_buf` increments the line address on every completion clock.

Recorded in `runs/20261017_212959_738_control/`:

| Implementation | Completion Clocks | Without A Data Return |
| --- | --- | --- |
| Original | 20 | 19 |
| Candidate | 1 | 0 |

The candidate is a minimal isolated fix, not a replacement of the v4 baseline.
This unit test does not by itself accept the whole video path. Early full-frame
runs also exposed a testbench warm-up mistake (first VS before reset CDC settled);
the corrected test waits eight camera clocks after DDR enable. Those early
results are retained but must not be used as clean full-frame comparisons.

## Reproduced Last-Line Bug

`runs/20261017_213033_240_s0_candidate/` uses only the completion fix, before the
last-line/reset corrections. Three full output frames contain exactly 3840 bad
pixels, all in row 719 (zero-based). All 3,686,400 captured input pixels are
correct at native writes. The display ring's cumulative balance reaches -3840.
This is a retained failed integration result, not a passed stage.

At frame start, `wr_rst` makes the old read-line counter one. The registered
VS prefetch trigger then increments it again. The request for row 719 is
suppressed by `wr_line != V_NUM`. The candidate starts the counter at zero.
Subsequent verification must demonstrate all 720 rows, not mask out row 719.

The early test sent all accelerator work during startup blanking. Final tests
spread the same tagged write/read pairs across the full video duration and
check that at least half the request handshakes occur during active video.
Early timing/occupancy figures are not substituted for this final workload.
