# Capture Status RTL Checks

From the repository root in PowerShell:

```powershell
& ./tools/video_capture_status/run.ps1
```

Requires the existing ModelSim installation (default
`D:/PDS/Modelsim/win64`). Each run creates a unique workspace-parent
`tmp/video_capture_status/<stamp>/` directory; no prior output is removed.
`result.json`, input SHA256 manifests, tool logs and directed-case
`frames.csv` are the evidence. Do not run memory-heavy PDS and ModelSim in
parallel on a machine with insufficient virtual memory.

- `capture_status_tb`: geometry, IDs/time, bounded mailbox, saturation,
  independent stopped-clock/frame watchdog, reset/recovery and presentation.
- `capture_full_color_tb`: three complete 1280x720 frames through the real
  `img_proc` clean path and its new reset connection; full pixel oracle.
- `capture_recovery_color_tb`: actual monitor/reset/processing tuple after
  stopped video clock and mid-frame global reset. Aborted partial frames are
  not called complete; every observed active pixel is checked.

Neither a RAM substitute nor a full DDR controller/PHY is instantiated here.
These tests do not validate frame-bank ownership, physical capture, CDC MTBF,
network communication or on-board recovery.

After a completed simulation PASS, the existing isolated full-build runner
can be used with the actual result path:

```powershell
& ./tools/s4_clean_video/build.ps1 `
    -SimulationResult 'E:/FPGA drive/tmp/video_capture_status/<stamp>/result.json' `
    -ReleaseName V2_capture_status_cmos1 `
    -OutputParent 'E:/FPGA drive/tmp/v2_capture_status_build'
```

The runner verifies simulation input hashes, copies current design/IP/FDC into
a unique output tree, runs Compile through Bitstream, checks artifacts and
final routed timing against the existing constraints, and records release
identity. It never programs the board. `FullIOSignoff` intentionally remains
false. Original/copy design changes during a build invalidate its result.
