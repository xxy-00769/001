"""Offline semantic road-mask experiment. No FPGA/MCU link or vehicle control."""
from __future__ import annotations

import argparse
from collections import deque
import hashlib
import json
import math
from pathlib import Path
import sys
import time

import numpy as np
from PIL import Image, ImageDraw, ImageFont, ImageOps

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tests"))
from road_marking_model import detect


def sha256(path):
    digest = hashlib.sha256()
    with Path(path).open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def validate_settings(settings):
    for key in ("minimum_probability", "minimum_margin", "minimum_component_fraction",
                "minimum_frame_road_fraction"):
        value = settings[key]
        if not math.isfinite(value) or not 0 < value <= 1:
            raise ValueError(f"Invalid {key}")
    if not isinstance(settings["erode_cells"], int) or not 0 <= settings["erode_cells"] <= 4:
        raise ValueError("Invalid erosion radius")
    if not 1 <= settings["intra_op_threads"] <= 32:
        raise ValueError("Invalid CPU thread count")


def retain_components(mask, minimum_size):
    """Four-connected components; no fixed trapezoid or assumed road location."""
    height, width = mask.shape
    visited = np.zeros_like(mask, dtype=bool)
    output = np.zeros_like(mask, dtype=bool)
    for y, x in zip(*np.nonzero(mask)):
        if visited[y, x]:
            continue
        pending = deque([(y, x)])
        visited[y, x] = True
        component = []
        while pending:
            cy, cx = pending.popleft()
            component.append((cy, cx))
            for ny, nx in ((cy - 1, cx), (cy + 1, cx), (cy, cx - 1), (cy, cx + 1)):
                if 0 <= ny < height and 0 <= nx < width and mask[ny, nx] and not visited[ny, nx]:
                    visited[ny, nx] = True
                    pending.append((ny, nx))
        if len(component) >= minimum_size:
            yy, xx = zip(*component)
            output[yy, xx] = True
    return output


def erode(mask, radius):
    if not radius:
        return mask.copy()
    height, width = mask.shape
    padded = np.pad(mask, radius, constant_values=False)
    return np.logical_and.reduce([
        padded[y:y + height, x:x + width]
        for y in range(2 * radius + 1) for x in range(2 * radius + 1)
    ])


def road_mask(logits, road_id, settings):
    """Reject uncertain/border pixels; no hole filling through cars or people."""
    values = np.asarray(logits, dtype=np.float32)
    if values.ndim != 3 or not 0 <= road_id < values.shape[0] or values.shape[0] < 2:
        raise ValueError("Unexpected class-logit dimensions")
    if not np.isfinite(values).all():
        raise ValueError("Non-finite model output")
    exp = np.exp(values - values.max(axis=0, keepdims=True))
    probabilities = exp / exp.sum(axis=0, keepdims=True)
    labels = values.argmax(axis=0)
    score = probabilities[road_id]
    competitors = np.maximum(probabilities[:road_id].max(axis=0) if road_id else 0,
                             probabilities[road_id + 1:].max(axis=0) if road_id + 1 < len(values) else 0)
    accepted = ((labels == road_id) & (score >= settings["minimum_probability"])
                & (score - competitors >= settings["minimum_margin"]))
    accepted = erode(accepted, settings["erode_cells"])
    accepted = retain_components(accepted, math.ceil(accepted.size * settings["minimum_component_fraction"]))
    candidate = bool(accepted.mean() >= settings["minimum_frame_road_fraction"])
    if not candidate:
        accepted[:] = False
    return accepted, labels, score, candidate


def prepare(image, config):
    if config.get("resample") != 2 or not config.get("do_resize") or not config.get("do_normalize"):
        raise ValueError("Unsupported model preprocessing; refusing to guess")
    size = config["size"]
    resized = image.convert("RGB").resize((size["width"], size["height"]), Image.Resampling.BILINEAR)
    values = np.asarray(resized, dtype=np.float32)
    if config.get("do_rescale"):
        values *= np.float32(config["rescale_factor"])
    values = (values - np.asarray(config["image_mean"], dtype=np.float32)) / np.asarray(config["image_std"], dtype=np.float32)
    return np.ascontiguousarray(values.transpose(2, 0, 1)[None])


def make_panel(original, baseline, mask, filtered, title, path):
    tile_w, tile_h = 480, 270
    canvas = Image.new("RGB", (tile_w * 2, 660), "#17191c")
    draw = ImageDraw.Draw(canvas)
    font = ImageFont.truetype("C:/Windows/Fonts/arial.ttf", 18)
    small = ImageFont.truetype("C:/Windows/Fonts/arial.ttf", 15)
    draw.text((12, 8), title, fill="white", font=font)
    draw.text((12, 31), "OFFLINE CPU / PRETRAINED MODEL / NOT A BOARD CAPTURE", fill="#f1c75b", font=small)
    road_view = np.asarray(original).copy()
    road_view[~mask] = road_view[~mask] // 5
    for index, (array, caption) in enumerate(((original, "Input (1280 x 720 RGB565 reference)"),
                                            (baseline, "Before: all v4 paint candidates"),
                                            (road_view, "Retained road candidates; other pixels dimmed"),
                                            (filtered, "After: paint candidates only inside road mask"))):
        x, y = index % 2 * tile_w, 60 + index // 2 * (tile_h + 30)
        draw.text((x + 8, y), caption, fill="white", font=small)
        tile = Image.fromarray(array).resize((tile_w, tile_h), Image.Resampling.BILINEAR)
        canvas.paste(tile, (x, y + 20))
    canvas.save(path)


