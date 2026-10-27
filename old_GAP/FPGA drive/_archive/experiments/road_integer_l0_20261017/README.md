# First-Layer Integer Hardware Prototype

Date: 2026-10-17. Isolated experiment for the retained 320x192 OMZ research
candidate. This is not a full road detector, board integration or new bitstream.
The original camera, display, RTL and named bitstreams are unchanged.

## Implemented Boundary

`source/layer0_tile.v` implements only the first network layer:

1. Accept a complete 17x17x3 raw uint8 BGR tile (867 bytes), including externally
   supplied zero padding. Convert each input through a model-derived 256-entry
   quantization LUT before storing it.
2. Apply the actual 16x3x3x3 signed INT8 weights, stride two, one reused MAC.
   Accumulate all 27 terms in a signed 24-bit register.
3. Apply per-output-channel Q36 scaling and bias, nonnegative activation,
   half-up rounding and saturation to uint8. This produces the feature codes
   consumed by `L0002_Conv2d_BN/WithoutBiases/fq_input_0`, including its residual
   consumer `L0007_AddBackward1`.
4. Emit 16x8x8 features, with a debug signed accumulator, using ready/valid
   backpressure. No new tile can overwrite the current computation.

The parameter ROM is generated from the pinned published FP16-INT8 model,
not handwritten demonstration weights. This includes the compressed model's
FP16 bias values. Model/input provenance and license metadata remain in the
previous `road_model_budget_20261017` experiment. These derived parameters are
for local research; competition submission/redistribution has not been approved.

All other convolutions, residual scheduling, pooling, interpolation, Softmax,
semantic-mask cleanup and display integration are outside this RTL prototype.
It is a serial correctness baseline, not the final throughput architecture.

## Arithmetic Contract

The input FakeQuantize range is 0..253.56333923339844 with 256 levels; the next
activation range is 0..7.945451736450195 with 256 levels. Every possible raw
channel value 0..255 is checked against OpenVINO's isolated input quantizer.

Let `A` be the signed integer convolution sum, `sx` the input step, `sw[c]`
the per-channel weight step, `sy` the output step and `b[c]` the model bias:

```text
gain[c]   = round_half_up((sx * sw[c] / sy) * 2^36)
offset[c] = round_half_up((b[c] / sy) * 2^36)
fixed     = A * gain[c] + offset[c]
output    = clamp((fixed + 2^35) >> 36, 0, 255)
```

RTL uses a signed 32-bit gain, signed 48-bit offset, 56-bit product and 57-bit
sum. Bounds are checked over every channel's possible accumulator interval.
The source input and its unsigned extension are explicit: raw value 255 must
not be interpreted as signed -1.

Q30 was tried first and rejected for unnecessary rounding errors. An exhaustive
audit of 1,908,946 accumulator/channel pairs found 13 differing output codes
at Q30, one at Q34, and zero at Q36 against the float64 affine oracle.
Q36 was selected using that complete bounded numeric domain, not by tuning
thresholds on particular road images. See `precision_audit.json`.
This is numeric comparison, not a formal equivalence proof to OpenVINO's
float32/fused execution or a claim about segmentation accuracy.

The earlier Q30 results are retained in `q30_reference.json` and
`q30_network_check.json`. Q30 had nine differing first-layer codes across
5,160,960 feature values. On the overhead-junction example, a two-code
difference could produce a 0.416 maximum change in a final class score while
the image still had no accepted road. Small early errors cannot simply be
declared harmless. Network-cut effects are measured separately from integer
substitution effects.

## Module Interface

All ports use one `clk` domain. A production reset must be released with the
appropriate clock-domain synchronization; no CDC logic is implemented here.

