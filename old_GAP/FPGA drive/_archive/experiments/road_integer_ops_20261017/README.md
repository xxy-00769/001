# Reusable Integer Operators And First Residual Block

Date: 2026-10-17. This is a correctness/resource experiment, NOT a new camera
bitstream, complete inference engine, or fix for the board's false detections.
No board programming was performed in this step. All 229 protected main RTL,
configuration and named bitstream files remain unchanged.

## Implemented

`source/conv_tile.v` is one reconfigurable serial convolution engine, reused
between tiles/layers. It accepts already quantized uint8 CHW features, signed
INT8 OIHW weights, and per-output-channel Q36 gain/bias. It supports ordinary
1x1/2x2/3x3 convolution, depthwise convolution, stride 1/2, dilation 1..8,
up to 80 input/output channels and output tiles up to 4x4. Padding must be
provided by the caller; there is no image/DDR address translation inside it.

The exporter extracted usable arithmetic contracts for 136 of the candidate
model's 137 convolutions. Each was tested with its actual weights, coefficient
scales and geometry. This does NOT mean 136 connected network layers run on
the FPGA. The final unquantized classifier is explicitly unsupported. MaxPool
preserves its input codes' scales; extracting this metadata is not a hardware
implementation of pooling. ShapeOf-only consumers are ignored when locating
the numerical output quantizer.

`source/residual_requant.v` implements two-input, independently scaled residual
addition with Q36 rounding/clamping, a three-stage backpressured pipeline and
per-segment configuration. Signed real features are represented as unsigned
codes plus folded offsets; simply adding uint8 branch codes would be wrong.

The first residual block's three convolutions (`L0002`, `L0004`, `L0006`) and
residual operation (`L0007` through `L0009` input quantization) are composed in
the integer SOFTWARE reference. Real feature tiles are fed to the RTL by the
testbench. There is not yet an on-chip block/layer scheduler or internal
connection from camera input through these operators to a semantic mask.

## Interface Contract

All signals use one `clk`; no clock-domain crossing or production reset-release
synchronizer is included.

- `cfg_valid && cfg_ready` accepts a fresh convolution descriptor. Geometry
  must exactly match the receptive field: input extent = (output extent-1) *
  stride + (kernel-1) * dilation + 1. Invalid dimensions, unsupported channel
  counts or insufficient RAM capacities cause sticky `fault` until reset.
- Three independently ordered byte banks must then be loaded. Kind 0 is CHW
  input, kind 1 is OIHW weights (one input channel per group for depthwise),
  and kind 2 is coefficients. Bank loads can be interleaved; addresses within
  each bank must start at zero and be consecutive. Reserved kind 3 faults.
- Coefficients are 14 little-endian bytes/channel: signed 48-bit gain, then
  signed 64-bit offset. Required counts are input C*H*W, weights O*I*K*K
  (or O*K*K), and 14*O. Input RAM is 32,768 bytes, weights 8,192 bytes,
  coefficient RAM 1,120 bytes. RAM is not reset or presumed initialized.
- A job starts only after all three banks are fully loaded. A malformed write
  concurrent with start takes precedence and prevents execution. Extra writes
  to a full bank, configuration changes and restarts while busy are ignored
  when their ready signal is low.
- Outputs are CHW with a sequential index and signed 32-bit accumulator debug
  value. Data/index stay fixed during output backpressure. `done` is asserted
  only when the final output is accepted. A new job requires a new descriptor
  and complete fresh loads, including weights. There is no retained-weight
  optimization yet.
- Reset discards partial loads, computation and pending outputs. Faults do
  not publish a partial result as a valid complete tile.
- Residual configuration supplies two signed 48-bit gains, signed 64-bit
  offset and a segment length 1..65,536. Its pipeline freezes on output
  backpressure, including the last-element tag. Reconfiguration waits until
  the last output is consumed. Segments can represent channels/rows; frame IDs
  and stale-frame rejection remain the future scheduler's responsibility.

For convolution, `A` is the exact signed sum of uint8-code * INT8-weight terms:

```text
scaled = A * gain[channel] + offset[channel]
code   = clamp((scaled + 2^35) >> 36, 0, 255)
```

The actual model convolution inputs have zero lower range. Regular convolution
input scales must be uniform; depthwise scales may differ by channel. The
exporter rejects unsupported ranges instead of silently inventing zero points.
Negative output ranges, as on the residual branch, are folded into offset.
For residual addition, `scaled = code_a*gain_a + code_b*gain_b + offset`.
Arithmetic widths are checked against extracted model bounds; caller-supplied
coefficients outside that contract are not validated for model semantics.

## Verification Results

`verification.json` records source/evidence hashes and measured results:

- Six Python unit tests passed: scalar convolution oracle, extraction coverage,
  signed coefficient byte order, bounds, corner padding and invalid shapes.
- 3,214 RTL convolution jobs checked 604,920 signed accumulator/output pairs
  exactly. Cases include all 136 extracted model convolution geometries,
  actual image features, partial tiles, signed extremes and negative gain.
- One road image's three full tensors were reassembled from 960 tiles each:
  122,880 + 122,880 + 245,760 features. Every value matched the integer
  reference. They were separately host-fed layer tests, not a live on-chip
  multi-layer execution test.
