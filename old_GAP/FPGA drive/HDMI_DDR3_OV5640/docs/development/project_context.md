# Development Context and Evidence Index

Date: 2026-10-19. This is a navigation snapshot, not permanent policy, fresh
hardware acceptance or authorization to continue the main development thread.
Paths are relative to this repository so the rules remain usable after moving it.

## Location and Current Evidence

- [V5.2 clean/bright display](../reintegration/14_mpi7001_v5_2_clean_bright.md):
  user confirms V5.1 stable, requests no diagnostic bars and reports dim image.
  V5.2 removes both probes, applies display-only 9/8 saturating RGB gain,
  preserves timing/algorithms/capture/DDR. Output exhaustive check PASS; final
  build `JF/builds/v5_2_20261020_140727` All Constraints Met, stable inputs.
  Package `JF/V5_2_MPI7001_800x480_BRIGHT`; new bitstream board test pending.

- [V5.1 MPI7001 diagnosis](../reintegration/13_mpi7001_v5_1_diagnosis.md),
  2026-10-20: user reports V5 receives video but has blocks/colour corruption.
  First-SOF/reset defect reproduced; final candidate preserves V5 PLL structure
  and adds independent display probes in the margins. PLL split was withdrawn.
  Persistent
  field corruption root cause remains unconfirmed. See release/user evidence.
  Delivery/build paths are ASCII under `E:/zhoumian/FPGA/JF/`.
  Final build `JF/builds/v5_1_20261020_135124`: PASS, All Constraints Met;
  final display simulation `v5_1_display_20261020_134611`: PASS, stable inputs.
  Package `JF/V5_1_MPI7001_800x480_DIAG`, SBIT SHA256
  `00CBF46936AAC6FC396D4E74E6980BA4E33DBBF6B87FDAC723614C2598B51A3A`.
  Only two display RTL files differ from V5; FDC/flow restored to V5.
  User subsequently reports V5.1 display stable on MPI7001, slightly dark;
  requests removal of diagnostic margins. This is user field feedback, not
  agent on-board measurement. V5.2 output-only revision is in progress.

- [V5 MPI7001 display output](../reintegration/12_mpi7001_display_v5.md),
  2026-10-20: current display adaptation for 800x480 MPI7001, based on cached
  EDID; original 720p capture/processing and KEY8 retained. Half-size display
  reader produces centred 640x360 at approximately 59.927 Hz panel scan rate.
  Timing RTL: three frames PASS. Reader RTL: two complete output frames,
  460800 pixels PASS, original read RAM with documented Icarus constant-CS
  compatibility copies. This is not a writer/ownership/algorithm regression.
  Final PDS routed timing: All Constraints Met, build directory
  `../tmp/v5_mpi7001/20261020_130448/` relative to the project parent.
  No agent programming/Flash operation. User programmed V5 and reported
  corrupted video; board display acceptance FAILED. Moved package:
  `E:/zhoumian/FPGA/JF/V5_MPI7001_800x480`.

- [V4 KEY8 selectable views](../reintegration/11_key8_video_modes.md) is the
  preceding KEY8 code/build increment; board feature acceptance is pending. Six
  frame-atomic views: original, grayscale, median, Sobel, candidates, and
  legacy lane/zebra diagnostic. Original has no paint/HUD; the independent
  clean output remains. The single DDR display cache now holds the selected
  view in diagnostic modes. V3 ownership and S3a/S3b fixes are retained.
  Key RTL: 55 checks PASS. Image RTL: 8 full frames / 7372800 pixels PASS.
  New delayed display-to-native-DDR path: 6 full frames / 5529600 pixels PASS.
  PDS through bitstream PASS under existing routed constraints, with original
  three-bit Gray encoding verified after preventing automatic FSM recoding.
  Release is in
  `E:/FPGA drive/tmp/v4_key8_video_modes_build/20261019_205011_596_12a24176/`,
  SHA256 `74CDE8193FF3F3FEF4B4A643FF132F7CA16FFF09989E6BCC4448965CBE7887B7`.
  Final release identity, reuse boundaries and warnings are in the V4 report.
  Do not use the older V3 SBIT to test KEY8. No programming by the agent.

- [V3 completed-frame ownership](../reintegration/10_frame_ownership_v3.md)
  is the preceding buffer baseline. Two-bank write reservation,
  raw/clean geometry and frame-tag binding, native completion-based publication,
  display-boundary selection, overwrite protection and read-fault blacking
  are implemented. Final registered-reset RTL passes: 38 directed checks,
  6 full 720p frames / 5529600 exact pixels, 2560 fault-output black pixels.
  Replacement full PDS build through bitstream passes under existing final
  routed timing constraints (DDR slow setup +2.017 ns / fast hold +0.102 ns).
  Existing implementation hold-fix/no-clock/IO/CDC warnings remain documented;
  not full IO signoff. The only V3 SBIT is in
  `E:/FPGA drive/tmp/v3_frame_ownership_build/20261019_200533_451_40284dab/`,
  SHA256 `A12CFF54132D3629CE36DE2985572DA406318D16EB87F7198C5ADD0666542359`.
  User programming/board feedback is pending. An earlier V3 build was
  deliberately cancelled during synthesis and is not a release. See this
  report before selecting any V3 output. No hardware programming by the agent.

- Actual Git root: this directory's `../..`, `HDMI_DDR3_OV5640`.
  The current workspace entrance is its parent, `E:/FPGA drive`.
- Inspected HEAD: `6f68d09149f3fcf3927174887f80cea9225fae50`.
  Existing README edits, untracked reports/tools and outside archives were
  preserved. Re-read Git state when starting work; this hash is not a live lock.
