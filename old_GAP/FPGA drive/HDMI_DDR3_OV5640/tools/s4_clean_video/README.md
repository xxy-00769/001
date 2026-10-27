# V1 clean color / S4

Run in PowerShell 7 from `E:/FPGA drive/HDMI_DDR3_OV5640`:

```powershell
& './tools/s4_clean_video/run.ps1'
& './tools/s4_clean_video/build.ps1' -SimulationResult '<the new simulation run>/result.json'
```

`run.ps1` creates unique workspace `tmp/s4_clean_video` outputs. It compiles
the production `img_proc` and diagnostic modules with ModelSim, then runs:

- Six 1280x720 clean frames: red, green, blue, 1-pixel checkerboard,
  row/column code with four-edge sentinels, and a frame-tagged pattern.
  All 5529600 pixels are compared; actual DE line lengths, frame marker,
  startup without VS, and reset between the third/fourth frames are checked.
- Two 1280x72 frames comparing diagnostic-off and diagnostic-on clean outputs
  cycle for cycle, including blanking. The diagnostic output must actually
  alter pixels, preventing a vacuous comparison with an inactive HUD.
- The existing `img_proc_early_sync_tb` unchanged, as a focused legacy smoke
  test. This is not a rerun of all old detection tests.

`frames.csv` / `rows.csv`, simulator logs, input hashes, tool commands and
`result.json` bind the results to the inputs. Optional unused output ports
in benches cause simulator warnings; they are not hidden.
This suite tests the buffered normalized RGB565 stream, not physical DVP
sampling, the DDR PHY or real camera color calibration.

`build.ps1` requires a completed PASS simulation whose inputs still match.
It copies current `source/`, FDC, flow template and PDS config into a new
workspace `tmp/s4_clean_video_build` directory after rejecting source links.
It runs the existing flow template unchanged via a disposable `build.tcl`.
It does not run destructive `build.bat`, alter the original IP/constraints,
or replace original build outputs. PDS may append commands to the disposable
script; the original template and copied design inputs are verified.

The runner checks process errors, stage artifacts and routed timing's
`All Constraints Met` under the existing constraints. This is not a full
external-IO/CDC signoff. A successful run produces:

- `V1_clean_color_cmos1.sbit` for manual configuration.
- `release.json` with its path, size and SHA256.
- `inputs.json`, `recipe.json`, worktree diff and simulation evidence link.
- `pds_console.log`, all PDS stage outputs and routed timing report.

There are no programmer, JTAG scan, Flash or hardware-control commands.
Do not use an older generic SBIT from the repository as this release.

For a completed run whose delivery verification needs to be repeated, pass
the same simulation result plus `-VerifyCompletedRun '<existing build run>'`.
This verifies identity, artifacts, inputs and timing without rerunning PDS;
the preceding result is retained before updating the verification result.
UTC freshness comparisons use `DateTimeOffset.UtcDateTime`, not a local
`DateTime` compared directly against a UTC file timestamp.
