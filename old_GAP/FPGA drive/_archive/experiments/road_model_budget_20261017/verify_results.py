"""Recompute output consistency, summarize budgets, and render a regression contact sheet."""
import argparse
import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont, ImageOps

from evaluate import (HERE, ROOT, SETTINGS, VARIANTS, detect, digest, gate,
                      protected_hashes, thumbnail, verify_models)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=HERE / "output_lowmem")
    args = parser.parse_args()
    data = json.loads((args.output / "results.json").read_text(encoding="utf-8"))
    verify_models()
    assert data["settings"] == SETTINGS
    assert data["variants"] == VARIANTS
    assert data["protected_files_unchanged"]
    assert data["protected_files_before"] == data["protected_files_after"] == protected_hashes()
    dataset_path = ROOT / "tests/fixtures/road_first/dataset.json"
    assert digest(dataset_path) == data["dataset_sha256"]
    assert digest(HERE / "model_provenance.json") == data["provenance_sha256"]
    dataset = json.loads(dataset_path.read_text(encoding="utf-8"))
    assert len(data["results"]) == len(VARIANTS)
    references = {}
    for entry in dataset["images"]:
        path = (dataset_path.parent / entry["file"]).resolve()
        with Image.open(path) as image:
            image = ImageOps.exif_transpose(image).convert("RGB").resize((1280, 720), Image.Resampling.BILINEAR)
        pixels, white, yellow, _ = detect(image)
        references[entry["id"]] = (pixels.astype(np.uint8), white, yellow, digest(path), entry["road_present"])
    cases = 0
    summary = []
    for result in data["results"]:
        variant = result["variant"]
        assert result["status"] == "OK", result
        assert len(result["records"]) == len(dataset["images"])
        assert {r["id"] for r in result["records"]} == set(references)
        for record in result["records"]:
            pixels, white, yellow, source_sha, road_present = references[record["id"]]
            assert source_sha == record["source_sha256"]
            assert road_present == record["road_present"]
            idir = args.output / variant["id"] / record["id"]
            with np.load(idir / "prediction.npz") as prediction:
                low, score, candidate = gate(prediction["probabilities"], [6] if variant["model"] == "segformer" else [1, 3])
                np.testing.assert_array_equal(low, prediction["mask"])
                np.testing.assert_allclose(score, prediction["score"])
            np.testing.assert_array_equal(low, np.asarray(Image.open(idir / "mask.png")))
            prepared = pixels if variant["scale"] == 1 else thumbnail(pixels, variant["scale"])
            np.testing.assert_array_equal(prepared, np.asarray(Image.open(idir / "input.png")))
            mask = np.asarray(Image.fromarray(low).resize((1280, 720), Image.Resampling.NEAREST))
            filtered = pixels.copy()
            filtered[white & mask] = (0, 255, 0)
            filtered[yellow & mask] = (0, 255, 255)
            np.testing.assert_array_equal(filtered, np.asarray(Image.open(idir / "gated_markings.png")))
            assert candidate == record["road_candidate"]
            assert record["road_fraction"] == float(mask.mean())
            assert record["baseline_paint_pixels"] == int((white | yellow).sum())
            assert record["gated_paint_pixels"] == int(((white | yellow) & mask).sum())
            assert 0 < record["inference_ms"] < 60000
            cases += 1
        negatives = [r for r in result["records"] if not r["road_present"]]
        positives = [r for r in result["records"] if r["road_present"]]
        expected = {"road_candidate_images": sum(r["road_candidate"] for r in positives),
                    "road_images": len(positives), "false_road_candidate_images": sum(r["road_candidate"] for r in negatives),
                    "nonroad_images": len(negatives), "nonroad_false_paint_pixels": sum(r["gated_paint_pixels"] for r in negatives),
                    "median_cpu_inference_ms": float(np.median([r["inference_ms"] for r in result["records"]]))}
        assert result["summary"] == expected
        summary.append({"variant": variant["id"], **expected,
                        "false_road_images": [r["id"] for r in negatives if r["road_candidate"]],
                        "missed_road_images": [r["id"] for r in positives if not r["road_candidate"]],
                        "positive_mask_agreement_with_segformer_not_accuracy": float(np.mean([
                            r["mask_iou_against_segformer_not_accuracy"] for r in positives]))})
    verification = {"verified_cases": cases, "model_files_verified": True,
                    "protected_file_count": len(data["protected_files_before"]), "protected_files_unchanged": True,
                    "results_sha256": digest(args.output / "results.json"), "settings": SETTINGS,
                    "scripts_sha256": {name: digest(HERE / name) for name in ("evaluate.py", "fetch_model.py", "test_evaluate.py", "verify_results.py")},
                    "summary": summary, "not_pixel_ground_truth": True, "not_hardware_inference": True}
    (HERE / "verification.json").write_text(json.dumps(verification, indent=2) + "\n", encoding="utf-8")
    lines = ["# Model Regression and Budget", "", "Offline CPU only. All 14 images are reused regression inputs, not untouched holdout.",
             "No pixel labels exist. A positive image retaining any road is not segmentation accuracy.", "",
             "| Variant | Road images with candidates / 6 | Nonroad images falsely accepted / 8 | Nonroad paint pixels | CPU inference median ms |",
             "| --- | --- | --- | --- | --- |"]
    for row in summary:
        lines.append(f"| {row['variant']} | {row['road_candidate_images']} | {row['false_road_candidate_images']} | {row['nonroad_false_paint_pixels']} | {row['median_cpu_inference_ms']:.1f} |")
    lines += ["", "Timing excludes all pre/postprocessing, I/O and display. It does not predict FPGA throughput.",
              "", "## Graph Budget", "", "| Variant | Convolution MACs/frame | Largest activation elements | Convolution weight elements |", "| --- | --- | --- | --- |"]
    for result in data["results"]:
        inventory = result["inventory"]
        if "convolution_macs_per_frame" in inventory:
            lines.append(f"| {result['variant']['id']} | {inventory['convolution_macs_per_frame']:,} | {inventory['largest_activation_tensors'][0]['elements']:,} | {inventory['convolution_weight_elements']:,} |")
    lines += ["", "MAC counts exclude interpolation, pooling, residual addition, quantization, Softmax and postprocessing. Activation count is not peak liveness.",
              "At hypothetical INT8 storage, element counts equal bytes; actual graph tensors are mixed precision. Accumulators, scales and live residuals cost extra.",
              "", "## Per-Image Failures", ""]
    for row in summary:
        lines += [f"### {row['variant']}", "", f"False road candidates: {', '.join(row['false_road_images']) or 'none in this sample'}.",
                  f"Road images with no candidates: {', '.join(row['missed_road_images']) or 'none in this sample'}.", ""]
    (args.output / "REPORT.md").write_text("\n".join(lines) + "\n", encoding="utf-8")
    columns = [("segformer_full", "SegFormer full"), ("segformer_thumb8_fullcompute", "SegFormer 160x90 -> 512"),
               ("omz_fp32_full", "OMZ FP32 896x512"), ("omz_fp32_160x96", "OMZ FP32 160x96"),
               ("omz_fp32_320x192", "OMZ FP32 320x192"), ("omz_int8_320x192", "OMZ INT8 320x192")]
    selected = ["legacy_road_3", "road_ai_junction_overhead", "negative_shelf_dark", "negative_boxes", "negative_table_window", "negative_desk_window"]
    sheet = Image.new("RGB", (240 * len(columns), 190 * len(selected) + 50), "#151719")
    draw = ImageDraw.Draw(sheet)
    font = ImageFont.truetype("C:/Windows/Fonts/arial.ttf", 14)
    draw.text((8, 5), "OFFLINE CPU / retained road regions remain bright / NOT BOARD OUTPUT / no pixel ground truth", font=font, fill="white")
    for x, (variant, label) in enumerate(columns):
        draw.text((x * 240 + 8, 27), label, font=font, fill="#e6ca8a")
        for y, identifier in enumerate(selected):
            pixels = references[identifier][0].copy()
            low = np.asarray(Image.open(args.output / variant / identifier / "mask.png"))
            mask = np.asarray(Image.fromarray(low).resize((1280, 720), Image.Resampling.NEAREST))
            pixels[~mask] //= 5
            record = next(r for result in data["results"] if result["variant"]["id"] == variant for r in result["records"] if r["id"] == identifier)
            top = 50 + y * 190
            draw.text((x * 240 + 5, top), identifier, font=font, fill="white")
            draw.text((x * 240 + 5, top + 18), f"accepted area {record['road_fraction']:.1%}", font=font, fill="white")
            sheet.paste(Image.fromarray(pixels).resize((240, 135)), (x * 240, top + 37))
    sheet.save(args.output / "contact_sheet.png")
    print(json.dumps(verification, indent=2))


if __name__ == "__main__":
    main()
