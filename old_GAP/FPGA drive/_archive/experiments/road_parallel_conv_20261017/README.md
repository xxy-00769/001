# Sixteen-Lane Integer Convolution Experiment

Date: 2026-10-17. Isolated RTL simulation and synthesis/device mapping only.
No new `.sbit`, board programming, camera connection, DDR master, full-model
execution, or semantic-accuracy improvement is delivered by this experiment.
The user's v4 baseline and all 229 protected main files remain unchanged.

## Decision

Continue development of a resource-bounded FPGA prototype. The arithmetic
accelerator now fits the standalone device budget with multiplier headroom,
but the existing implementation is still too slow for real-time driving.
This is NOT approval of the full architecture or the road model for deployment.

The new engine implements the same 136 convolution arithmetic contracts as
`../road_integer_ops_20261017`. It is one configurable engine reused across
tiles, not 136 connected layers. The final floating-point classifier remains
unsupported. Pooling, interpolation, complete residual scheduling, semantic
postprocessing, DDR arbitration and camera/display integration remain absent.

## Implementation

`source/conv_parallel.v` processes up to 16 output channels together. The
ordinary-convolution path broadcasts one input value to 16 independent weights;
the depthwise path reads one input channel and weight per lane. The address,
synchronous RAM, multiplier and accumulator stages accept one kernel term per
active lane per clock. Incomplete channel groups suppress inactive lanes.

Input, weight and coefficient bytes retain the serial engine's CHW, OIHW and
little-endian contracts. Loading internally banks channels modulo 16:

| Memory | Per Bank | Banks | Allocated Bytes |
| --- | ---: | ---: | ---: |
| Input codes | 4,096 | 16 | 65,536 |
| INT8 weights | 1,024 | 16 | 16,384 |
| Coefficient bytes | 128 | 16 | 2,048 |

These allocations contain banking slack; the logical descriptor limits remain
32,768 input bytes and 8,192 weight bytes. An exhaustive descriptor-address
audit covers 3,476,367 valid combinations, with maxima of 2,415 input and 954
weight bytes in one bank. Coefficients use at most 70 bytes per bank.

Each output is a signed INT32 accumulator followed by a signed 48-bit Q36 gain
and signed 64-bit offset, round-half-up and saturation to uint8. The shared
quantizer first registers lane selection, then multiplies, adds bias and
publishes. Without that selection register, PDS distributed the multiplication
across lanes and consumed all 84 APMs. That rejected intermediate build is kept
under `tests/output/pre_quant_select`; it is not the reported final design.

## Interface and Ordering

Descriptors support ordinary/depthwise 1x1, 2x2 and 3x3 convolutions, stride
1/2, dilation 1..8, 1..80 channels and output tiles up to 4x4. The caller supplies
padding. Valid input extents exactly match the receptive field. No full-image
address generator is present.

- Configuration is accepted only on `cfg_valid && cfg_ready` while idle.
- Each of the three byte banks must be loaded consecutively from address zero.
  Banks may be interleaved or loaded in any order. Counters are independent.
- No job starts until all three banks are complete. Reserved bank writes and
  out-of-order accepted writes latch `fault` until reset. A malformed write
  concurrent with start takes precedence over starting the job.
- Full-bank writes and changes of descriptor/load/start while running are
  not accepted and cannot mutate a running job.
- RAM is unreset. Reset invalidates the entire transaction, including data
  still in the multiply/quantization pipeline. The next job must fully reload.
- **Output delivery order differs from the serial engine.** It is channel
  group, row, column, then lane. `out_index` is the flattened CHW destination
  within the tile. Consumers must use that index; arrival order is not CHW.
- Data, accumulator, index and validity remain stable under backpressure.
  `done` occurs only when the final output is consumed. No next descriptor is
  accepted while that final output is stalled.
- There is no retained-weight mode, overlapping load/compute, wide burst
  ingress, DDR backpressure adapter, frame ID or stale-result rejection yet.

This is a single-clock internal block. The production design still needs
clock-domain handling, reset synchronization and integrated interface timing.

## Verification

