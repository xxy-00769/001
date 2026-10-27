# Camera-Candidate Interaction Build

The user accepted the four physical keys in v11 RULE TEST on 2026-10-18:
`看到了 测试通过，四个键测试完成  可以进行下一阶段`.
That accepts the local rule interaction, not real-image lane accuracy.

## Current Single Goal

Connect the existing real CMOS1 `img_proc` lane candidate snapshot to the
four-key controller and the `LOCAL CANDIDATE` status panel. Preserve the
accepted v11 binary, v4/v8 baselines, original detector, DDR and key assignments.
No ARM, traffic-light, four-camera or FPGA neural-network work in this stage.

Camera candidates are image-space heuristics. They can reject valid road scenes
and accept furniture/lines. A dashed request is not a safe-driving decision.
No vehicle actuator is connected.

## Archive Relocation

During the first v12 build, a separate repository cleanup moved experiments to:

`E:/FPGA drive/_archive/experiments`

Commit `6f68d09` and its rewritten README are preserved. The archived v12
`runs/20261018_143119_235` contains the first simulation and routed build,
including failed compile attempts and the unsupported mapped-DB timing query.
Nothing in those historical logs is rewritten to account for the move.

v11's user acceptance record is now at:

`E:/FPGA drive/_archive/experiments/v11_lane_interaction_20261018/board/user_acceptance_20261018.json`

Its accepted binary remains at:

`E:/FPGA drive/_archive/experiments/v11_lane_interaction_20261018/builds/20261018_130743_866_resume_pnr/bitstreams/11_lane_interaction_rule_test_cmos1.sbit`

SHA256: `9c21a93bee132ed1513810b29c820309387a5b73a84de41f6851bddc22e0c442`.

## Changes And Verification

- `SELF_TEST=0`, `LOCAL_RULE_TEST=0`; no rotating synthetic rule source is used
  in the candidate build. Existing heuristic thresholds are unchanged.
- Reset the new mailbox/controller epoch when `img_rstn` is asserted as well as
  during the existing system/DDR reset. Both mailbox domains share assertion
  and release synchronously in their own clock domains.
- Preserve the mailbox handshake/held registers for mapped inspection.
- The first build routed, but even a targeted exception report showed no
  held-to-snapshot paths. It is not a released build. The second constraint
  configuration replaces only the camera-pixel and display blanket clock
  groups with first-synchronizer-stage exceptions and an asynchronous
  bundled-data hold exception. The data max-delay must still be measured
  against 14ns. Other clocks, frequencies and original pin assignments stay.
- Actual `img_proc` plus the camera-mode UI passed six RGB fixture frame inputs
  (five complete and one intentionally malformed):
  solid blocking/alarm, dashed request, blank/bad clearing, stopped-source
  timeout and common reset/recovery. The 256-bit CDC test also passed.
  These are synthetic image fixtures, not camera hardware or labeled accuracy.
- A constraint-only rebuild reuses those tests only after exact source/test
  hashes and PASS log hashes match. It is not another simulation run.

Scripts never scan or program a board and never write Flash. `build.ps1`
performs mapping, direct single-action routing, timing gates, then bitstream
generation. It does not use the project dependency dispatcher to resume PNR.
Output goes outside the repository, under workspace `tmp/`.

```powershell
./tools/v12_camera_interaction/build.ps1 -Run 'E:/FPGA drive/tmp/v12_camera_interaction_20261018/<new-run>'
```

The source fixtures and v11 generator currently depend on the preserved local
archive; this is not a standalone repository-only release recipe.

## Routing-Only Hold Repair

The second constraint configuration exposed the expected 24 mailbox data
endpoints in both corners, all meeting 14ns (worst slack +12.171ns).
Its only reported timing failure was a fast-corner -0.005ns hold path from
`u_img_proc/u_lane/width_meta[65][24]` to `width_meta[66][24]`.
It was not released.

`build.ps1 -ResumeHoldFrom <previous-run>` reuses the exact mapped DB and
placement checkpoint, checks their hashes and leaves RTL/constraints unchanged.
It explicitly enables multi-corner hold repair with a 50ps repair threshold,
not a relaxed timing requirement. The PDS command help defines this option in
ps; the installed User Guide describes optimization of paths below the
threshold. This is one hypothesis-driven repair attempt, not proof that the
default threshold caused the original failure. No automatic retry follows a
failed audit.

The first launch stopped before routing because the PDS child could not open
the relative placement-checkpoint path. Its files remain under workspace
`tmp/v12_camera_interaction_20261018/20261018_hold_margin_50ps`.
The corrected launch uses absolute DB paths in a separate
`20261018_hold_margin_50ps_absolute` directory. The copied `map.log` is explicitly
identified as reused evidence in `recipe.json`; no synthesis or mapping runs
in this continuation.

The continuation completed routing, but the final report still shows the same
`width_meta[65][24]` to `[66][24]` fast-corner -0.005ns hold violation.
All 48 reported mailbox paths pass; its setup summary is +12.176ns.
The release gate fails, so there is no v12 SBIT/SMSK, programming or board
acceptance. No further routing settings were tried. The collector was corrected
to accept both PDS output layouts (run root and `place_route/`); its small
helper test suite passes six tests, which are not FPGA functional simulations.

The targeted-CDC build, failed relative-path launch and completed hold-repair
build were copied without alteration to the preserved archive's `builds/`
directory. All 293, 243 and 259 files respectively matched SHA256 after copying.
Historical absolute paths inside logs remain unchanged. See the Chinese stage
report at
`E:/FPGA drive/HDMI_DDR3_OV5640/reports/v12_真实候选按键集成_2026-10-18.md`.

## Remaining Physical Acceptance

After a named artifact passes checks and JTAG trial authorization is clear,
record 6 scenes twice each (12 functional observations): two solid boundaries,
two dashed boundaries, left-solid/right-dashed, left-dashed/right-solid,
no usable pair, and indoor furniture as a non-road negative. This is inference
evaluation, not training or a statistical accuracy estimate.

Keep KEY1 left, KEY2 right, KEY3 force, KEY4 cancel. Confirm no synthetic scene
rotation, valid candidate/request association, unknown clearing, image update,
and actual limitations. UNKNOWN is allowed; never force validity just to show
an arrow. If the fixed existing heuristic fails positive scenes, record that
and use the planned ARM perception path rather than unlimited threshold trials.

The panel shows latest state/frame ID, not a promise of exact DDR background
frame alignment. The old pre-DDR HUD/background may freeze when the camera stops;
the new controller timeout does not solve whole-frame disconnect behavior.
The orange blocked arrow indicates the requested direction, while effective
direction remains zero; a competition driving-action arrow needs a separate
unambiguous presentation review before final lane-function acceptance.

Physical camera classification, complete IO/CDC signoff, frame rate, latency,
road semantic recognition and the competition lane task are not accepted by
these local simulations or a successful build.
