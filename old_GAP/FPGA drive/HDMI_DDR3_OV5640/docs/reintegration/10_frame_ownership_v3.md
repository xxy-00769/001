# V3: Completed-frame DDR ownership

Date: 2026-10-19. Scope: the next FPGA data-integrity increment after V2.
The user reports V2 normal video has no apparent problems. That is a normal
video observation, not independent readback, fault injection or full hardware
acceptance. This round changes code, runs targeted RTL checks and builds in
PDS. The user alone performs hardware programming.

## Implementation

`source/rtl/frame_buffer_owner.v` manages the existing two banks (native
address bit 22). It does not add a third bank or change DDR geometry/IP:

- A reserved write bank is offered using a synchronized grant toggle. The
  video side accepts only at the buffered clean-color frame marker.
- A video-domain end descriptor contains frame ID, acquisition time and
  geometry validity. It also requires the matching raw-source result from
  `video_capture_status`, before `img_proc` can normalize malformed rows.
- A bank is published only after a good descriptor, 720 issued line commands,
  720 completed line commands, no overlap and a CDC drain interval.
- A pending bank cannot be overwritten. At an output frame boundary, it can
  replace the current read bank only when no native read is outstanding.
- When both banks are occupied, new input frames are dropped as whole frames.
  Without a new pending frame, display repeats the last complete frame.
- Native writes already in flight are drained even for an aborted/bad frame.
  Only the legacy write buffer is reset between allocations. The shared DDR
  command controller is not reset to abandon a transaction.
- Outstanding reads pin their bank across early output frame boundaries.
  That display frame is disabled; an idle later boundary can recover. A
  per-row completion check blacks from an unavailable row through frame end;
  already transmitted earlier rows cannot be retracted.

`img_proc.v` now carries frame tags through its actual buffered-color marker,
not from the current raw source ID. `video_capture_status.v` provides local
video-domain opening tags and closing verdicts independently of its bounded
reference-domain report mailbox. The main top connects these tags/verdicts.

`fram_buf.v` overrides only the old logical bank bits in native addresses.
It keeps the generated line RAMs and native command controllers. Its startup
`init_done` now means a first complete frame was committed, synchronizes to
the output clock and clears on DDR reset. HDMI timing remains unchanged.
`wr_buf.v` adds the line-event observation and isolated-reset cleanup;
`rd_buf.v` adds a frame-event output. The S3b line-zero reset is preserved.
S3a `wr_cmd_trans.v` remains SHA256
`2B99C581904A5C61FAA6EA8BF06065482A724A72C01CB4EF56FE86E53443F659`.

The root README/user changes and previous outputs/archives are preserved.
HEAD remains `6f68d09149f3fcf3927174887f80cea9225fae50`. No staging or commit.
The only comment-encoding cleanup changes two GBK full-width colon marks in
`fram_buf.v` to ASCII so the patch tool can read the file.

## Targeted RTL Evidence

New entry: `tools/frame_ownership/run.ps1`. Each run records SHA256 inputs,
commands, ModelSim logs and full row evidence in an independent directory.
All `tmp/...` paths in this report are relative to the workspace entrance
`E:/FPGA drive`, not the Git root.
It uses production source-monitor/color/ownership logic, native controllers,
generated write/read line RAMs and Pango primitive models. The external DDR
response is a bounded two-bank memory BFM, **not the physical DDR PHY**.

1. `tmp/frame_ownership/20261019_195135_946_5b27f1d8`: failed second capture.
   First complete frame passed. The stimulus resumed from a display-clock
   edge without aligning to the source driving edge; the first input pixel
   could be lost. Added a source negative-edge alignment in the bench, not a
   DUT patch or changed pixel oracle.
2. `tmp/frame_ownership/20261019_195351_376_0c1b0d30`: PASS with inputs stable.
   38 ownership checks; 5 complete output frames / 4608000 exact pixels,
   288000 returned native beats, 3 published frames and 1 rejected raw-invalid
   frame. Pending-frame drop, repeat, concurrent unequal-clock capture/display,
   full 720 rows and all 1280 last-row pixels are covered.
