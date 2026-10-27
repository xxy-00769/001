# Offline Road-First Prototype

This is a local CPU evaluation, not new FPGA firmware. It gates the unchanged
v4 marking-reference output with a pretrained semantic road mask. No training,
camera capture, FPGA/MCU connection, binocular processing or control is included.
The existing named bitstreams remain unchanged. Do not use this for driving.

## Current Evidence

- See `tests/ROAD_FIRST.md` for the Chinese findings and known failures.
- Inputs: 11 newly supplied images plus 3 existing road fixtures, 14 in total.
- Development and holdout: each 3 road-positive and 4 road-negative images.
- All 8 negatives have empty retained masks; all 6 positives retain some road.
- These are image-level counts, NOT pixel accuracy or a generalization guarantee.
- The overhead intersection loses substantial road/crosswalk coverage. Other
  images retain in-road marking noise and lose parts of actual yellow markings.
- No parameters were changed after viewing the holdout results. For further
  tuning, this inspected holdout is now a regression set, not a fresh test set.

## Run Locally

Run PowerShell from the project root. The existing `.venv-road-seg` is usable;
it was created with system-site-packages to inherit local NumPy and Pillow.
For a new environment instead:

```powershell
py -3 -m venv .venv-road-seg
.\.venv-road-seg\Scripts\python.exe -m pip install -r host/road_first/requirements.txt
```

Model assets already exist under `models/road_first/segformer_b0_ade/`.
Evaluation does not download anything or upload images. Use a new output
directory for every run; existing results are never overwritten:

```powershell
.\.venv-road-seg\Scripts\python.exe -X utf8 tests/test_road_first.py
.\.venv-road-seg\Scripts\python.exe -X utf8 host/road_first/evaluate.py --split development --output tests/output/road_first_dev_repeat
.\.venv-road-seg\Scripts\python.exe -X utf8 host/road_first/evaluate.py --split holdout --output tests/output/road_first_holdout_repeat
.\.venv-road-seg\Scripts\python.exe -X utf8 tests/verify_road_first_results.py --rerun-inference --development tests/output/road_first_dev_repeat --holdout tests/output/road_first_holdout_repeat --output tests/output/road_first_audit_repeat
```

The verifier audits the fixed 14-image experiment, not arbitrary new datasets.
It checks split membership, input/config/model hashes, saved logits and masks,
exact RGB overlays and metrics, and original baseline/bitstream hashes.
`--rerun-inference` also compares fresh CPU logits and requires identical masks.
It shares mask-processing functions with the evaluator, so it is a consistency
check supported by unit tests, not an independent semantic-accuracy evaluation.
Its JSON records exact installed package versions and artifact hashes.
Comparison-panel generation currently uses Windows Arial.

## Processing Contract

1. Apply EXIF orientation, convert to RGB and resize to 1280 x 720. The resize
   matches the old reference workflow; portrait inputs are distorted.
2. Feed this RGB image through the export's 512 x 512 bilinear resize, /255,
   RGB means `[0.485, 0.456, 0.406]` and standard deviations
   `[0.229, 0.224, 0.225]`. Model input is not RGB565-quantized.
3. Use native 150 x 128 x 128 logits. `config.json` labels class 6 as `road`.
   `do_reduce_labels` is an annotation-label setting, not an output-class shift.
4. Require road argmax, softmax score >= 0.70 and margin >= 0.20 over every
   other class. Erode one native cell; retain four-connected components of at
   least 0.005 native-frame area. Require retained area >= 0.02 of the frame.
5. Below that area, return an empty mask and `UNCONFIRMED`. This means road is
   not confirmed, NOT that road is definitely absent. Scores are not calibrated
   probabilities of correctness. No hole filling or lane-pair requirement.
6. Nearest-neighbor resize the binary mask to 1280 x 720 and intersect with the
   unchanged v4 white/yellow candidates. That detector quantizes to RGB565 and
   retains its original lower-frame ROI, starting at row 405 (zero-based).
7. Only accepted white/yellow candidates become green/cyan. All other displayed
   pixels equal the RGB565 reference, without smoothing or background repaint.

The semantic mask uses the entire image, not a fixed bottom-two-thirds ROI.
The inherited marking ROI is deliberately unchanged for this comparison.
Semantic road can include opposing lanes and restricted road surfaces; it is
not a free-space mask, ego lane, obstacle detector or safe steering command.
Native mask resolution and erosion can lose narrow or distant road features.

## Model Provenance

Pinned ONNX export: `Xenova/segformer-b0-finetuned-ade-512-512`, revision
`d3e5499fa8701ff0453ca940a8dfeae39b2f1504`.
Pinned upstream model: `nvidia/segformer-b0-finetuned-ade-512-512`, revision
`489d5cd81a0b59fab9b7ea758d3548ebe99677da`.
The original author cards, configuration files and license are retained in the
model directory. This project did not train or fine-tune those weights.

Fixed download locations, for reconstruction only:

```text
https://huggingface.co/Xenova/segformer-b0-finetuned-ade-512-512/resolve/d3e5499fa8701ff0453ca940a8dfeae39b2f1504/onnx/model.onnx
https://huggingface.co/Xenova/segformer-b0-finetuned-ade-512-512/resolve/d3e5499fa8701ff0453ca940a8dfeae39b2f1504/config.json
https://huggingface.co/Xenova/segformer-b0-finetuned-ade-512-512/resolve/d3e5499fa8701ff0453ca940a8dfeae39b2f1504/preprocessor_config.json
https://huggingface.co/nvidia/segformer-b0-finetuned-ade-512-512/resolve/489d5cd81a0b59fab9b7ea758d3548ebe99677da/README.md
```

`model.onnx`: 15,335,446 bytes; SHA256:

```text
3e5c18a4be395f16646438d54c42377ddc202edfa33d5eced0c9506de75c44c2
```

`settings.json` pins this hash and inference refuses a mismatched model.
Configuration and source-image hashes are recorded in each `results.json`;
the verification manifest also hashes model cards and the saved license.
The saved `LICENSE.txt`, section 3.3, limits use to non-commercial research or
evaluation. Retain notices and review model/input permissions before submission
or redistribution. This experiment does not establish competition eligibility.

## Deployment Is Separate

Current deliverables run on this PC. No ONNX-to-PGL50 implementation, resource
estimate, quantization validation, frame transport or on-board timing evidence
exists for this model. A semantic-mask prototype cannot simply be compiled by
the current Verilog build. The user currently has no external ARM/MCU board.

Next engineering work is to test unpainted captures from the actual camera,
label road/non-road boundaries and marking failures, and determine a deployable
compute/interface architecture. Keep failures as regression inputs. Only then
select and validate hardware changes; do not present PC images as FPGA output.
