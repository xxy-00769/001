"""Audit saved offline results against inputs, fixed settings and fresh CPU inference."""
from __future__ import annotations

import argparse
import importlib.metadata
import json
from pathlib import Path
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont, ImageOps

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "host/road_first"))
from evaluate import detect, prepare, road_mask, sha256, summarize, validate_settings


PROTECTED = {
    "tests/road_marking_model.py": "0412e0b0d9b2ff48eb83935351e4bf21f6f3f6b787271ddd3d29451c6c0b0731",
    "source/rtl/lane_detect.v": "6e0df02de7b5ca383bc7293f2141c28a9ab3b506cc908a907b2ed9509e5ca110",
    "bitstreams/4_road_markings_filtered_cmos1.sbit": "ed53c960f810528bec0a641565a00b1a6fed9c2e6fcfaedac1af64f32d613467",
    "bitstreams/6_road_framefix_v4_cmos1.sbit": "599c5a26752885da38a8a8ecca0d3fb53f3ca30854753df0f0e20d4c83b942b9",
    "bitstreams/7_zebra_candidate_v4_cmos1.sbit": "808a9c281b11658d3326008db745d135aaeded0fd26bbf0e17d49e955770cd1a",
    "bitstreams/8_adas_lane_status_cmos1.sbit": "4714b2f26e2e71de27627a709c23daf98818421613f850f97bbe73c8a8772573",
    "bitstreams/9_adas_selftest_no_camera.sbit": "912bfb169f0a6205c5c79f494bd04a4b67e110567f2b762b61998d48e7d30843",
}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def read_json(path):
    return json.loads(path.read_text(encoding="utf-8"))


def read_image(path):
    with Image.open(path) as image:
        return np.asarray(image).copy()