| Signal | Contract |
| --- | --- |
| `load_valid`, `load_ready` | A byte is accepted only on both high at the clock edge. |
| `load_addr[9:0]` | Must be exactly 0..866 in order. Skipped/repeated/out-of-order accepted addresses set sticky `fault`. |
| `load_data[7:0]` | Unquantized BGR byte, HWC order. |
| `start_valid`, `start_ready` | Start only after all 867 input bytes have been accepted. A start alongside the final byte must wait for ready on the following cycle. |
| `out_valid`, `out_ready` | Output data/index/accumulator stay unchanged while valid and not ready. |
| `out_index[9:0]` | Tile-local CHW order: channel in bits 9:6, row in 5:3, column in 2:0. |
| `out_data[7:0]` | Quantized first-layer feature, not a road classification. |
| `out_acc[31:0]` | Sign-extended integer sum, for verification. |
| `done` | One cycle after the final output is accepted; not asserted merely because the final value was computed. |
| `fault` | Stays set until reset; no partially loaded tile can be started. |

Writes or restarts while not ready are not accepted. Reset cancels a running
job and its pending output. RAM is not reset, but every new job requires all
867 bytes to be freshly loaded. Tile/frame identities are managed externally;
the module has no live-camera frame counter, mask freshness policy or host bus.

## Verification

`tests/run.ps1` executes unit tests, regenerates fixed numeric references,
compiles RTL with Vivado xsim, and runs 575 distinct tile cases plus one repeat
after a mid-computation reset. The scoreboard checks both the signed sum and
quantized feature value, not just a checksum.

- Two complete first-layer feature tensors: `legacy_road_3` and
  `negative_shelf_dark`, each reconstructed from all 240 tiles.
- Five corner/central tiles from each of the other 12 images, plus random,
  checkerboard, black, white and primary-color frames.
- Gaps during input, rejected out-of-order input, incomplete tile startup,
  blocked extra input, attempted writes/restarts during computation, output
  stalls, reset during MAC and reset during a stalled output.
- Software first-layer comparisons over all 14 images and seven patterns:
  21 x 245,760 = 5,160,960 feature values. This tests arithmetic, not road labels.
- `network_check.py` substitutes only the fixed-point first-layer reference
  into the CPU network tail and compares 14 previously inspected images. It
  also runs a control using the isolated OpenVINO first-layer codes, because
  cutting/recompiling the graph can itself change fused arithmetic.

The final measured counts, resource reports, source hashes and remaining
network-mask differences are recorded in `verification.json` and
`tests/output/network_check.json`. A passing image-level regression does not
imply identical probabilities, identical masks or correct road boundaries.
The Q36 run has 589,824 bit-exact RTL outputs (576 jobs), including the repeated
reset-recovery job. Of 5,160,960 software first-layer feature codes, two differ
from the isolated OpenVINO execution by one code; none differ from the float64
affine formula on these inputs. The nine unit tests also cover the entire
bounded accumulator domain, all 240 read plans and random-order masked writes.

In the 14-image CPU-tail substitution regression, all image-level decisions
remain unchanged. However, `road_ai_curve` changes 50 cells on the 160x90
accepted-road grid due to integer-vs-native first-layer rounding. Separately,
`legacy_road_3` changes 17 mask cells in the graph-cut control, without any
integer-vs-control feature difference. `negative_desk_window` has a maximum
class-score change of about 0.151 from the substitution but still no accepted
road. Therefore the final masks are NOT equivalent; these differences must
remain visible in further deployment validation. No threshold was retuned.

The original model's overhead-junction miss and road-internal marking errors
have not been fixed by this arithmetic work.

## Memory Transfer Plan

`reference.py` implements a SOFTWARE transfer planner and byte-strobe replay,
not a synthesizable DMA or the board's DDR controller interface.

- Full input: 320x192x3 BGR, HWC, 184,320 bytes. The previous 4x4 software
  reference creates 320x180 RGB565-derived pixels, with 12 bottom rows repeated.
  The existing 160x90 input RTL was not changed to this format.
- Tile origin is `(16*tx-1, 16*ty-1)` in input coordinates. Top/left out-of-image
  samples are locally zero-filled. The 20x12 output-tile grid covers 160x96.
- Reads are aligned 32-byte transfers, with per-row extraction and local
  padding. Replaying all tile plans against a byte array must match direct
  tile extraction.