def summarize(records):
    groups = {}
    for split in ("development", "holdout", "all"):
        selected = [r for r in records if split == "all" or r["split"] == split]
        negatives = [r for r in selected if not r["road_present"]]
        positives = [r for r in selected if r["road_present"]]
        groups[split] = {
            "images": len(selected), "road_images": len(positives), "nonroad_images": len(negatives),
            "road_images_with_candidate": sum(r["road_candidate"] for r in positives),
            "nonroad_images_with_candidate": sum(r["road_candidate"] for r in negatives),
            "nonroad_images_with_baseline_paint": sum(r["baseline_candidate_pixels"] > 0 for r in negatives),
            "nonroad_images_with_gated_paint": sum(r["gated_candidate_pixels"] > 0 for r in negatives),
            "nonroad_baseline_paint_pixels": sum(r["baseline_candidate_pixels"] for r in negatives),
            "nonroad_gated_paint_pixels": sum(r["gated_candidate_pixels"] for r in negatives),
        }
    return groups


def write_report(output, records, metadata):
    lines = ["# Offline Road-First Evaluation", "", "CPU experiment only. No training, FPGA deployment, live camera link or actuator output.",
             "The original bitstreams and RTL have not been changed.", "",
             "Image-level presence labels are provisional visual labels. No pixel ground truth exists for road-positive images.",
             "Do not interpret these counts as segmentation IoU, real-world accuracy or driving safety.", "",
             "## Fixed Settings", "", "```json", json.dumps(metadata["settings"], indent=2), "```", "",
             "## Image-Level Results", "", "| Split | Road candidate / road images | False road candidate / nonroad images | Baseline nonroad paint pixels | Gated nonroad paint pixels |",
             "| --- | --- | --- | --- | --- |"]
    for split, result in metadata["summary"].items():
        lines.append(f"| {split} | {result['road_images_with_candidate']}/{result['road_images']} | {result['nonroad_images_with_candidate']}/{result['nonroad_images']} | {result['nonroad_baseline_paint_pixels']} | {result['nonroad_gated_paint_pixels']} |")
    lines += ["", "## Per Image", "", "| Image | Split | Source | Expected road | Road fraction | State | Paint before -> after | CPU inference ms |",
              "| --- | --- | --- | --- | --- | --- | --- | --- |"]
    for record in records:
        lines.append(f"| {record['id']} | {record['split']} | {record['source_kind']} | {record['road_present']} | {record['road_fraction']:.4f} | {record['state']} | {record['baseline_candidate_pixels']} -> {record['gated_candidate_pixels']} | {record['inference_ms']:.1f} |")
    lines += ["", "## Limits", "",
              "- Three new road images explicitly carry an AI-generated watermark; one is an overhead intersection, not an ego-camera view.",
              "- Stock/web images, watermarks and an illustration are retained, not silently removed. Their redistribution rights are not established.",
              "- The 1280x720 reference resize matches the existing detector, including aspect-ratio distortion of portrait inputs. This is not camera calibration.",
              "- Model preprocessing follows the pinned export configuration; logits are thresholded at native resolution, then the binary mask is nearest-neighbor resized.",
              "- Softmax scores are not calibrated probability of correctness. UNCONFIRMED does not mean there is definitely no road.",
              "- No minimum lane-pair requirement or fixed lower-image trapezoid is used to create the semantic mask.",
              "- Road surface is not a safe/free path, own lane, legal driving area or permission to move; pedestrians and vehicles require separate validation.",
              "- Gated paint still inherits v4 marking errors inside the road. Yellow hatching is not automatically an ego-lane boundary.",
              "- Holdout was fixed before inference and not used for threshold tuning. Seven examples are too few for a meaningful generalization guarantee.",
              "- Per-image inference timing excludes model loading, pre/postprocessing, transfers and display; it is not an end-to-end FPS measurement.",
              "- NVIDIA's SegFormer license limits use to non-commercial research/evaluation. Model and input licenses must be reviewed before redistribution.",
              "", "## Panels", ""]
    for record in records:
        lines += [f"### {record['id']}", "", f"![{record['id']}]({record['id']}/comparison.png)", ""]
    (output / "REPORT.md").write_text("\n".join(lines) + "\n", encoding="utf-8")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dataset", type=Path, default=ROOT / "tests/fixtures/road_first/dataset.json")
    parser.add_argument("--model-dir", type=Path, default=ROOT / "models/road_first/segformer_b0_ade")
    parser.add_argument("--settings", type=Path, default=Path(__file__).with_name("settings.json"))
    parser.add_argument("--output", type=Path, default=ROOT / "tests/output/road_first_20261017")
    parser.add_argument("--split", choices=("development", "holdout", "all"), default="all")
    args = parser.parse_args()
    settings = json.loads(args.settings.read_text(encoding="utf-8"))
    validate_settings(settings)
    model_path = args.model_dir / "model.onnx"
    if sha256(model_path) != settings["model_sha256"]:
        raise ValueError("Model SHA256 mismatch")
    if args.output.exists():
        raise FileExistsError(f"Refusing to replace an existing evaluation: {args.output}")
    dataset = json.loads(args.dataset.read_text(encoding="utf-8"))
    config = json.loads((args.model_dir / "config.json").read_text(encoding="utf-8"))
    processor = json.loads((args.model_dir / "preprocessor_config.json").read_text(encoding="utf-8"))
    road_ids = [int(key) for key, label in config["id2label"].items() if label == settings["road_class_name"]]
    if len(road_ids) != 1:
        raise ValueError("Missing or ambiguous road class")
    import onnxruntime as ort
    options = ort.SessionOptions()
    options.intra_op_num_threads = settings["intra_op_threads"]
    options.inter_op_num_threads = 1
    session = ort.InferenceSession(str(model_path), sess_options=options, providers=["CPUExecutionProvider"])
    input_name = session.get_inputs()[0].name
    args.output.mkdir(parents=True)
    records = []
    dataset_ids = [item["id"] for item in dataset["images"]]
    if len(set(dataset_ids)) != len(dataset_ids):
        raise ValueError("Duplicate dataset IDs")
    for entry in dataset["images"]:
        if args.split != "all" and entry["split"] != args.split:
            continue
        path = (args.dataset.parent / entry["file"]).resolve()
        with Image.open(path) as loaded:
            original = ImageOps.exif_transpose(loaded).convert("RGB")
        reference = original.resize((1280, 720), Image.Resampling.BILINEAR)
        tensor = prepare(reference, processor)
        start = time.perf_counter()
        logits = session.run(None, {input_name: tensor})[0]
        elapsed = (time.perf_counter() - start) * 1000
        lowmask, labels, score, candidate = road_mask(logits[0], road_ids[0], settings)
        mask_image = Image.fromarray(lowmask.astype(np.uint8) * 255).resize(reference.size, Image.Resampling.NEAREST)
        mask = np.asarray(mask_image) != 0
        pixels, white, yellow, _ = detect(reference)
        baseline = pixels.copy()
        baseline[white] = (0, 255, 0)
        baseline[yellow] = (0, 255, 255)
        filtered = pixels.copy()
        filtered[white & mask] = (0, 255, 0)
        filtered[yellow & mask] = (0, 255, 255)
        item_dir = args.output / entry["id"]
        item_dir.mkdir()
        Image.fromarray(pixels).save(item_dir / "reference.png")
        Image.fromarray(baseline).save(item_dir / "baseline.png")
        mask_image.save(item_dir / "road_mask.png")
        Image.fromarray(filtered).save(item_dir / "gated_markings.png")
        np.savez_compressed(item_dir / "prediction.npz", logits=logits[0], labels=labels.astype(np.uint8),
                            road_score=score, road_mask=lowmask)
        state = "ROAD_CANDIDATE" if candidate else "UNCONFIRMED"
        make_panel(pixels, baseline, mask, filtered, f"{entry['id']} | {entry['split']} | {state}", item_dir / "comparison.png")
        record = {**entry, "source_path": str(path), "source_sha256": sha256(path),
                  "original_size": original.size, "reference_size": reference.size,
                  "state": state, "road_candidate": candidate, "road_pixels": int(mask.sum()),
                  "road_fraction": float(mask.mean()), "baseline_candidate_pixels": int((white | yellow).sum()),
                  "gated_candidate_pixels": int(((white | yellow) & mask).sum()), "inference_ms": elapsed,
                  "actuator_output": False, "implementation": "OFFLINE_CPU_ONLY"}
        records.append(record)
        print(json.dumps({key: record[key] for key in ("id", "state", "road_fraction", "baseline_candidate_pixels", "gated_candidate_pixels", "inference_ms")}), flush=True)
    metadata = {"settings": settings, "settings_sha256": sha256(args.settings), "dataset_sha256": sha256(args.dataset),
                "model_config_sha256": sha256(args.model_dir / "config.json"),
                "processor_config_sha256": sha256(args.model_dir / "preprocessor_config.json"),
                "runtime": ort.__version__, "provider": session.get_providers(),
                "training_performed": False, "fpga_deployed": False,
                "summary": summarize(records), "records": records}
    (args.output / "results.json").write_text(json.dumps(metadata, indent=2) + "\n", encoding="utf-8")
    write_report(args.output, records, metadata)
    print(json.dumps(metadata["summary"], indent=2), flush=True)


if __name__ == "__main__":
    main()