def overview(output, rows):
    canvas = Image.new("RGB", (960, 80 + 300 * len(rows)), "#17191c")
    draw = ImageDraw.Draw(canvas)
    font = ImageFont.truetype("C:/Windows/Fonts/arial.ttf", 18)
    draw.text((12, 8), "NON-ROAD HOLDOUT / OFFLINE CPU ONLY / NOT FPGA OUTPUT", fill="white", font=font)
    draw.text((12, 38), "Before: v4 marking candidates", fill="white", font=font)
    draw.text((492, 38), "After: road-mask gate (empty on these inputs)", fill="white", font=font)
    for index, (record, directory) in enumerate(rows):
        y = 80 + index * 300
        draw.text((12, y), record["id"], fill="white", font=font)
        for x, name in ((0, "baseline.png"), (480, "gated_markings.png")):
            with Image.open(directory / name) as image:
                canvas.paste(image.resize((480, 270), Image.Resampling.BILINEAR), (x, y + 24))
    canvas.save(output / "nonroad_holdout.png")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--development", type=Path, default=ROOT / "tests/output/road_first_20261017_development")
    parser.add_argument("--holdout", type=Path, default=ROOT / "tests/output/road_first_20261017_holdout")
    parser.add_argument("--output", type=Path, default=ROOT / "tests/output/road_first_20261017_verification")
    parser.add_argument("--rerun-inference", action="store_true")
    args = parser.parse_args()
    require(not args.output.exists(), "Refusing to replace an existing audit directory")
    settings_path = ROOT / "host/road_first/settings.json"
    dataset_path = ROOT / "tests/fixtures/road_first/dataset.json"
    model_dir = ROOT / "models/road_first/segformer_b0_ade"
    settings = read_json(settings_path)
    validate_settings(settings)
    dataset = read_json(dataset_path)
    config = read_json(model_dir / "config.json")
    processor = read_json(model_dir / "preprocessor_config.json")
    road_ids = [int(key) for key, value in config["id2label"].items() if value == settings["road_class_name"]]
    require(len(road_ids) == 1, "Ambiguous road class")
    require(sha256(model_dir / "model.onnx") == settings["model_sha256"], "Model hash mismatch")
    inventory = {row["id"]: row for row in dataset["images"]}
    require(len(inventory) == len(dataset["images"]) == 14, "Unexpected or duplicate dataset IDs")
    expected_hashes = {
        "settings_sha256": sha256(settings_path), "dataset_sha256": sha256(dataset_path),
        "model_config_sha256": sha256(model_dir / "config.json"),
        "processor_config_sha256": sha256(model_dir / "preprocessor_config.json"),
    }
    for relative, expected in PROTECTED.items():
        require(sha256(ROOT / relative) == expected, f"Protected baseline changed: {relative}")

    session = None
    if args.rerun_inference:
        import onnxruntime as ort
        options = ort.SessionOptions()
        options.intra_op_num_threads = settings["intra_op_threads"]
        options.inter_op_num_threads = 1
        session = ort.InferenceSession(str(model_dir / "model.onnx"), sess_options=options,
                                       providers=["CPUExecutionProvider"])

    rows, negative_panels, file_hashes = [], [], {}
    seen = set()
    for split, directory in (("development", args.development), ("holdout", args.holdout)):
        results = read_json(directory / "results.json")
        require(results["settings"] == settings, f"Settings changed: {split}")
        for key, expected in expected_hashes.items():
            require(results[key] == expected, f"Metadata hash mismatch: {key}")
        require(results["provider"] == ["CPUExecutionProvider"], "Unexpected inference provider")
        require(results["training_performed"] is False and results["fpga_deployed"] is False,
                "Incorrect implementation claim")
        require(results["summary"] == summarize(results["records"]), f"Summary mismatch: {split}")
        expected_ids = {key for key, value in inventory.items() if value["split"] == split}
        require({row["id"] for row in results["records"]} == expected_ids, f"Split changed: {split}")
        for row in results["records"]:
            item_id = row["id"]
            require(item_id not in seen, f"Duplicate result: {item_id}")
            seen.add(item_id)
            require(all(row[key] == value for key, value in inventory[item_id].items()),
                    f"Input metadata changed: {item_id}")
            source = (dataset_path.parent / row["file"]).resolve()
            require(sha256(source) == row["source_sha256"], f"Input hash mismatch: {item_id}")
            with Image.open(source) as loaded:
                original = ImageOps.exif_transpose(loaded).convert("RGB")
            require(list(original.size) == row["original_size"], f"Input size mismatch: {item_id}")
            reference = original.resize((1280, 720), Image.Resampling.BILINEAR)
            item_dir = directory / item_id
            with np.load(item_dir / "prediction.npz", allow_pickle=False) as saved:
                logits = saved["logits"]
                require(logits.shape == (len(config["id2label"]), 128, 128), "Logit shape mismatch")
                mask, labels, score, candidate = road_mask(logits, road_ids[0], settings)
                np.testing.assert_array_equal(saved["road_mask"], mask)
                np.testing.assert_array_equal(saved["labels"], labels)
                np.testing.assert_array_equal(saved["road_score"], score)
                if session is not None:
                    fresh = session.run(None, {session.get_inputs()[0].name: prepare(reference, processor)})[0][0]
                    np.testing.assert_allclose(fresh, logits, rtol=1e-5, atol=1e-5)
                    np.testing.assert_array_equal(road_mask(fresh, road_ids[0], settings)[0], mask)
            full_mask = np.asarray(Image.fromarray(mask.astype(np.uint8) * 255).resize(
                reference.size, Image.Resampling.NEAREST))
            np.testing.assert_array_equal(read_image(item_dir / "road_mask.png"), full_mask)
            mask = full_mask != 0
            pixels, white, yellow, _ = detect(reference)
            baseline, gated = pixels.copy(), pixels.copy()
            baseline[white], baseline[yellow] = (0, 255, 0), (0, 255, 255)
            gated[white & mask], gated[yellow & mask] = (0, 255, 0), (0, 255, 255)
            np.testing.assert_array_equal(read_image(item_dir / "reference.png"), pixels)
            np.testing.assert_array_equal(read_image(item_dir / "baseline.png"), baseline)
            actual = read_image(item_dir / "gated_markings.png")
            np.testing.assert_array_equal(actual, gated)
            np.testing.assert_array_equal(actual[~mask], pixels[~mask])
            expected_metrics = {
                "reference_size": [1280, 720], "road_candidate": candidate,
                "state": "ROAD_CANDIDATE" if candidate else "UNCONFIRMED",
                "road_pixels": int(mask.sum()), "road_fraction": float(mask.mean()),
                "baseline_candidate_pixels": int((white | yellow).sum()),
                "gated_candidate_pixels": int(((white | yellow) & mask).sum()),
                "actuator_output": False, "implementation": "OFFLINE_CPU_ONLY",
            }
            require(all(row[key] == value for key, value in expected_metrics.items()),
                    f"Pixel metrics mismatch: {item_id}")
            require(np.isfinite(row["inference_ms"]) and row["inference_ms"] > 0, "Invalid timing")
            for path in sorted(item_dir.iterdir()):
                if path.is_file():
                    file_hashes[str(path.relative_to(ROOT))] = sha256(path)
            rows.append(row)
            if split == "holdout" and not row["road_present"]:
                negative_panels.append((row, item_dir))
            print(f"PASS {split}: {item_id}; exact mask/RGB/counts" +
                  ("; fresh CPU inference matched" if session is not None else ""), flush=True)
        file_hashes[str((directory / "results.json").relative_to(ROOT))] = sha256(directory / "results.json")
    require(seen == set(inventory), "Missing result")
    for path in (settings_path, dataset_path, ROOT / "host/road_first/evaluate.py",
                 ROOT / "tests/test_road_first.py", Path(__file__), *model_dir.iterdir()):
        if path.is_file():
            file_hashes[str(path.relative_to(ROOT))] = sha256(path)
    versions = {name: importlib.metadata.version(name) for name in ("numpy", "Pillow", "onnxruntime")}
    report = {"status": "PASS", "images_verified": len(rows), "fresh_inference": session is not None,
              "verification_scope": "Artifact consistency, not an independent semantic accuracy assessment",
              "summary": summarize(rows), "packages": versions, "protected_hashes": PROTECTED,
              "artifact_hashes": file_hashes}
    args.output.mkdir(parents=True)
    overview(args.output, negative_panels)
    (args.output / "verification.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report["summary"], indent=2), flush=True)
    print(f"PASS: {len(rows)} inputs, original baseline hashes, artifact integrity. No FPGA deployment.")


if __name__ == "__main__":
    main()
