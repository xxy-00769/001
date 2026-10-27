# Standalone Road-Analysis Input Preparation

## Status

This is an isolated RTL experiment, not a new camera bitstream or road detector.
There is no deployed model, RISC-V CPU, software/hardware bus, external image
transport, semantic mask, or changed overlay. Main RTL and named bitstreams are
unchanged. No board programming was performed.

The user's preferred deployment is independent of a PC. The supplied competition
PDF, physical page 14 (printed page 12), permits an FPGA RISC-V soft core or an
external ARM processor, and separately requires software/hardware communication.
An FPGA soft core is a possible route, not proof that the current model fits or
meets latency requirements. No purchase recommendation is made here.

## Implemented Contract

`road_thumbnail.v` accepts RGB565, DE and active-high VS in one clock domain.
Default input is 1280 x 720. Every 8 x 8 block is decoded to RGB888, summed,
integer-divided by 64 and requantized to RGB565. All image regions are included:
there is no assumed road ROI. Output is 160 x 90, with coordinates and validity.
This is an analysis branch only. Its blurred/downsampled image must never replace
the user's original display image.
Its input must be aligned original RGB, not pixels already painted green/cyan by
the marking overlay. No connection to the existing camera clock/reset path has
been made or validated in this experiment.

`road_input_buffer.v` stores one 14,400-pixel, 28,800-byte snapshot. A full frame
is published only on the next VS boundary after exact row widths and row count
have been checked. This adds up to one source-frame period of wait, independent
of later inference. The first clean VS starts acquisition; a stopped source
without the next VS does not publish its last frame.

- RGB/DE/VS, read controls and releases must all use `clk`. There is no CDC.
- DE must fall between rows, with at least one full low clock before frame VS.
- A consumer reads row-major RGB565 words at addresses 0..14,399. Reads are
  synchronous, one per clock, qualified by `read_valid`.
- Reads while unavailable, out-of-range reads and release/read collisions return
  zero with `read_valid=0`. A release does not erase memory.
- `frame_available` protects the entire buffer from overwrite until release.
  It does not mean the snapshot is fresh. A future inference/overlay integration
  must check age and reject stale results; no temporal safety gate exists here.
- Release in the middle of a source frame cannot admit its partial remainder.
  Acquisition waits for the next clean VS. Publication wins a simultaneous
  release; it protects the newly published frame and skips the new source frame.
- This is deliberately a single-buffer handshake, not a full-rate queue. Valid
  frames not captured increment `dropped_frames`; malformed frames increment
  `invalid_frames`. No analysis-frame drop changes the display stream.
- IDs count accepted start boundaries, wrap at 32 bits, and identify the captured
  source frame. Holding a snapshot while many new source frames arrive is allowed.
- RAM is not reset. First block rows overwrite sums and complete-frame checks
  prevent uninitialized or partially filled frame memory from being published.

Parameters require a power-of-two scale between 2 and 16, dimensions divisible
by the scale and between 16 and 2040, and fewer than 16,384 output pixels. The
tested configurations are 64 x 32 and 1280 x 720, both at scale 8; other legal
configurations are not yet regression-tested.

## Verification

Run from the project root using the existing local tools:

```powershell
./experiments/road_input_20261017/tests/run.ps1
```

This generates independent NumPy block-mean vectors and runs the actual RTL on
synthetic pixels, saturated primary/secondary colors, a road photo and an indoor
shelf photo, including complementary RGB variants. It checks every output pixel,
full-buffer reads, immutability, backpressure drops, releases, reset, and recovery.
The small cases additionally reject empty/truncated frames, short/long rows,
extra rows and VS/DE overlap. Publication/release priority is exercised explicitly.

For resource estimation, run these separately from this experiment directory:

```powershell
Copy-Item -LiteralPath flow.tcl -Destination impl.tcl
& 'D:/PDS/PDS_2022.2-SP6.1/bin/pds_shell.exe' impl.tcl *> synthesis.log
```

Then from the project root:

```powershell
./.venv-road-seg/Scripts/python.exe -X utf8 experiments/road_input_20261017/tests/verify.py
```

Final counts, source hashes and protected file hashes are recorded in
`tests/verification.json`. Default-size standalone synthesis/device mapping used
309 LUTs, 310 registers, 17 DRM18K units and no APMs. These numbers include the
snapshot RAM, not an inference engine or CPU. Logical buffer size is 28,800 bytes;
physical memory allocation is larger due to block geometry and sum storage.

This flow intentionally stops at device mapping. There are no pin assignments,
interface delays or placement/routing. Expected unconstrained-port warnings,
constant-probe-loop messages, constant-bit removal and fanout warnings are present.
No timing/FPS or main-video integration signoff is claimed. Vivado's optional
Webtalk may report a missing local `E:/FPGA` path; actual compile/elaboration and
simulation PASS markers are checked separately.

## Next Acceptance Boundary

Select and validate an implementable small road-segmentation model on labelled
road/nonroad data, including missed-road pixels. Existing 14 images are a reused
regression set, not sufficient training or independent accuracy evidence. Measure
quantized model memory, operators and end-to-end latency before committing to an
accelerator/soft-core architecture. The CPU SegFormer experiment is not an FPGA
model and has not been converted by this work.

Only after model evaluation and actual inference integration should the analysis
branch be connected to a separate camera build. Keep original RGB for display,
require complete current masks, and preserve the version 4 comparison bitstream.