- Outputs are written into a 16x96x160 CHW feature allocation, 245,760 bytes.
  Each eight-byte tile row uses a 32-byte aligned write with an explicit
  eight-byte strobe. Random-order replay checks untouched neighbors and guard
  bytes; blindly writing the other 24 bytes would corrupt adjacent tiles.
- One full first-layer pass requests 318,304 aligned read bytes. The simple
  non-coalesced output plan requests 983,040 write-bus bytes for 245,760 payload
  bytes. These are software schedule counts, not measured DDR bandwidth.

The synthetic bases `0x100000` and `0x200000` are separate test allocations
only. They are not reserved in the actual video framebuffer. Addresses here
are bytes; the vendor controller's address units, ID behavior, write-data
request ordering and byte-enable semantics must be checked before connection.
No existing video arbitration, burst timing, controller backpressure, timeout,
reset recovery or frame freshness is covered by this software memory replay.

## Resource and Timing Boundary

The PDS flow stops after synthesis and device mapping on PGL50H. It does not
place/route, assign production pins, add a target-frequency constraint or
generate a bitstream. The automatically inferred 1000 ns clock is not a useful
performance target or a timing signoff. The 10 ns simulation clock is likewise
only a testbench timebase, not a claim that hardware meets 100 MHz.

For the final Q36 RTL, synthesis reports 383 LUTs, 90 registers, 1 DRM18K and
4.5 APM units. Device mapping reports 384 LUTs with the same other counts.
The fractional APM figure is the tool's SIMD-capacity accounting, not a claim
about a fractional physical component. These figures include the first-layer
parameter ROM and tile storage only, not the video design or remaining network.
The earlier Q30 mapping used 369 LUTs and 4 APM; that is superseded, not the
resource figure for the final verified source.

The serial engine uses 56 cycles per output without stalls: 27 synchronous
reads, 27 MAC cycles, quantization and output consumption. Thus it needs
57,344 compute cycles per tile and 13,762,560 per first-layer frame, excluding
input transfer and stalls. No full-model FPS follows from these counts.
The selected full candidate still has about 296.64 million convolution MACs
per frame, with many operators and memory dependencies not yet implemented.

PDS also reports that the local license has 17 days remaining at build time.
This warning did not stop the build, but the license needs attention before
future builds. An initial xsim elaboration required explicit module timescales;
those were added. A separate first-run Webtalk path warning did not affect the
subsequent clean simulation pass; it is not an RTL correctness signal.

## Reproduce

From the main project directory, using the existing isolated model environment:

```powershell
./experiments/road_integer_l0_20261017/tests/run.ps1
./.venv-road-model/Scripts/python.exe experiments/road_integer_l0_20261017/tests/network_check.py
./.venv-road-model/Scripts/python.exe experiments/road_integer_l0_20261017/tests/precision_audit.py
```

In this experiment directory, run these as separate commands:

```powershell
Copy-Item -LiteralPath flow.tcl -Destination impl.tcl
& 'D:/PDS/PDS_2022.2-SP6.1/bin/pds_shell.exe' impl.tcl *> synthesis.log
```

Then from the main project directory:

```powershell
./.venv-road-model/Scripts/python.exe experiments/road_integer_l0_20261017/tests/verify.py
```

Tests regenerate `tests/output/` and the derived parameter ROM; PDS writes only
this experiment's build directories. `flow.tcl` must be copied because PDS
appends to its input script. Do not use or overwrite the old named bitstreams.

## Remaining Work

The next arithmetic primitives are pointwise and depthwise convolutions, then
residual addition and their independent scaling rules. The tile/weight scheduler
must become configurable so hardware is reused across layers, not instantiated
once per layer. Network-cut and native-float rounding differences need a clear
integer deployment contract, not image-specific threshold adjustments.

Separately, implement and simulate a real DDR requester/arbiter with the
existing vendor/video handshake, preserving video priority and nonoverlapping
memory. Only after numerical, semantic, timing, memory and stale-frame checks
pass should the prototype enter the main video design and produce a separately
named experimental bitstream. Bench verification is not real-driving validation.
