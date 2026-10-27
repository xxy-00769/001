# Complete-frame DDR regression

From the repository root, run `./tools/frame_ownership/run.ps1`.
Every run uses a new workspace-parent `tmp/frame_ownership/` directory, with
input SHA256 manifests, commands, logs, per-row evidence and `result.json`.
No main build outputs are cleaned and no hardware is programmed.

`owner_tb.sv` directs the production ownership module at small geometry:
final-write delay, pending-bank protection, read completion across a frame
boundary, repeat, overloaded writer, raw geometry failure, pipeline abort,
drain, read failure, reset and fresh-frame recovery.

`full_frame_tb.sv` connects the production raw monitor, tagged clean-color
processor, frame buffer, native command controllers, generated write/read
line RAMs and Pango simulation primitives. A bounded external two-bank
memory BFM responds to the existing vendor native port, including data gaps.
It is NOT a simulation of DDR electrical timing or the DDR PHY.

The pixel oracle depends on source frame ID, row and column. All 1280 pixels
of row 719 are included, as are repeated complete frames, parallel capture
and display at different clocks, no-free-bank frame drop, raw malformed
geometry and recovery. Invalid source frames must never become display frames.
Software calculations alone do not count as these RTL checks.

Do not run the heavy ModelSim test concurrently with the full PDS build on
this machine. Use the current passing `result.json` with the existing isolated
`tools/s4_clean_video/build.ps1` entry to build without programming.
