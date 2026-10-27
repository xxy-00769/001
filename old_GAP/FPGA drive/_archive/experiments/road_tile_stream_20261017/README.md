# Retained Weights and Banked Tile Ingress

Date: 2026-10-17. Isolated RTL, simulation and synthesis/device mapping.
No board programming, new `.sbit`, DDR controller connection, complete layer
scheduler, camera integration or road-accuracy improvement is delivered here.
The user's v4 baseline and 229 protected main files are unchanged.

## Implemented

`source/conv_cached.v` extends the previous sixteen-lane convolution engine:

- Retain one layer's INT8 weights and Q36 gain/offset bytes between tiles.
- Explicit cache identity and shape checks before accepting a reuse request.
- Select either the original byte-loading interface or a 128-bit channel-banked
  input interface for each descriptor. Only the selected interface is ready.
- Exact address, tail-mask and completeness checks before computation.
- Preserve the existing arithmetic and indexed output ordering.

There is still only one layer's weight storage, not a full-model weight cache.
Loading and computation do not overlap. Coefficient RAM is still read at each
channel group inside a tile; retention avoids host reloads, not that core cost.
The shared four-stage quantizer and sixteen-lane MAC pipeline are unchanged.

## Cache Contract

Every descriptor supplies `cfg_weights_id`, `cfg_reuse` and `cfg_banked_load`.

1. A fresh descriptor (`cfg_reuse=0`) immediately invalidates any old cache.
   All input, weight and coefficient bytes must be loaded. The cache becomes
   valid only when a fully loaded job successfully starts.
2. A reuse descriptor requires a valid cache, exactly matching 32-bit identity,
   and matching depthwise mode, input/output channels and kernel size. Otherwise
   it faults; there is no silent fallback to old data or an incomplete reload.
3. Input dimensions, output tile dimensions, stride and dilation may change
   subject to the original geometry/capacity checks. Their pixels must always
   be reloaded. Weight/coefficient writes are not accepted during reuse.
4. Reset, malformed accepted input, invalid configuration or invalid FSM state
   invalidates the cache. An aborted load or pre-reset RAM content cannot be
   reused. No cache hit can bypass the new tile's input-completeness check.
5. Configuration is accepted only while idle. A new layer cannot replace
   coefficients while computation or a final stalled output is pending.

The identity is a **caller-managed version token, not a hardware content hash**.
The caller must assign a new identity when either weights or quantization
coefficients change, and must avoid stale token reuse. Identical shapes alone
are insufficient. The test generator derives identities from content/shape
hashes; that generator is not an on-chip hashing or model-management system.

## Banked Format

`cfg_banked_load=0` preserves the byte stream (CHW inputs, OIHW weights,
14 little-endian coefficient bytes per channel). `cfg_banked_load=1` uses:

```text
vec_kind: 0 = input, 1 = weight, 2 = coefficient; 3 is invalid
vec_addr: consecutive local word addresses starting at zero, independently per kind
vec_data[8*lane +: 8]: byte for channel (16*group + lane)
vec_keep: all low active-channel bits set, high inactive-channel bits clear
```

For each kind let P be bytes per channel: input P=Iw*Ih, weight
P=(depthwise ? 1 : Ci)*K*K, coefficient P=14. The layout is
`[channel_group][position_within_channel][16 lanes]`:

```text
vec_addr = group*P + position
logical byte index = (group*16 + lane)*P + position
physical byte offset in a prepacked buffer = vec_addr*16 + lane
```

The input channel count is Ci; the other two kinds use Co. An exact low-bit
mask is required for the final partial channel group. The test vectors put
nonzero poison bytes in unused lanes to verify they are ignored. Sparse masks,
empty masks, wrong tail masks and skipped/repeated accepted addresses fault.
Complete banks are not ready and ignore additional writes, as in the byte mode.

This is an internal tile-load protocol, **not AXI, a DDR burst master, or a
linear CHW-to-wide converter**. Input features/weights must already be arranged
in the banked format or produced by a future adapter. Merely reading 16 adjacent
CHW bytes from DDR does not produce this layout. The current test packing is
offline software. A future independent design must generate/store the layout
on board, including halo padding and partial tiles, without relying on a PC.

Bank allocations remain 16x4,096 input bytes, 16x1,024 weight bytes and 16x128
coefficient bytes. Logical descriptor limits are unchanged. Output remains
one indexed code/accumulator per handshake in channel-group, row, column, lane
order; it is not automatically written back or packed for DDR.

## Verification

There are three passes over 3,285 fixed cases:

- Fresh byte loads, preserving the previous interface behavior.
- Fresh banked loads, covering all shapes and exact tail masks.
- Alternating byte/banked loads with content-matched reuse between adjacent
  cases, including different real-image tiles and changed geometry.

The 3,281 previous cases are unchanged. Four additional cases deliberately
reuse the same actual layer weights/coefficients while changing input/output
dimensions, stride and dilation. Vector packing is checked against the original
byte arrays, and all outputs are checked by CHW destination index, not arrival
order. Python arbitrary precision is used for extreme quantization cases in
the inherited reference data.

