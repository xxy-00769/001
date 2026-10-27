# Independent-FPGA Model Feasibility Experiment

Date: 2026-10-17. Offline CPU experiment only; no training, FPGA inference,
new bitstream, camera transfer or vehicle-control output.

## Decision

- Reject direct use of the candidate at 160x96: four of six road images lose
  all accepted road regions. Zero nonroad detections alone is not success.
- Reject unmodified full-resolution OMZ as a replacement for the existing
  semantic baseline: three of eight nonroad images are accepted as road.
- Retain OMZ at 320x192 as a **research candidate**, not a deployment choice:
  five of six road images retain some road, with no accepted road on the eight
  nonroad images in this reused sample. FP32 and published FP16-INT8 both miss
  the overhead junction. The positive count does not measure mask correctness.
- The existing SegFormer still rejects these eight nonroads after 8x8 box-mean
  RGB565 downsampling. This shows the thumbnail contains useful information;
  resizing it back to the model input DOES NOT reduce inference computation.
- No tested configuration is approved for autonomous driving or for replacing
  the board's stable comparison bitstream.

## Fixed Inputs and Postprocessing

All 14 previous images are reused regression cases. Their original
development/holdout names do NOT make them an untouched holdout in this study.
There are six road images (three visibly AI-generated, including one overhead
junction) and eight nonroad images. No pixel ground truth or independent real
camera video exists. Input reuse/redistribution rights are not established.

EXIF-oriented RGB is resized to 1280x720, then quantized and bit-replicated as
RGB565, matching the existing detector. Full-image aspect-ratio distortion
matches the old reference and is not calibration. The 8x8 box-mean path uses
integer channel sums, floor division, and RGB565 requantization, matching the
isolated RTL input experiment. The 4x4 path is a SOFTWARE reference only;
the existing RTL remains fixed at 8x8 and 160x90.

OMZ receives float32 NCHW BGR in the 0..255 range; its graph includes Softmax.
The four output classes are BG, road, curb, mark. Road and mark probabilities
are grouped; BG and curb are competitors. SegFormer uses its pinned saved
normalization and road class 6, with Softmax applied to logits. Scores and
maximum competitor scores are BOX-resized to a common 160x90 mask grid.
Settings fixed before candidate inference:

- Road-group score at least 0.70 and margin against the largest other class
  at least 0.20. These are not calibrated correctness probabilities.
- One-cell erosion on the common grid, four-connected components of at least
  0.5% of the image, and at least 2% total accepted area per frame.
- Nearest-neighbor mask expansion to 1280x720, intersected with unchanged v4
  white/yellow marking candidates. No fixed semantic ROI, lane pair, hole
  filling or lowering of thresholds to rescue the results.

Native OMZ is 896x512. The reduced networks are actually reshaped and executed
at 160x96 and 320x192. Their logical 160x90/320x180 inputs are edge-padded at
the bottom by 6/12 rows, and output padding is removed before postprocessing.
Changing input resolution also changes the learned scale/context distribution.
The padding/resampling policy is part of this experiment, not a validated
deployment preprocessing contract.

The common mask grid and RGB565 model input differ from the older SegFormer
experiment. All configurations are re-evaluated here; old and new per-pixel
counts must not be mixed. Model-to-model mask agreement is NOT accuracy.

## Results

| Configuration | Road images with any accepted road / 6 | Nonroad images falsely accepted / 8 | Nonroad false paint pixels |
| --- | --- | --- | --- |
| SegFormer, full reference | 6 | 0 | 0 |
| SegFormer, 160x90 thumbnail resized to 512x512 | 6 | 0 | 0 |
| OMZ FP32, 896x512 | 6 | 3 | 2,105 |
| OMZ FP32, thumbnail resized to 896x512 | 6 | 4 | 19,929 |
| OMZ FP32, actual 160x96 | 2 | 0 | 0 |
| OMZ FP32, actual 320x192 | 5 | 0 | 0 |
| OMZ published FP16-INT8, 896x512 | 6 | 3 | 1,713 |
| OMZ published FP16-INT8, actual 160x96 | 2 | 0 | 0 |
| OMZ published FP16-INT8, actual 320x192 | 5 | 0 | 0 |