All 3,214 fixed serial tests are reused unchanged, including real-image tiles
and the three fully reconstructed intermediate tensors from `legacy_road_3`.
There are 67 additional cases for odd/partial channel groups, channels around
16/32/64 boundaries, kernel 2, maximum dilation, high local bank addresses,
signed weight extremes and full-range gain/offset saturation. Python arbitrary
precision is used for the new extreme-coefficient quantization oracle.

- 3,281 RTL jobs; 624,572 accumulator/code pairs exactly match the references.
- 342,301 stalled output cycles checked with no changes to pending results.
- Each output index is range-checked and checked for duplicates/missing data.
- Exact core-cycle formula checked for every case, excluding measured stalls.
- Reset during six MAC-pipeline positions and while output is pending.
- Explicit final-output stall and completion check; invalid descriptors,
  malformed loads, incomplete loads, busy mutation and start/write race tests.
- Original serial vectors, model files, sources and evidence are hash-checked.
  Build input hashes are checked before/after simulation and synthesis.

The testbench drives Verilog RTL in Vivado xsim; this is not post-route simulation
or board execution. Reusing old image vectors proves arithmetic consistency,
not held-out semantic accuracy. No thresholds, model weights or image masks
were tuned in this experiment. Prior road false positives/misses remain open.

## Resources and Timing

PDS 2022.2-SP6.1, PGL50H -6 FBG484, final standalone device mapping:

| Resource | Used | Device Total |
| --- | ---: | ---: |
| LUT | 2,913 | 42,800 |
| FF | 3,315 | 64,200 |
| DRM18K | 48 | 134 |
| APM | 23.5 | 84 |

The 10 ns synthesis clock target has an estimated period of 8.966 ns and
1.034 ns positive slack. This is **synthesis-only**: no placement/routing,
external I/O delay constraints, integrated camera/video resource report,
or measured on-board frequency. Separate module budgets must not be presented
as proof that the whole design fits or meets timing.

## Throughput Bound

For an output tile, let G=ceil(Co/16), A=Ow*Oh, and T=K*K for depthwise or
Ci*K*K for ordinary convolution. Starting after the accepted start handshake,
the measured unstalled core cycles are:

```text
28*G + A*(G*(T+8) + Co)
```

The 28 clocks fetch a group's 14 coefficient bytes; T+4 clocks issue/drain MACs;
the four-stage quantizer plus final handshake account for the remaining
per-position overhead. The cycle formula includes successful output handshakes
but not subsequent DDR writes. Input loading is not included in core cycles.

The fixed 320x192 model's 136 supported convolutions require 32,361 tiles:

| Metric | Cycles | Hypothetical Time at 100 MHz |
| --- | ---: | ---: |
| Old serial core | 1,546,275,648 | 15.4628 s |
| New parallel core | 40,883,388 | 0.4088 s |
| Fresh byte loads for every tile | 47,777,472 | 0.4778 s |
| Configuration and start handshakes | 64,722 | 0.00065 s |
| New core plus ideal loads/control | 88,725,582 | 0.8873 s |

Core-cycle speedup is 37.82x. The 0.8873 s figure is NOT measured frame latency:
it excludes DDR latency/arbitration, output writeback, remaining operators and
classifier, camera/display, stalls and routed-frequency limitations. It assumes
one accepted load byte per clock. Weight/coefficients are reloaded for every
tile; overlapping receptive fields also repeat feature loads.

The next useful work is burst ingress/egress and retained coefficients/weights
with a verified layer scheduler, then video-priority DDR arbitration and the
missing operators. Faster arithmetic alone does not establish a real-time
system. A complete low-rate prototype must explicitly associate masks with
frames; stale masks must never be used to justify current-frame road decisions.

## Reproduce

From this experiment directory, with the existing project tools/environment:

```powershell
./tests/run.ps1
./build.ps1
../../.venv-road-model/Scripts/python.exe -X utf8 tests/verify.py
```

The preparation step requires the preceding serial experiment's verified
outputs. `tests/run.ps1 -SkipGenerate` reuses the already prepared vectors.
`verification.json` records final source/evidence hashes; `layer_budget.json`
records each supported layer's exact tile/core/load budget. Neither script
programs the FPGA or modifies the main design.
