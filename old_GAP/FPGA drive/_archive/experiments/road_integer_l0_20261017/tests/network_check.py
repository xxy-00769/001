"""Replace only the first layer with its fixed-point reference; the rest is CPU-only."""
import json
from pathlib import Path
import sys

import numpy as np
import openvino as ov
from PIL import Image

HERE = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(HERE))
import reference as ref
from evaluate import gate


def main():
    ref.verify_models()
    output = HERE / "tests/output"
    metadata = json.loads((output / "reference.json").read_text(encoding="utf-8"))
    params, _ = ref.extract()
    path = ref.MODEL_DIR / "models" / ref.MODEL_NAME / "FP16-INT8" / f"{ref.MODEL_NAME}.xml"
    core = ov.Core()
    model = core.read_model(path)
    model.reshape([1, 3, ref.H, ref.W])
    options = {"INFERENCE_PRECISION_HINT": "f32", "INFERENCE_NUM_THREADS": 2, "NUM_STREAMS": 1}
    full = core.compile_model(model, "CPU", options)
    node = next(n for n in model.get_ops() if n.get_friendly_name() == "L0002_Conv2d_BN/WithoutBiases/fq_input_0")
    consumers = [p.get_node().get_friendly_name() for p in node.output(0).get_target_inputs()]
    feature = ov.opset13.parameter([1, 16, 96, 160], np.float32, name="integer_first_layer_features")
    for port in list(node.output(0).get_target_inputs()):
        port.replace_source_output(feature.output(0))
    tail_model = ov.Model([model.output(0)], [feature])
    tail = core.compile_model(tail_model, "CPU", options)
    records = []
    for source in metadata["records"]:
        if source["source_sha256"] is None:
            continue
        with np.load(output / f"{source['id']}_reference.npz") as saved:
            raw = np.ascontiguousarray(saved["bgr"].transpose(2, 0, 1)[None], dtype=np.float32)
            original_codes = saved["model_codes"].copy()
            fixed_codes = saved["quantized"].copy()
        baseline = full([raw])[full.output(0)][0, :, :180].copy()
        original_features = (original_codes.astype(np.float64) * params["output_step"]).astype(np.float32)[None]
        integer_features = (fixed_codes.astype(np.float64) * params["output_step"]).astype(np.float32)[None]
        control = tail([original_features])[tail.output(0)][0, :, :180].copy()
        actual = tail([integer_features])[tail.output(0)][0, :, :180].copy()
        baseline_mask, _, baseline_candidate = gate(baseline, [1, 3])
        control_mask, _, control_candidate = gate(control, [1, 3])
        actual_mask, _, actual_candidate = gate(actual, [1, 3])
        previous_path = ref.MODEL_DIR / "output_lowmem/omz_int8_320x192" / source["id"] / "mask.png"
        if previous_path.exists():
            np.testing.assert_array_equal(baseline_mask, np.asarray(Image.open(previous_path)))
        record = {"id": source["id"], "baseline_candidate": baseline_candidate,
                  "cut_control_candidate": control_candidate, "integer_first_layer_candidate": actual_candidate,
                  "cut_control_changed_mask_cells": int(np.count_nonzero(control_mask != baseline_mask)),
                  "integer_vs_control_changed_mask_cells": int(np.count_nonzero(actual_mask != control_mask)),
                  "integer_vs_baseline_changed_mask_cells": int(np.count_nonzero(actual_mask != baseline_mask)),
                  "cut_control_max_probability_error": float(np.max(np.abs(control-baseline))),
                  "integer_vs_control_max_probability_error": float(np.max(np.abs(actual-control))),
                  "first_layer_differing_codes": int(np.count_nonzero(fixed_codes != original_codes))}
        records.append(record)
        np.savez_compressed(output / f"{source['id']}_network_check.npz", baseline=baseline, cut_control=control,
                            integer_first_layer=actual, baseline_mask=baseline_mask, integer_mask=actual_mask)
        print(json.dumps(record), flush=True)
    summary = {"scope": "Only first layer substituted with fixed-point software reference; remaining network runs on CPU, not FPGA.",
               "records": records, "cut_consumers": sorted(consumers), "openvino": ov.__version__,
               "same_candidate_decisions": all(r["baseline_candidate"] == r["cut_control_candidate"] == r["integer_first_layer_candidate"] for r in records),
               "same_accepted_masks": all(r["integer_vs_baseline_changed_mask_cells"] == 0 for r in records),
               "same_cut_control_masks": all(r["cut_control_changed_mask_cells"] == 0 for r in records),
               "no_claim_of_full_integer_network": True}
    ref.write_json(output / "network_check.json", summary)
    assert len(records) == 14 and summary["same_candidate_decisions"], "First-layer substitution changed image decisions"
    print("PASS: 14 first-layer substitution regressions; inspect mask/probability deltas separately")


if __name__ == "__main__":
    main()