Full OMZ falsely accepts `negative_shelf_dark`, `negative_boxes`, and
`negative_table_window`. A semantic false positive can occur without paint
if it does not intersect the old marking candidates; both metrics are kept.
Thumbnail-upscaled OMZ also falsely accepts `negative_table_brick`.
Both actual 160x96 variants miss `legacy_road_1`, `road_ai_straight`,
`road_ai_curve`, and `road_ai_junction_overhead` entirely.

Visual review also remains necessary on the five accepted road images:
partial acceptance does not guarantee correct boundaries, retained yellow
lines, obstacle exclusion, own-lane identification, or a safe/free path.
The v4 detector still produces texture/highlight false paint inside accepted
road, and its fixed lower-image ROI still limits what can be highlighted.
In the reviewed INT8 320x192 panels, `legacy_road_3` retains many green texture
specks on asphalt. `road_ai_curve` loses sizeable near-field/shadowed road
regions and still paints shadow edges green/cyan. These are retained failures,
even though both images count as having some accepted road.

The retained run is `output_lowmem/results.json`; per-image predictions,
inputs, masks and comparison panels are saved alongside it. See
`output_lowmem/REPORT.md` and `output_lowmem/contact_sheet.png`.
Ten unit tests pass, and `verification.json` records 126 checked output cases,
model provenance verification, and 229 unchanged source/bitstream/config files.
Consistency verification is not an independent accuracy benchmark.

## Hardware Budget

The actual OMZ graph has 97 regular convolutions and 40 grouped/depthwise
convolutions, plus residual adds, ReLU, pooling, five interpolation operations
and Softmax. Published quantization adds FakeQuantize, Convert, scaling and
reshape operations. None of these have been mapped to this FPGA.

| Network input | Convolution MACs/frame | Largest activation elements | Hypothetical INT8 bytes for that tensor |
| --- | --- | --- | --- |
| 896x512 | 2,214,912,000 | 3,670,016 | 3,670,016 |
| 160x96 | 74,160,000 | 122,880 | 122,880 |
| 320x192 | 296,640,000 | 491,520 | 491,520 |

The graph consumes 179,280 convolution weight elements. Published INT8 weight
constants occupy 179,280 bytes, but there are additional floating-point scales,
biases and shape constants. The published `.bin` is 215,040 bytes; file size is
not a hardware memory allocation. The FP32 `.bin` is 737,184 bytes.

The actual device report lists 42,800 LUTs, 64,200 registers, 134 DRM18K and
84 APM. At nominal bit capacity, 134 DRM18K is 308,736 bytes. This is an upper
bound before port width, banking, parity and allocation fragmentation.
The old v6 synthesis used 26.5 DRM18K; the standalone thumbnail buffer used
17. An illustrative subtraction leaves 208,512 nominal bytes. These are
separate builds, NOT an integrated utilization result or current v8 headroom.

Even at hypothetical all-INT8 storage, keeping all convolution weights plus
one largest activation at 160x96 costs 302,160 bytes, exceeding that illustrative
headroom before residuals, accumulators, scales, masks or control. At 320x192,
one largest activation alone exceeds the whole device's nominal block RAM.
This rejects the **fully resident, full-feature-map** scheme, not all possible
tiled/streamed implementations. DDR or carefully scheduled tiles are needed.
MAC counts omit non-convolution work and do not establish DSP use, clock rate,
bandwidth, latency or FPS. CPU timings do not predict FPGA timings.

The existing top wires the video framebuffer directly to the DDR controller
(`source/rtl/hdmi_ddr_ov5640_top.v`, framebuffer ports around lines 317-342 and
DDR ports around 372-392). It does not already expose a separate inference
master. Arbitration, nonoverlapping address allocation, video priority and
vendor-specific handshake validation remain work, not completed features.

