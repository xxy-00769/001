# S2 DDR Minimal Directed Tests

This directory does not modify or select replacement main RTL.
Every invocation creates a new directory under
`E:/FPGA drive/tmp/s2_ddr_minimal`.
No synthesis, implementation, bitstream, programming or Flash operation is run.

## Run

```powershell
& 'E:/FPGA drive/HDMI_DDR3_OV5640/tools/s2_ddr_minimal/run.ps1' -Case control
& 'E:/FPGA drive/HDMI_DDR3_OV5640/tools/s2_ddr_minimal/run.ps1' -Case rd_buf
```

Default simulator: `D:/PDS/Modelsim/win64` (ModelSim SE-64 10.7).
The paths can be overridden by `-ModelSim`, `-PrimitiveLibrary`, `-OutputParent`.
The current repo is located from this script, not from archived relative paths.
No archived candidate RTL or archived runner is executed.

- `control` compiles the main `source/rtl/wr_cmd_trans.v` and the unchanged
  archived `road_video_ddr_20261017/tests/control_tb.sv`.
  It tests the read-return completion counter: 80 valid returns, with 17
  additional idle clocks before the last return (plus normal inter-return idle).
  It injects return-valid directly; it does not validate burst scheduling,
  `rd_ctrl`, native DDR responses or the physical DDR.
- `rd_buf` compiles only the main `rd_buf.v`, its original generated
  `rd_fram_buf` RAM wrapper/implementation and this directory's testbench.
  It uses installed `GTP_DRM18K`/`GTP_GRS` models, not an ideal replacement FIFO.
  A native line-return BFM returns 80 beats and one final completion for each
  request. `wr_cmd_trans` is absent, so this test isolates the second problem.
  The pattern, clocks, GRS startup and display timing reuse the archived assets.

Exit code 0 means the directed DUT assertions passed.
Exit code 1 means the simulator completed but the directed DUT verdict failed.
Exit code 2 means execution/input stability was blocked or invalid.
Inspect `result.json`: a simulator exit code of zero alone is not acceptance.

Each output directory contains input/protection hashes, actual tool commands
and return codes, compiler/simulator logs, a VCD and evidence hashes.
The read test additionally writes `requests.csv`, `rows.csv`, `mismatches.csv`.
The mismatch file stores the first 16 failures; `rows.csv` counts every failure.
Its row pixel counts group the output stream into 1280-pixel rows; they are not
an independent DE-envelope timing assertion.
In this first testbench revision, the `requests.csv` header `time_ns` is
mislabelled: `%0t` actually prints picoseconds at the simulator's 1ps precision.
Use the VCD timescale/command log for time units. This label does not affect
address, row, data or completion checks; original evidence is retained unchanged.

`verify_evidence.ps1 -ControlRun <directory> -ReadRun <directory>` cross-checks
the original two failing results against their VCD/CSV and SHA256 records.
It deliberately expects the initial 20/19 completion and missing-row findings;
it is not the post-fix acceptance oracle and must not be reused unchanged to
approve S3. Use the runner's zero-error PASS requirements for post-fix tests.
Its default S1 metadata location is this session's verified snapshot; supply
`-S1Metadata` when restoring that metadata elsewhere.
