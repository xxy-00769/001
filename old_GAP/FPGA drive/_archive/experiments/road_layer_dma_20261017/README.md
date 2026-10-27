# Whole-Layer DMA and Writeback

Date: 2026-10-17. Functional RTL simulation passed. Synthesis/device mapping
completed, but the 10 ns clock target FAILED. No board programming or new
bitstream. The v4 baseline and 229 protected main files are unchanged.

This stage moves complete convolution tensors through a simulated memory,
not camera pixels through a complete semantic road model. No road-accuracy
improvement is claimed. Real DDR integration remains unimplemented.

## Implemented

`source/conv_layer_dma.v` wraps the unchanged prior `conv_cached.v`:

- Accept one layer descriptor while idle and validate geometry, address ranges,
  output overlap, reserved bits and tile storage capacity before memory access.
- Iterate 4x4 output tiles, including partial right/bottom edge tiles.
- Load weights/coefficients for the first tile only, retaining them thereafter.
  Input features are reloaded per tile. Padding is generated locally as zero.
- Pack output channel bytes into 128-bit words with exact low-lane write masks.
  Validate the core's CHW tile indices before packing each byte.
- Wait for every write acknowledgement, including the final write, and core
  completion before asserting the one-cycle `done` pulse and publishing its ID.
- Latch errors, reset the core and stop new memory requests until external reset.

No loading/computation overlap, multiple outstanding requests, bursts, layer
queue, autonomous network controller, input-layout converter or watchdog is
implemented. Missing acknowledgements stall execution until reset. An external
controller must manage tensor lifetimes and submit subsequent layer descriptors.

## Memory Contract

The interface is an abstract, tagged, single-outstanding protocol, NOT AXI and
NOT the board's vendor DDR interface. The main framebuffer uses 256-bit data;
this 128-bit interface must not be wired directly to it.

- `mem_req_valid/ready` accepts a request on a rising clock edge.
- `mem_req_addr` is a 32-bit **128-bit word address**, not a byte address.
- `mem_req_write` distinguishes writes from reads. Read data/strobes are zero.
- `mem_req_data` carries writes; `mem_req_strb` selects the bytes to overwrite.
- Both reads and writes require a subsequent `mem_rsp_valid/ready` handshake.
  Zero-cycle response pulses are unsupported; hold a response until accepted.
- `mem_req_tag = {job_id[31:0], sequence[31:0]}`. Sequence starts at zero for each
  accepted job and increments on accepted requests. Responses echo the exact tag.
- A write response means the selected bytes have been committed and are visible
  to later reads. This ordering is required for chained layers.
- A memory error or wrong response tag faults the layer. Previously acknowledged
  writes are not rolled back, and a failing write may have partially committed
  in a real adapter. A failed output tensor must not be consumed.
- `result_job_id` changes only on success, retaining the previous successful ID
  across a failed job. Reset clears it. `busy` remains high in the fault state.

Use unique job IDs while old transactions can still exist, including across
engine resets. Either drain/flush/reset the adapter together with the engine or
use a new ID and handle any stale response as an error. Reusing an ID/sequence
does not magically distinguish stale traffic. No wraparound management exists.

The tests commit masked writes at the response handshake, deliberately delay
the final acknowledgement, and never refill intermediate feature buffers.

## Descriptor

One 320-bit value is captured only on `cfg_valid && cfg_ready`:

| Bits | Field |
| --- | --- |
| 31:0 | Job ID |
| 63:32 | Input base word address |
| 95:64 | Output base word address |
| 127:96 | Weight base word address |
| 159:128 | Coefficient base word address |
| 191:160 | Arena base word address |
| 223:192 | Arena exclusive limit word address |
| 230:224 | Input channels |
| 237:231 | Output channels |
| 239:238 | Kernel size |
| 241:240 | Stride |
| 245:242 | Dilation |
| 250:246 | Symmetric padding |
| 260:251 | Full input width |
| 270:261 | Full input height |
| 280:271 | Full output width |
| 290:281 | Full output height |
| 291 | Depthwise mode |
| 319:292 | Reserved, must be zero |

Channels: 1..80; kernel: 1..3; stride: 1..2; dilation: 1..8;
padding: 0..16; dimensions: 1..1023. Output dimensions must exactly match
the floor convolution formula. Depthwise requires equal input/output channels.
Tile storage limits still apply, so not every combination is supported.

