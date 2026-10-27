# S3b directed read-buffer regression

Run from `E:/FPGA drive/HDMI_DDR3_OV5640`:

```powershell
& './tools/s2_ddr_minimal/run.ps1' -Case rd_buf -OutputParent 'E:/FPGA drive/tmp/s3b_rd_buf_original_case'
& './tools/s3b_rd_buf/run.ps1'
```

The first command reuses the unmodified S2 full-frame failure oracle.
The second runs two consecutive 1280x720 frames, then a third frame after
an idle, between-frame `ddr_rstn` reset. Each frame has a distinct pattern
tag; frame-bank selection alternates across the reset, matching the existing
bank counter's lifetime. This is not a mid-command reset test.

Both compile production `rd_buf.v`, the original generated `rd_fram_buf` and
installed Pango `GTP_GRS` / `GTP_DRM18K` simulation models. A native-return BFM
supplies each requested line, without replacing the line RAM. It does not
instantiate the full DDR controller/PHY or `wr_cmd_trans`.

For each frame, require exactly 720 requests, 720 completions, 57600 return
beats, 921600 correct pixels and zero last-row errors. The added regression
also checks 720 separate DE segments of 1280 pixels and exactly one request
for each row. No clipping or modified expected pixels are used.

Each invocation creates a unique directory under workspace `tmp`, containing
input hashes, commands, simulator logs, request/row/frame CSVs, mismatches,
control VCD and `result.json`. Exit 0 means the complete regression passed;
nonzero means failure or an execution/input-integrity problem. Check the
result and simulator log to distinguish them. The generated RAM currently
emits missing `WWCONF` port warnings; these are preserved, not patched away.

These files are simulation-only and must not be added to the PDS design
source list. Passing does not establish synthesis, STA or on-board acceptance.