Final evidence is recorded by `tests/verify.py` in `verification.json`:

- 9,855 jobs, 1,874,628 accumulator/code pairs exactly match the references.
- 3,037 adjacent jobs use retained weights, with fresh input required each time.
- 210,944 banked words independently checked against their logical byte arrays.
- 1,027,260 stalled output cycles checked with stable data and delayed completion.
- Exact accepted-byte/beat counts and core-cycle formula checked for every job.
- Wrong cache ID, mismatched channels/kernel/mode, reuse before loading and
  reuse after reset all reject the request.
- Invalid bank/mask/address, incomplete transfers, full-bank overwrite attempts,
  busy mutation, reset during MAC/output and start/write races are exercised.
- The shared-payload synthesis probe matches direct-core status and valid data
  cycle-for-cycle through the full suite, including failure cases.

This is RTL simulation, not post-route simulation or measured board behavior.
It reuses known image/model vectors and is not a new semantic accuracy test.
Previous road misses and false positives remain open.

## Synthesis Probe

A standalone top exposes every internal interface as package pins. Directly
mapping `conv_cached` required 361 I/Os, exceeding the FBG484 budget of 296.
That failed build is retained under `tests/output/direct_io_failure`.

`source/conv_stream_probe.v` shares the configuration and load payload pins
between their disjoint accepted phases. It does not change the core and does
not tie off a datapath. Control strobes remain independent. The complete core
output and cache/status interfaces remain observable, and the probe is tested
against the direct core. This is a resource-estimation shell, NOT a proposed
board pinout or production bus. Main-design integration will use internal
signals, not 266 additional external pins.

PDS 2022.2-SP6.1, PGL50H -6 FBG484, final core-plus-probe device mapping:

| Resource | Used | Device Total |
| --- | ---: | ---: |
| LUT | 3,609 | 42,800 |
| FF | 3,455 | 64,200 |
| DRM18K | 48 | 134 |
| APM | 23.5 | 84 |
| Probe I/O | 266 | 296 |

The final 10 ns synthesis target has estimated period 8.884 ns, slack +1.116 ns.
The first probe version failed with -1.739 ns slack; its tail count/mask was
calculated on every accepted word. Masks/counts are now registered at descriptor
and channel-group boundaries. The failing report/source is retained in
`tests/output/pre_registered_masks`, not used as final evidence.

There is no placement/routing, external I/O delay constraint, production pin
assignment, integrated video utilization report, or measured clock frequency.
This report cannot establish integrated timing or final device headroom.

## Throughput Bound

The 136 supported convolution contracts still require 40,883,388 unstalled
core cycles across 32,361 tiles at model input 320x192. The final classifier and
remaining operators are not included. The core formula is unchanged:

```text
G = ceil(Co/16)
T = K*K for depthwise; Ci*K*K otherwise
core cycles/tile = 28*G + Ow*Oh*(G*(T+8) + Co)
```

Model-derived load budgets, assuming one accepted byte/word every clock:

| Load Policy | Load Cycles | Core + Load + Control at Hypothetical 100 MHz |
| --- | ---: | ---: |
| Byte, reload each tile | 47,777,472 | 0.88726 s |
| Byte, retain per layer | 19,199,616 | 0.60148 s |
| Banked, reload each tile | 3,500,382 | 0.44448 s |
| Banked, retain per layer | 1,473,001 | 0.42421 s |

Control adds 64,722 configuration/start cycles. Retention assumes each layer's
tiles run consecutively with one fresh weight/coefficients load. The final
policy reduces load cycles by 32.44x; arithmetic cycles do not change. The
last figure is not measured frame latency or a real-time-system claim.

The ideal banked reads transfer 23,568,016 physical bytes, including inactive
tail lanes, for 19,199,616 useful input/weight/coefficient bytes. Fewer bus cycles
do not mean proportionally fewer physical bytes. Overlapping tile inputs are
still loaded repeatedly.

These bounds exclude DDR/layout-conversion costs, output writeback, missing
operators/classifier, video arbitration, stalls, camera/display and routed
frequency. In particular, this work does not solve the DDR interface or make
the model suitable for autonomous driving. The next implementation boundary
is indexed output packing and a verified tile/layer DMA schedule, followed by
the actual video-priority DDR adapter and remaining model operators.

## Reproduce

From this directory, using the existing project tools/environment:

```powershell
./tests/run.ps1
./build.ps1
../../.venv-road-model/Scripts/python.exe -X utf8 tests/verify.py
```

The preparation step requires the preceding parallel experiment's verified
files. `-SkipGenerate` reuses the prepared vectors. Final verification checks
previous/current source/evidence hashes, all saved outputs and transfer counts,
protected main files, model provenance and the model-derived load budget.
`layer_budget.json` provides per-layer details. None of these scripts programs
the FPGA or writes the main video design.