3. `tmp/frame_ownership/20261019_195720_130_de09e3e8`: supplemental PASS
   before the registered-reset refinement. 38 checks; 6 full output frames /
   5529600 exact pixels, 2560 fault-output black pixels; committed ID/time,
   outstanding-read bank pinning and next-boundary recovery checked.
   Native beats: 230400 writes and 345680 reads (six complete frames plus an
   80-beat drained read). Three publications, one rejected malformed frame.
4. Source review then replaced a combinational multi-bit-state reset decode
   with a dedicated registered writer-release signal, to avoid a potential
   asynchronous local-reset glitch. No observed board failure is claimed.
   Added an assertion forbidding isolated reset during a native write.
   Final-input regression:
   `tmp/frame_ownership/20261019_200246_818_fa473b4c/result.json` **PASS**,
   input SHA256 unchanged before/after. `unit.log`: 38 checks, zero errors.
   `simulation.log` / `rows.csv`: 6 full frames, 5529600 exact pixels,
   all 4320 output rows including six complete row-719 checks; 2560 correctly
   black pixels during the read fault; ID/time checks pass. Native beat totals
   remain 230400 writes / 345680 reads; 3 published / 1 rejected frames.

The unchanged V2 monitor/clean-color recovery paths were rerun:
`tmp/video_capture_status/20261019_195955_323_303059ce/result.json` PASS;
203 checks / 25 reports, three 720p color frames / 2764800 exact pixels,
eight small recovery frames / 1600 checked pixels including aborted pixels.
Their relevant production inputs are unchanged by the reset refinement.

The malformed source case deliberately shortens one raw row and lengthens the
next by one pixel, keeping total source pixels unchanged. A correct total
pixel count or `img_proc` output raster alone cannot let it publish.
Good-frame color oracle stays frame/row/column dependent; invalid frames are
checked for rejection, not relabeled as acceptable images.

ModelSim reports existing generated RAM bit-select/port warnings; these are
retained, not suppressed by changing IP. Assertions and completion signatures,
not process exit status alone, decide PASS.

## Build Status

`tmp/v3_frame_ownership_build/20261019_200052_074_0410489f` was deliberately
cancelled by the agent during synthesis after identifying the reset-decode
risk above. Only the positively identified agent-owned PDS process tree was
stopped; `agent_cancelled_processes.json` records it. Its result is ERROR /
process exit -1, not a successful build or a release. No source was changed
while that process ran. Previous artifacts remain intact.

Replacement isolated PDS build **PASS**:
`tmp/v3_frame_ownership_build/20261019_200533_451_40284dab/result.json`.
Compile, synthesis, mapping, place/route, final timing and bitstream generation
completed; both original and copied design input hashes stayed unchanged.
The PDS flow took approximately five minutes. No hardware programming.

Final `report_timing/hdmi_ddr_ov5640_top.rtr` is multi-corner and reports
`Design Summary : All Constraints Met.` Relevant covered paths:

| Clock | Slow setup WNS (ns) | Fast hold WHS (ns) |
| --- | --- | --- |
| DDR core | 2.017 | 0.102 |
| CMOS1 buffered pixel | 17.503 | 0.201 |
| HDMI pixel | 8.924 | 0.265 |

Important retained warnings: the intermediate implementation hold-fix summary
has DDR fast hold -0.089 ns; console lines 13454/13457 report worst -79 ps and
`Hold violation fix failed`. These are not deleted or equated with the final
STA report, whose covered DDR hold is +0.102 ns. Existing STA-3011 no-clock
camera configuration warnings, inferred/unused clocks, asynchronous groups
and IO/CDC coverage limitations remain. **FullIOSignoff=false**.

The ONLY V3 delivery is:

```text
E:/code/BackupPortal/tmp/v3_frame_ownership_build/20261019_200533_451_40284dab/V3_frame_ownership_cmos1.sbit
```

