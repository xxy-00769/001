"""Substitute a complete first residual block; the remaining network runs on CPU."""
import json
from pathlib import Path
import sys

import numpy as np
import openvino as ov

HERE = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(HERE))
import reference as ref
from evaluate import gate


def cut_tail(core, name):
    model = ref.load_model()
    node = next(n for n in model.get_ops() if n.get_friendly_name() == name)
    param = ov.opset13.parameter(list(node.get_output_shape(0)), np.float32)
    for port in list(node.output(0).get_target_inputs()):
        port.replace_source_output(param.output(0))
    return core.compile_model(ov.Model([model.output(0)], [param]), "CPU", ref.OPTIONS)


def infer(compiled, value):
    return compiled([np.ascontiguousarray(value, dtype=np.float32)])[compiled.output(0)][0, :, :180].copy()


def main():
    out = HERE / "tests/output"
    metadata = json.loads((out / "reference.json").read_text(encoding="utf-8"))
    model = ref.load_model()
    core = ov.Core()
    full = core.compile_model(model, "CPU", ref.OPTIONS)
    tail = cut_tail(core, "L0009_Conv2d_BN/WithoutBiases/fq_input_0")
    l0_tail = cut_tail(core, "L0002_Conv2d_BN/WithoutBiases/fq_input_0")
    rp = ref.residual_params(model)
    records = []
    for source in metadata["records"]:
        name = source["id"]
        with np.load(out / f"{name}_block.npz") as saved:
            baseline = infer(full, saved["raw_bgr"].transpose(2,0,1)[None])
            control = infer(tail, ref.decode(saved["native_block_codes"], rp["out"])[None])
            integer = infer(tail, ref.decode(saved["block_codes"], rp["out"])[None])
            first_only = infer(l0_tail, ref.decode(saved["input_codes"], rp["b"])[None])
        masks, decisions = {}, {}
        outputs = {"baseline": baseline, "cut_control": control, "first_layer_only": first_only, "integer_block": integer}
        for key, values in outputs.items():
            masks[key], _, decisions[key] = gate(values, [1,3])
        record = {"id": name, "nonroad_fixture": name.startswith("negative_"), "decisions": decisions,
                  "cut_control_changed_mask_cells": int(np.count_nonzero(masks["cut_control"] != masks["baseline"])),
                  "integer_vs_control_changed_mask_cells": int(np.count_nonzero(masks["integer_block"] != masks["cut_control"])),
                  "integer_vs_baseline_changed_mask_cells": int(np.count_nonzero(masks["integer_block"] != masks["baseline"])),
                  "integer_vs_first_only_changed_mask_cells": int(np.count_nonzero(masks["integer_block"] != masks["first_layer_only"])),
                  "integer_vs_control_max_probability_error": float(np.abs(integer-control).max()),
                  "integer_vs_first_only_max_probability_error": float(np.abs(integer-first_only).max())}
        records.append(record)
        np.savez_compressed(out / f"{name}_network.npz", **outputs, **{f"{k}_mask":v for k,v in masks.items()})
        print(json.dumps(record), flush=True)
    summary = {"scope": "Integer first layer plus first residual block substituted; CPU executes all later layers. Not board inference or full-model equivalence.",
               "records": records, "same_image_decisions": all(len(set(r["decisions"].values()))==1 for r in records),
               "same_accepted_masks": all(r["integer_vs_baseline_changed_mask_cells"]==0 for r in records),
               "baseline_nonroad_accepted": sum(r["nonroad_fixture"] and r["decisions"]["baseline"] for r in records),
               "integer_nonroad_accepted": sum(r["nonroad_fixture"] and r["decisions"]["integer_block"] for r in records),
               "baseline_road_accepted": sum(not r["nonroad_fixture"] and r["decisions"]["baseline"] for r in records),
               "integer_road_accepted": sum(not r["nonroad_fixture"] and r["decisions"]["integer_block"] for r in records),
               "openvino": ov.__version__, "deployment_approved": False}
    assert len(records)==14
    ref.write_json(out / "network_check.json", summary)
    print("COMPLETE: 14 CPU-tail regressions; review decisions and boundary deltas, not an accuracy PASS")


if __name__ == "__main__":
    main()
