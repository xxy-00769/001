"""Generate model-derived ROM, independent numeric references and tile test vectors."""
import json
from pathlib import Path
import sys

import numpy as np
from PIL import Image, ImageOps

HERE = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(HERE))
import reference as ref
from evaluate import thumbnail
from road_marking_model import rgb565


def main():
    output = HERE / "tests/output"
    output.mkdir(exist_ok=True)
    ref.write_json(output / "protected_before.json", ref.protected_hashes())
    params, cut = ref.extract()
    ref.export_rom(params)
    np.savez(output / "parameters.npz", **params)
    dataset_file = ref.ROOT / "tests/fixtures/road_first/dataset.json"
    dataset = json.loads(dataset_file.read_text(encoding="utf-8"))
    images = []
    for entry in dataset["images"]:
        path = dataset_file.parent / entry["file"]
        with Image.open(path) as image:
            pixels = rgb565(ImageOps.exif_transpose(image).convert("RGB").resize((1280, 720), Image.Resampling.BILINEAR)).astype(np.uint8)
        rgb = thumbnail(pixels, 4)
        bgr = np.pad(rgb[..., ::-1], ((0, 12), (0, 0), (0, 0)), mode="edge")
        images.append((entry["id"], bgr, ref.hash_file(path)))
    rng = np.random.default_rng(20261017)
    images.append(("random", rng.integers(0, 256, (ref.H, ref.W, 3), dtype=np.uint8), None))
    yy, xx = np.indices((ref.H, ref.W))
    images.append(("checker", np.repeat((((yy + xx) & 1) * 255).astype(np.uint8)[..., None], 3, axis=2), None))
    for name, color in (("black", (0, 0, 0)), ("white", (255, 255, 255)), ("blue", (255, 0, 0)),
                        ("green", (0, 255, 0)), ("red", (0, 0, 255))):
        images.append((name, np.broadcast_to(np.array(color, dtype=np.uint8), (ref.H, ref.W, 3)).copy(), None))
    records, cases, raw_tiles, expected = [], [], [], []
    full_frame_ids = {"legacy_road_3", "negative_shelf_dark"}
    full_transfer_bytes = 0
    for name, bgr, sha in images:
        acc = ref.conv_acc(bgr, params)
        fixed = ref.requant(acc, params)
        ideal = ref.float_reference_codes(acc, params)
        tensor = np.ascontiguousarray(bgr.transpose(2, 0, 1)[None], dtype=np.float32)
        actual = cut([tensor])[cut.output(0)][0].copy()
        model_codes = np.clip(np.rint(actual / params["output_step"]), 0, 255).astype(np.uint8)
        error = np.abs(fixed.astype(np.int16) - model_codes.astype(np.int16))
        ideal_error = np.abs(fixed.astype(np.int16) - ideal.astype(np.int16))
        if error.max() > 1 or ideal_error.max() > 1:
            raise ValueError(f"First-layer quantization error exceeds 1 code: {name}, {error.max()}")
        points = [(x, y) for y in range(12) for x in range(20)] if name in full_frame_ids else [(0, 0), (19, 0), (0, 11), (19, 11), (9, 5)]
        for tx, ty in points:
            plan = ref.transfer_plan(tx, ty, base=0x100000, frame_id=len(records))
            pixels = ref.tile(bgr, tx, ty)
            np.testing.assert_array_equal(ref.replay_plan(bgr, plan), pixels)
            tile_acc = acc[:, ty*8:ty*8+8, tx*8:tx*8+8].reshape(-1)
            tile_q = fixed[:, ty*8:ty*8+8, tx*8:tx*8+8].reshape(-1)
            raw_tiles.append(pixels.reshape(-1))
            expected.append(((tile_acc.astype(np.uint64) & 0xffffffff) << 8) | tile_q)
            cases.append({"case": len(cases), "image": name, "tile_x": tx, "tile_y": ty, "plan": plan,
                          "write_plan": ref.write_plan(tx, ty, frame_id=len(records))})
            if name == "legacy_road_3":
                full_transfer_bytes += plan["read_bytes"]
        records.append({"id": name, "source_sha256": sha, "first_layer_output_elements": int(fixed.size),
                        "model_code_max_abs_error": int(error.max()), "model_code_differences": int(np.count_nonzero(error)),
                        "ideal_code_max_abs_error": int(ideal_error.max()), "ideal_code_differences": int(np.count_nonzero(ideal_error)),
                        "acc_min": int(acc.min()), "acc_max": int(acc.max()),
                        "quant_zero_count": int((fixed == 0).sum()), "quant_255_count": int((fixed == 255).sum()),
                        "rtl_tiles": len(points)})
        np.savez_compressed(output / f"{name}_reference.npz", bgr=bgr, accumulator=acc.astype(np.int32),
                            quantized=fixed, model_codes=model_codes)
        print(json.dumps(records[-1]), flush=True)
    np.savetxt(output / "tiles.hex", np.concatenate(raw_tiles), fmt="%02x")
    np.savetxt(output / "expected.hex", np.concatenate(expected), fmt="%010x")
    ref.write_json(output / "cases.json", cases)
    metadata = {"model_provenance_sha256": ref.hash_file(ref.MODEL_DIR / "model_provenance.json"),
                "rom_sha256": ref.hash_file(HERE / "source/layer0_params.v"), "shift": ref.SHIFT,
                "input_high": params["input_high"], "output_high": params["output_high"],
                "input_lut_verified_codes": 256, "rounding": f"positive half-up, Q{ref.SHIFT} gain/bias, ReLU and uint8 saturation",
                "records": records, "rtl_cases": len(cases), "rtl_expected_elements": len(cases) * 1024,
                "raw_tile_bytes": len(cases)*867, "input_frame_bytes": ref.W*ref.H*3,
                "output_frame_bytes": 16*96*160, "single_tile_read_bytes_range": [min(c["plan"]["read_bytes"] for c in cases), max(c["plan"]["read_bytes"] for c in cases)],
                "full_frame_planned_read_bytes": full_transfer_bytes,
                "full_frame_planned_write_bus_bytes": 240 * 4096,
                "ddr_plan_only": True, "fpga_integrated": False}
    ref.write_json(output / "reference.json", metadata)
    print(f"READY: {len(cases)} tiles, {len(cases)*1024} expected first-layer outputs", flush=True)


if __name__ == "__main__":
    main()
