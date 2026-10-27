"""Export reconfigurable RTL vectors from real model weights and feature frames."""
import copy
import json
from pathlib import Path
import sys

import numpy as np
import openvino as ov

HERE = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(HERE))
import reference as ref


def main():
    out = HERE / "tests/output"
    out.mkdir(exist_ok=True)
    ref.write_json(out / "protected_before.json", ref.l0.protected_hashes())
    model = ref.load_model()
    inventory = ref.inventory(model)
    ref.write_json(HERE / "operator_inventory.json", inventory)
    cases, inputs, weights, coefficients, expected, native_records = [], [], [], [], [], []
    input_offset = weight_offset = coefficient_offset = output_offset = 0

    def add(p, pixels, desc, acc, codes, label):
        nonlocal input_offset, weight_offset, coefficient_offset, output_offset
        raw_coeff = ref.coefficient_bytes(p)
        record = {"id": len(cases), "label": label, "name": p["name"], "descriptor": desc,
                  "offsets": [input_offset, weight_offset, coefficient_offset, output_offset],
                  "lengths": [pixels.size, p["weights"].size, raw_coeff.size, codes.size]}
        inputs.append(pixels.reshape(-1))
        weights.append(p["weights"].reshape(-1).view(np.uint8))
        coefficients.append(raw_coeff)
        expected.append(((acc.reshape(-1).astype(np.uint64) & 0xffffffff) << 8) | codes.reshape(-1))
        cases.append(record)
        input_offset += pixels.size
        weight_offset += p["weights"].size
        coefficient_offset += raw_coeff.size
        output_offset += codes.size

    rng = np.random.default_rng(20261017)
    for row in inventory["supported"]:
        p = ref.extract_conv(model, row["name"])
        desc = row["descriptor"]
        pixels = rng.integers(0, 256, (p["ci"], desc[7], desc[6]), dtype=np.uint8)
        small = copy.deepcopy(p)
        small.update(input_shape=list(pixels.shape), output_shape=[p["co"], desc[9], desc[8]], pad=0)
        acc = ref.convolve(pixels, small)
        q = ref.requant(acc, p)
        oracle = ref.affine_oracle(acc, p)
        native = ref.native_tile(pixels, p)
        err = np.abs(q.astype(np.int16)-native.astype(np.int16))
        if err.max() > 1 or np.abs(q.astype(np.int16)-oracle.astype(np.int16)).max() > 1:
            raise ValueError(f"Unexpected isolated-op quantization difference: {p['name']}")
        native_records.append({"name": p["name"], "features": q.size, "max_native_error": int(err.max()),
                               "native_differing_codes": int(np.count_nonzero(err)),
                               "affine_differing_codes": int(np.count_nonzero(q != oracle))})
        add(p, pixels, desc, acc, q, "model_random_tile")
    print(f"Exported {len(native_records)} model convolution contracts", flush=True)

    # Non-square partial tiles, signed extremes, negative scale and saturation.
    for c, shape in enumerate(((1, 1), (2, 3), (4, 2))):
        p = copy.deepcopy(ref.extract_conv(model, "L0002_Conv2d_BN/WithoutBiases"))
        p["gain"][0] = -(1 << 36)
        p["offset"][0] = 127 << 36
        p["weights"][:] = -128 if c == 0 else 127
        ow, oh = shape
        p.update(input_shape=[p["ci"], oh, ow], output_shape=[p["co"], oh, ow], pad=0)
        pixels = np.full(p["input_shape"], 255 if c != 2 else 0, np.uint8)
        desc = [0, p["ci"], p["co"], 1, 1, 1, ow, oh, ow, oh]
        acc = ref.convolve(pixels, p)
        add(p, pixels, desc, acc, ref.requant(acc, p), f"partial_extreme_{c}")

    ps = [ref.extract_conv(model, f"L{i:04d}_Conv2d_BN/WithoutBiases") for i in (2, 4, 6)]
    residual = ref.residual_params(model)
    ref.write_json(out / "residual_params.json", {k: v.tolist() for k, v in residual.items() if isinstance(v, np.ndarray)})
    # These parameters are uniform across channels in this particular block.
    assert all(np.all(residual[k] == residual[k][0]) for k in ("gain_a", "gain_b", "offset"))
    a, b = np.indices((256, 256), dtype=np.uint16)
    qa, qb = a.astype(np.uint8)[None], b.astype(np.uint8)[None]
    rp = {k: v[:1] if isinstance(v, np.ndarray) else v for k, v in residual.items()}
    qr = ref.residual(qa, qb, rp).reshape(-1)
    np.savetxt(out / "residual_expected.hex", qr, fmt="%02x")
    (out / "residual_params.vh").write_text(
        f"localparam signed [47:0] GA = 48'h{int(residual['gain_a'][0]) & ((1<<48)-1):012x};\n"
        f"localparam signed [47:0] GB = 48'h{int(residual['gain_b'][0]) & ((1<<48)-1):012x};\n"
        f"localparam signed [63:0] OFFSET = 64'h{int(residual['offset'][0]) & ((1<<64)-1):016x};\n", encoding="ascii")

    old = ref.L0_DIR / "tests/output"
    metadata = json.loads((old / "reference.json").read_text(encoding="utf-8"))
    records = []
    nodes = {n.get_friendly_name(): n for n in model.get_ordered_ops()}
    output_names = [p["qout_name"] for p in ps] + ["L0009_Conv2d_BN/WithoutBiases/fq_input_0"]
    cut = ov.Core().compile_model(ov.Model([nodes[n].output(0) for n in output_names], model.get_parameters()), "CPU", ref.OPTIONS)
    for source in metadata["records"]:
        if source["source_sha256"] is None:
            continue
        name = source["id"]
        with np.load(old / f"{name}_reference.npz") as saved:
            initial = saved["quantized"].copy()
            raw = saved["bgr"].copy()
        native_outputs = cut([raw.transpose(2,0,1)[None].astype(np.float32)])
        values = initial
        stage_records = []
        for i, p in enumerate(ps):
            acc = ref.convolve(values, p)
            q = ref.requant(acc, p)
            native = ref.encode(native_outputs[cut.output(i)][0], p["limits_out"])
            oracle = ref.affine_oracle(acc, p)
            stage_records.append({"layer": p["name"], "features": q.size,
                                  "full_native_differing_codes": int(np.count_nonzero(q != native)),
                                  "affine_differing_codes": int(np.count_nonzero(q != oracle))})
            points = [(x,y) for y in range(0,96,4) for x in range(0,160,4)] if name == "legacy_road_3" else [(0,0),(156,0),(0,92),(156,92),(76,44)]
            for x,y in points:
                desc, pixels = ref.tile(values, p, x, y)
                add(p, pixels, desc, acc[:,y:y+4,x:x+4], q[:,y:y+4,x:x+4], f"{name}:{x}:{y}")
            values = q
        block = ref.residual(values, initial, residual)
        native_block = ref.encode(native_outputs[cut.output(3)][0], residual["out"])
        np.savez_compressed(out / f"{name}_block.npz", input_codes=initial, branch_codes=values,
                            block_codes=block, native_block_codes=native_block, raw_bgr=raw)
        records.append({"id": name, "source_sha256": source["source_sha256"], "stages": stage_records,
                        "block_features": block.size, "full_native_block_differing_codes": int(np.count_nonzero(block != native_block))})
        print(f"Block reference: {name}", flush=True)
    np.savetxt(out / "inputs.hex", np.concatenate(inputs), fmt="%02x")
    np.savetxt(out / "weights.hex", np.concatenate(weights), fmt="%02x")
    np.savetxt(out / "coefficients.hex", np.concatenate(coefficients), fmt="%02x")
    np.savetxt(out / "expected.hex", np.concatenate(expected), fmt="%010x")
    (out / "descriptors.txt").write_text("".join(" ".join(str(v) for v in c["descriptor"]+c["offsets"]+c["lengths"])+"\n" for c in cases), encoding="ascii")
    (out / "cases.vh").write_text(f"localparam CASES={len(cases)}, INPUT_BYTES={input_offset}, WEIGHT_BYTES={weight_offset}, COEFF_BYTES={coefficient_offset}, OUTPUT_VALUES={output_offset};\n", encoding="ascii")
    ref.write_json(out / "cases.json", cases)
    ref.write_json(out / "reference.json", {"cases": len(cases), "outputs": output_offset,
        "model_convolution_contracts": len(native_records), "isolated_native_checks": native_records,
        "records": records, "shift": ref.SHIFT, "full_tensor_rtl_cases": "legacy_road_3: L0002, L0004, L0006",
        "residual_exhaustive_pairs": 65536, "not_full_model": True})
    print(f"READY: {len(cases)} cases, {output_offset} expected convolution outputs", flush=True)


if __name__ == "__main__":
    main()