- The RTL residual engine checked all 65,536 input-code pairs for the first
  block's uniform coefficients, plus two subsequent coefficient changes.
- Protocol tests include malformed descriptors, out-of-order/incomplete loads,
  reserved banks, concurrent bad-write/start, ignored writes/restarts while
  busy, output stalls, final-output hold, reset during execution and reset with
  a stalled result. Final tests counted 562,820 convolution hold cycles and
  18,364 residual hold cycles.
- Exhaustive numeric audit covered 2,020,142 accumulator/channel combinations
  for the three first-block convolutions and 1,048,576 residual/channel pairs:
  no differences from the specified float64 affine/rounding formulas.
- Across 80,000 isolated OpenVINO operator outputs, one code differs by one
  from the integer implementation; none differ from the float64 affine oracle.
  Across 14 first-block image tensors, 22 of 3,440,640 codes differ from the
  separately compiled native prefix. Native fused execution is NOT bit-exact.

### Full-Network Boundary

`tests/network_check.py` feeds the integer first-layer plus first-residual-block
features into a CPU-executed network tail. It separately compares the native
prefix cut, the unchanged full model, and the older first-layer-only cut.

All 14 reused images retained the same image-level decisions: five of six road
images have some accepted road, and zero of eight nonroad images are accepted.
This is a regression result, not accuracy or independent held-out validation.
The overhead junction remains missed; the dataset also contains AI-generated
road images and has no pixel-labelled ground truth.

Final road masks are NOT identical. Integer substitution versus the native
prefix-cut control changes 67 mask cells on the curved-road image and four on
`legacy_road_3`. The native graph-cut control itself changes 124 curve cells
relative to the uncut model. Integer versus uncut curve masks differ at 81
cells. These overlapping differences must not be added or described as fixes.
Some class probabilities change appreciably without changing the image-level
decision. No threshold was tuned to hide differences. Old road-internal marking
errors, generalization, temporal flicker and scene-switch behavior are unresolved.

## Resource And Throughput Limits

Standalone PGL50H device mapping (two separate designs, NOT an integrated sum):

| Module | LUT | FF | DRM18K | APM |
| --- | ---: | ---: | ---: | ---: |
| Convolution tile | 1,051 | 531 | 21 | 11.5 |
| Residual requantization | 287 | 276 | 0 | 6 |

The initial design violated the 10 ns synthesis clock target. Quantization,
address calculation and RAM-to-multiply paths were pipelined and the same
numeric/protocol regression rerun. Final synthesis estimates report 1.034 ns
and 4.111 ns slack respectively. Earlier failed reports/sources remain under
`tests/output/pre_pipeline`, `quant_pipeline` and `address_pipeline`.

These are synthesis estimates only: NO placement/routing, production I/O
constraints, main-video integration, measured clock, power or board acceptance.
Descriptor/load input paths are not covered by this standalone internal-clock
check and require integrated timing analysis. Fractional APM is the tool's
capacity accounting, not a claim about a fractional physical component.

The serial convolution uses five clocks per MAC term, four per output for
scaling/output handshake, and 28 per output channel for coefficient reads.
The regression checks this formula against actual simulated cycles and stalls.
For the 136 supported model convolutions it totals **1,546,275,648 core clocks**
per frame. Even hypothetically at 100 MHz, that is **15.46 seconds/frame**, before
all RAM loads, DDR stalls, pooling/interpolation, classification and display.
This explicitly rejects the current serial engine as a real-time architecture.
It is a reusable numeric correctness baseline for a parallel/banked successor;
small LUT use is not evidence that a real-time whole-model implementation fits.

## Reproduce

From the project root, using the existing pinned model environment and xsim:

```powershell
./experiments/road_integer_ops_20261017/tests/run.ps1
./.venv-road-model/Scripts/python.exe -X utf8 experiments/road_integer_ops_20261017/tests/precision_audit.py
./.venv-road-model/Scripts/python.exe -X utf8 experiments/road_integer_ops_20261017/tests/network_check.py
./experiments/road_integer_ops_20261017/build.ps1
./.venv-road-model/Scripts/python.exe -X utf8 experiments/road_integer_ops_20261017/tests/verify.py
```

Generation reuses the preceding first-layer experiment's saved input/reference
tensors. Reproduce that experiment first if its `tests/output` is absent. Main
model files/provenance remain pinned in `road_model_budget_20261017`; source
images remain in the existing road-first fixture set. No dependencies changed.
The old model/data licensing and competition-submission restrictions still apply.

The build stops at device mapping and writes separate convolution/residual
reports. It does not invoke a programmer. The simulation runner checks actual
PASS markers rather than trusting exit status; the optional Vivado Webtalk
helper can still report the pre-existing local path warning.

## Next Engineering Work

1. Replace serial MAC scheduling with measured parallel/banked execution and
   reuse weights. Retain these exact integer/protocol tests as the oracle.
2. Implement remaining operators and the unquantized classifier, define all
   residual scales, and validate integer behavior through the entire network.
3. Build the real vendor-DDR requester/arbitration, separate video/inference
   allocations, input preparation, layer scheduler and frame-age rejection.
4. Re-evaluate errors on independent real camera samples and verify the complete
   design's timing, latency and video stability before creating a new bitstream.

The prior v4 programming record is unchanged. This experiment does not authorize
calling v4 a semantic-road solution or reprogramming the board with a prototype.