Size: 2101696 bytes. SHA256, verified against the release file:
`A12CFF54132D3629CE36DE2985572DA406318D16EB87F7198C5ADD0666542359`.
`release.json`, `inputs.json`, `recipe.json`, `simulation_evidence.json`,
`input_changes.json` and final `.rtr` bind it to this build and simulation.
**Programmed=false, FlashWritten=false, BoardTest=false.**
Do not download an older generic bitstream under the V3 name. PDS project
and flow already include the new source `source/rtl/frame_buffer_owner.v`.
`unchanged_hardware_inputs.json` compares this build's inputs against the
accepted V2 build manifest: all 194 selected FDC, PLL, DDR IP, line-RAM IP and
camera-register files have identical SHA256. It is a file-identity check,
not hardware-parameter or full-IO signoff.
In the replacement build's `synthesize/hdmi_ddr_ov5640_top_syn.vm:15943`,
`writer_release_vname` is an actual `GTP_DFF_C` with its Q connected to the
local writer-release signal. The reset refinement is not merely an RTL name
whose register disappeared into a multi-bit state decode.

## Changed Files

- New RTL: `source/rtl/frame_buffer_owner.v`.
- Modified RTL: `fram_buf.v`, `wr_buf.v`, `rd_buf.v`, `img_proc.v`,
  `video_capture_status.v` and `hdmi_ddr_ov5640_top.v` under `source/rtl/`.
- Build inclusion only: `flow.tcl`, `HDMI_DDR3_OV5640.pds`.
- New tests/runner/README: `tools/frame_ownership/`.
- Evidence/status: this report, V2 feedback addendum in
  `09_capture_status_v2.md`, `docs/development/fpga_completion.md` and
  `docs/development/project_context.md`.

`git -c core.whitespace=blank-at-eol,blank-at-eof,space-before-tab,cr-at-eol
diff --check` passed. Original CRLF files were not normalized. No broad
historical test cleanup, backup rerun or archive edits.

## Limits And Board Handoff

- Correctness-first two-bank scheduling may lower the **new-frame update
  rate**, even while HDMI timing stays unchanged. No measured FPS claim.
  Repeated complete frames are intentional; tearing is not.
- Counters/committed tags are internal retained nets, not a PC-readable status
  interface. Do not ask the user to read nonexistent registers.
- A permanently stalled DDR transaction keeps its bank quarantined. This
  release does not claim safe autonomous cancellation/reinitialization of the
  DDR PHY. Global DDR reset invalidates all ownership.
- No crop/downscale, auxiliary product stream, semantic recognition or image
  network transport is added. No pin/FDC/PLL/DDR IP/camera-register changes.
- RTL PASS is not synthesis, routed timing or board PASS. Existing incomplete
  IO/CDC timing coverage must still be reported with any build.

Open `E:/FPGA drive/HDMI_DDR3_OV5640/HDMI_DDR3_OV5640.pds`;
top `hdmi_ddr_ov5640_top`, CMOS1, `SELF_TEST=0`. Source lists already include
the new module; no manual duplicate addition is required. Existing camera,
power and HDMI wiring stays unchanged. Ethernet is unused.

Manually select the exact successful V3 SBIT above in PDS
Programmer for JTAG. Do not assume the root generic SBIT or an old Flash image
is V3. Never hot-plug camera wiring for fault injection.

Board checks: startup reaches clean color; run moving video at least five
minutes; inspect for mixed old/new image bands, displaced final row, new
color corruption, repeated blacking or permanent freeze. Compare perceived
motion with V2 and report whether complete-frame repetition is noticeable.
Send exact programmed filename, startup time and a short moving-video clip;
on failure include full screen plus close-up, input scene and reproduction
steps. This is a debug image, so there are intentionally no HUD overlays.

The next bounded feature is configurable crop/downscale with transform/frame
metadata, after this release's normal-video feedback. Do not start it
automatically in this round.