All four nonempty ranges must fit the arena without 32-bit endpoint overflow.
Output must be disjoint from input, weights and coefficients. Read-only regions
may alias; their contents remain the caller's responsibility. The exclusive
limit cannot represent 2^32, so the final 32-bit word address is not usable.

## Layout

Every lane contains one byte; lane 0 is `data[7:0]`.

```text
Features: [channel_group][height][width][16 lanes]
address = base + (group * H + y) * W + x

Weights: [output_channel_group][position][16 lanes]
position = input_channel * K*K + ky*K + kx
Depthwise weights have only K*K positions per channel.

Coefficients: [output_channel_group][byte_position=0..13][16 lanes]
Each channel has signed little-endian 48-bit gain, then signed 64-bit offset.
```

Features are unsigned 8-bit codes; weights are signed INT8; quantization uses
the previously verified Q36 convention. Padding is code zero, which requires
the supported model's zero input lower bound. This is not a general arbitrary
zero-point quantized convolution. Unused high lanes are ignored on reads and
preserved by output write strobes. CHW bytes cannot be fed as striped words.

## Verification

Run from this directory in PowerShell:

```powershell
./tests/run.ps1
./build.ps1
../../.venv-road-model/Scripts/python.exe -X utf8 tests/verify.py
```

Tools: Vivado 2018.3 simulator and PDS 2022.2-SP6.1. The generator checks pinned
previous-stage artifacts and model files. The build scripts hash source/vector
inputs before and after execution. Large reproducible vectors/logs are ignored
by Git; `verification.json` records their hashes and measured test counts.

- 29 successful layer jobs plus a separate post-fault/reset recovery job.
- 518,967 exact output bytes in 49,923 word writes; 33,103 partial-channel writes.
- 124,374 memory transactions, 3,462 tiles, 3,433 retained-weight tile reuses.
- 8,008 locally generated zero-padding vectors; 74,027 final memory words
  checked, including untouched read-only regions, guards and high tail lanes.
- 26 synthetic layers cover random/signed data, channel groups, K=1/2/3,
  stride, dilation, mostly-padding inputs, partial tiles and 1023-wide/tall inputs.
  Small golden cases also use an independently indexed scalar convolution.
- Three model-derived layers use the saved `legacy_road_3` input features:
  L0002, L0004 and L0006 produce 491,520 bytes in 2,661,008 simulated cycles.
  Each layer reads its predecessor's actual writes without host intermediate
  reloads. Residual addition is not connected, so this is NOT a complete block.
- Deterministic request backpressure, delayed responses, stable stalled requests,
  exact request tags/addresses/strobes and ignored busy configuration changes.
- 18 fault cases cover invalid geometry/reserved bits, output overlap, range
  overflow, storage limits, read/write errors, wrong tags, core faults, output
  index corruption and invalid FSM state. A failure after success retains its ID.
- Two shared engine/adapter resets interrupt a pending read and a pending write.
  Recovery and delayed final acknowledgement are explicitly checked.

The memory timing includes test-probe overhead. It is not a DDR bandwidth result,
full-frame inference latency, semantic accuracy test or on-board observation.

## Mapping and Timing

Core plus DMA plus the test-only multiplexed probe maps to 4,905 LUT, 4,889 FF,
48 DRM18K, 37.5 APM and 172 IO. This is not the resource cost of the main camera/
DDR/display system, and the probe is not a production pin interface.

The 10 ns synthesis target is **not met**: estimated period 13.133 ns, slack
-3.133 ns. Splitting the new geometry/size calculations removed the original
scheduler bottleneck; the reported worst path now enters the reused core's
configuration validation/cache-valid logic from the layer's kernel register.
The previous isolated core had unconstrained external configuration ports, so
its internal timing result did not establish this newly registered path.
No false-path or multicycle exceptions were added to hide this violation.

There is no placement/routing or external IO timing closure. Do not treat either
the target 100 MHz or the synthesis frequency estimate as achieved board speed.
The verifier records mapping success and functional success separately from
`target_timing_passed=false` and `deployment_approved=false`.

## Fault Codes and Next Work

Codes: 1 geometry, 2 ranges/overlap, 3 capacity, 4 core fault, 5 memory error,
6 response tag, 7 output order, 8 reserved descriptor bits, 9 invalid FSM.

Next: pipeline/prove the registered core configuration path, then implement a
separately verified 128-to-256-bit vendor-memory adapter with video-priority
arbitration. Complete model scheduling, residual/other operators, classifier,
input geometry/layout, resource integration and camera-based semantic evaluation
are still required before a new independent road-recognition bitstream.