The existing SegFormer export contains 3,752,438 initializer elements
(15,009,752 bytes), plus graph constants. It also uses MatMul, normalization,
Softmax and Erf. These counts are not a claim that an accelerator fits.

## Reproduction and Provenance

Use the isolated `.venv-road-model` environment from the project root. The old
`.venv-road-seg` is unchanged. Dependencies are pinned in `requirements.txt`.

```powershell
.\.venv-road-model\Scripts\python.exe -m pip install -r experiments/road_model_budget_20261017/requirements.txt
.\.venv-road-model\Scripts\python.exe experiments/road_model_budget_20261017/fetch_model.py
.\.venv-road-model\Scripts\python.exe -m unittest discover -s experiments/road_model_budget_20261017 -p test_evaluate.py -v
.\.venv-road-model\Scripts\python.exe experiments/road_model_budget_20261017/evaluate.py --output experiments/road_model_budget_20261017/output_reproduction
.\.venv-road-model\Scripts\python.exe experiments/road_model_budget_20261017/verify_results.py --output experiments/road_model_budget_20261017/output_reproduction
```

Evaluation refuses to overwrite existing output directories. Verification
regenerates the selected run's report/contact sheet and the small experiment
`verification.json`; use a different checkout to preserve that manifest too.
The first run in `output/` aborted on host memory allocation and is retained
as incomplete evidence. It is not included in the result table. The completed
retry disables the ONNX Runtime CPU arena/memory patterns, uses in-place
Softmax temporaries, and releases the previous session before the next model.
Four CPU inference threads and one stream/session were used. Timings are
single-image measurements under variable host load, not stable benchmarks;
loading, pre/postprocessing, transfers, file compression and display are excluded.

OMZ is pinned to release 2023.0.0, commit
`27a654e312e7aa89ad72648784753d522e3a0a4e`. Model metadata, README,
accuracy configuration and repository Apache-2.0 license are saved locally.
`fetch_model.py` follows the pinned YAML's URLs and checks every downloaded
model against publisher sizes and SHA384 checksums. `model_provenance.json`
records URLs and SHA256 hashes. Saving the license does not resolve all
competition submission, third-party data or redistribution questions.
The previously pinned SegFormer and its research-use restrictions are unchanged.

## Next Acceptance Gates

1. Obtain pixel-labelled real camera cases and independent negative scenes.
   Include the existing overhead-junction failure; do not silently redefine
   the user's supported road types to make the score improve. Track false-road
   area, missed road, boundary errors and temporal flicker separately.
2. For the retained 320x192 candidate, validate deployable integer arithmetic
   layer-by-layer, including per-channel scales, saturation, interpolation and
   residual alignment. Published OpenVINO quantization is not an RTL engine.
3. Prototype tiled convolution and DDR scheduling in an isolated experiment;
   measure actual PDS resources and timing before promising a frame rate.
   A new 4x4 input path also needs its own RTL regression and memory plan.
4. Integrate only after semantic and resource checks: preserve full display,
   match masks to source frame IDs, reject stale/incomplete inference and avoid
   overlaying an old road mask onto a new scene. Then generate a separately
   named experimental bitstream and perform bench tests, not live driving.

Until those gates pass, `4_road_markings_filtered_cmos1.sbit` stays untouched
as the display/marking comparison baseline, not a semantic-road solution.

## Subsequent First-Layer Prototype

`../road_integer_l0_20261017/README.md` records a later Q36 first-layer RTL
prototype, 589,824 bit-exact reference checks, and standalone synthesis/device
mapping. Its software memory plan is not an actual DDR master. Replacing only
this layer in a CPU-tail regression preserves image decisions but not all mask
boundaries. It does not change this experiment's model-suitability decision or
prove the whole network deployable.