- [FPGA completion track](fpga_completion.md) records the user's fixed FPGA/
  Orange Pi division and what is genuinely integrated versus still pending.
  [V2 capture status/recovery](../reintegration/09_capture_status_v2.md) adds
  source geometry checks, internal metadata, independent stopped-clock/frame
  watchdog, processing reset and an HDMI display guard. Directed RTL: 203
  checks; integrated clean color: three 720p frames / 2764800 correct pixels,
  plus stopped-source/mid-frame-reset color recovery.
  These are not DDR bank ownership, a host-readable status port, crop/resize
  or physical network/image transmission. Final isolated PDS build passes
  through bitstream with existing routed timing met and input hashes stable;
  old coverage warnings remain. Current V2 SBIT is in
  `E:/FPGA drive/tmp/v2_capture_status_build/20261019_192508_695_fd822c5f/`.
  The user subsequently reports normal video has no apparent problems; no
  independent bitstream readback or fault testing was done. The report contains the exact release
  path/SHA256; do not use the earlier invalidated build.
- [S5a diagnostic application / second-PC tools](../reintegration/08_udp_diag_s5a.md):
  isolated 32-byte protocol RTL and standard-library host client/emulator.
  Nine host tests (including OS UDP loopback) and 281 directed RTL checks pass;
  independent application-only PDS compile/synthesis pass, with warnings
  recorded. No main-top/PDS/FDC/IP changes, MAC/PHY integration, new bitstream,
  physical Ethernet acceptance or image transfer. ETH1 electrical/PHY delay
  evidence gates that integration only, not independent development.
  A portable ZIP and Chinese second-PC instructions are in the report.
- [V1 clean color / S4](../reintegration/06_clean_color_v1.md) now exports
  the buffered unpainted color stream with its own DE/VS to main DDR.
  Old diagnostic outputs/source remain separate and do not feed main DDR.
  Six full 720p frames (5529600 pixels), diagnostic isolation and the existing
  early-sync smoke test passed. PDS compile through bitstream completed in an
  isolated directory; final multi-corner STA meets existing constraints.
  Existing no-clock/IO coverage limitations and an internal hold-fix message
  are documented, not suppressed. The earlier delivery status was not yet
  programmed; subsequent user feedback reports clean HDMI and smooth moving
  video after their manual download. This is a user board observation, not
  independent bitstream readback, pixel/color-edge or long-duration acceptance.
  S3a/S3b inputs remain unchanged; user feedback on the preceding release
  reported compilation/configuration and basic old functions working.
- [S3a/S3b repair and build handoff](../reintegration/05_ddr_correctness_fix.md)
  supersedes the S2 proposal status below. S3a's side-session last-valid-beat
  fix and its original/16-case PASS evidence were checked against current
  input hashes. S3b changes only the read-line counter reset from 1 to 0:
  the original 720-row RTL case passed, and three frames (two consecutive,
  then one after an idle DDR reset) passed with 2764800 correct pixels.
  These are worktree fixes, not this HEAD, synthesis, timing or board passes.
  The user owned that release's PDS build/JTAG/board feedback. Its statement
  that V1 was next applies to that historical release; see the newer V1 entry.
- [S2 report](../reintegration/04_ddr_minimal_reproduction.md) records two
  independent failures on unchanged main RTL: completion held 20 cycles with
  19 cycles lacking a return; isolated read buffer requested 719 rows and all
  1280 last-row pixels were wrong. This Skill task did not rerun those tests.
- That report proposes separate S3a/S3b repairs. A proposal is not authorization
  to implement them here. No product repair was part of Skill installation.
  During installation, the preservation comparison observed an external change
  to `source/rtl/wr_cmd_trans.v` and new S3a tool files. This side conversation
  did not write, revert or test them. Consult current inputs and newer task
  evidence before describing the present repair status.
- [S1 baseline](../reintegration/03_baseline.md) holds identity distinctions,
  snapshot/recovery coverage and limitations. Hardware unknowns gate their
  dependent operations, not all independent development.
- [Video contract](../reintegration/07_video_interface.md) is an S1 design draft,
  not a delivered clean-color output. Do not inherit its historical "stop at S1"
  as a permanent restriction on later user-authorized work.

## Read Only What Affects the Task

| Decision | Evidence entry |
| --- | --- |
| Existing architecture/function inclusion | [Audit](../reintegration/00_project_audit.md), [matrix](../reintegration/function_matrix.csv) |
| Current FPGA/ARM division | [Target architecture](../reintegration/01_target_architecture.md) |
| Phase names and candidate checks | [Execution plan](../reintegration/02_execution_plan.md); its initial S1-only status predates the S2 report |
| Rules/requirements vs real completion | [ADAS comparison](../../reports/ADAS细则对照与完成度审查_2026-10-19.md); this is a user-document mapping, not fresh official competition verification |
| Recurrent execution mistakes | [2026-10-18 review](../../reports/2026-10-18_开发完整时间线与问题复盘.md), especially sections 5 and 6 |
| Directed test commands/limits | [DDR test README](../../tools/s2_ddr_minimal/README.md) |
| Host-only evidence boundary | [Host README](../../host/README.md) |
| Skill installation and checks | [Validation record](skill_validation.md) |

Outside-repository archives currently live at workspace-parent
`_archive/experiments/`. Locate the exact asset first; old scripts may still use
pre-move paths or select patched candidates. Preserve archives as evidence.
The user's original requirements and vendor hardware documents are referenced
by the audit/baseline reports; their external availability is not guaranteed
by a Git checkout.

## Maintenance

Update current progress and verification in task-specific project reports.
Change this index only when routing or a material status changes. Keep old
failures intact and bind new results to inputs, rather than overwriting history.
Permanent architecture changes require a user decision or authorized task,
not an incidental README sentence. Latest user scope and actual current inputs
control execution; neither the index nor old reports independently grant it.
