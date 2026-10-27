"""Reused-image regression and graph budget, not FPGA inference or accuracy certification."""
from __future__ import annotations

import argparse
from collections import Counter
import gc
import hashlib
import json
import math
from pathlib import Path
import sys
import time

import numpy as np
from PIL import Image, ImageDraw, ImageFont, ImageOps

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(ROOT))
sys.path.insert(0, str(ROOT / "tests"))
from host.road_first.evaluate import erode, prepare, retain_components
from road_marking_model import detect, rgb565

MODEL_NAME = "road-segmentation-adas-0001"
SEGFORMER = ROOT / "models/road_first/segformer_b0_ade"
SEG_SHA = "3e5c18a4be395f16646438d54c42377ddc202edfa33d5eced0c9506de75c44c2"
SETTINGS = {"probability": 0.70, "margin": 0.20, "component_fraction": 0.005,
            "frame_fraction": 0.02, "erosion": 1, "mask_size": [160, 90], "threads": 4}
VARIANTS = [
    {"id": "segformer_full", "model": "segformer", "scale": 1, "shape": [512, 512]},
    {"id": "segformer_thumb8_fullcompute", "model": "segformer", "scale": 8, "shape": [512, 512]},
    {"id": "omz_fp32_full", "model": "FP32", "scale": 1, "shape": [512, 896]},
    {"id": "omz_fp32_thumb8_fullcompute", "model": "FP32", "scale": 8, "shape": [512, 896]},
    {"id": "omz_fp32_160x96", "model": "FP32", "scale": 8, "shape": [96, 160], "pad": True},
    {"id": "omz_fp32_320x192", "model": "FP32", "scale": 4, "shape": [192, 320], "pad": True},
    {"id": "omz_int8_full", "model": "FP16-INT8", "scale": 1, "shape": [512, 896]},
    {"id": "omz_int8_160x96", "model": "FP16-INT8", "scale": 8, "shape": [96, 160], "pad": True},
    {"id": "omz_int8_320x192", "model": "FP16-INT8", "scale": 4, "shape": [192, 320], "pad": True},
]


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def protected_hashes():
    paths = list((ROOT / "source").rglob("*")) + list((ROOT / "bitstreams").glob("*.sbit"))
    paths += [ROOT / "hdmi_ddr_ov5640_top.fdc", ROOT / "flow.tcl"]
    return {str(p.relative_to(ROOT)): digest(p) for p in paths if p.is_file()}


def thumbnail(pixels, scale):
    h, w, c = pixels.shape
    if h % scale or w % scale or c != 3:
        raise ValueError("Integer box mean requires divisible RGB dimensions")
    mean = pixels.reshape(h // scale, scale, w // scale, scale, 3).sum(axis=(1, 3), dtype=np.uint32) // (scale * scale)
    return rgb565(Image.fromarray(mean.astype(np.uint8))).astype(np.uint8)


def softmax(values):
    exp = np.array(values, dtype=np.float32, copy=True)
    exp -= exp.max(axis=0, keepdims=True)
    np.exp(exp, out=exp)
    exp /= exp.sum(axis=0, keepdims=True)
    return exp


def gate(probabilities, road_ids):
    if probabilities.ndim != 3 or not np.isfinite(probabilities).all():
        raise ValueError("Invalid output tensor")
    if probabilities.min() < -1e-4 or probabilities.max() > 1.0001:
        raise ValueError("Output is not probabilities")
    if not np.allclose(probabilities.sum(axis=0), 1, atol=0.02):
        raise ValueError("Probabilities do not sum to one")
    others = [i for i in range(len(probabilities)) if i not in road_ids]
    score = probabilities[road_ids].sum(axis=0)
    competitor = probabilities[others].max(axis=0)
    # A common output grid makes morphology comparable across input dimensions.
    score = np.asarray(Image.fromarray(score).resize(tuple(SETTINGS["mask_size"]), Image.Resampling.BOX))
    competitor = np.asarray(Image.fromarray(competitor).resize(tuple(SETTINGS["mask_size"]), Image.Resampling.BOX))
    accepted = (score >= SETTINGS["probability"]) & (score - competitor >= SETTINGS["margin"])
    accepted = erode(accepted, SETTINGS["erosion"])
    accepted = retain_components(accepted, math.ceil(accepted.size * SETTINGS["component_fraction"]))
    candidate = bool(accepted.mean() >= SETTINGS["frame_fraction"])
    if not candidate:
        accepted[:] = False
    return accepted, score, candidate


def ov_inventory(model):
    ops = model.get_ordered_ops()
    histogram = Counter(n.get_type_name() for n in ops)
    constants = Counter()
    largest = []
    convs = []
    weights = 0
    for node in ops:
        kind = node.get_type_name()
        if kind == "Constant":
            constants[str(node.get_element_type())] += int(np.asarray(node.data).nbytes)
            continue
        for port in node.outputs():
            if port.get_partial_shape().is_static:
                shape = list(port.get_shape())
                largest.append({"node": node.get_friendly_name(), "op": kind,
                                "shape": shape, "elements": math.prod(shape)})
        if kind in ("Convolution", "GroupConvolution"):
            ws = list(node.input_value(1).get_shape())
            out = list(node.output(0).get_shape())
            elements = math.prod(ws)
            weights += elements
            convs.append({"node": node.get_friendly_name(), "op": kind,
                          "weights": ws, "output": out,
                          "macs": math.prod(out) * math.prod(ws[2:] if kind == "GroupConvolution" else ws[1:])})
    return {"input": list(model.input().get_shape()), "output": list(model.output().get_shape()),
            "operators": dict(histogram), "constant_bytes_by_type": dict(constants),
            "convolution_weight_elements": weights, "convolution_macs_per_frame": sum(n["macs"] for n in convs),
            "largest_activation_tensors": sorted(largest, key=lambda x: x["elements"], reverse=True)[:10],
            "convolutions": convs,
            "limits": "Logical tensors only. MACs exclude non-convolution operations. Maximum tensor is not peak live memory. No tiling, fusion, DDR schedule, synthesized accelerator, clock or throughput claim."}


def seg_inventory():
    import onnx
    model = onnx.load(str(SEGFORMER / "model.onnx"))
    arrays = [onnx.numpy_helper.to_array(t) for t in model.graph.initializer]
    return {"sha256": digest(SEGFORMER / "model.onnx"), "file_bytes": (SEGFORMER / "model.onnx").stat().st_size,
            "initializer_elements": sum(a.size for a in arrays), "initializer_bytes": sum(a.nbytes for a in arrays),
            "operators": dict(Counter(n.op_type for n in model.graph.node)),
            "limits": "Initializer elements include helper constants; not an FPGA resource estimate."}


def runner(variant):
    if variant["model"] == "segformer":
        import onnxruntime as ort
        config = json.loads((SEGFORMER / "preprocessor_config.json").read_text(encoding="utf-8"))
        options = ort.SessionOptions()
        options.intra_op_num_threads = SETTINGS["threads"]
        options.inter_op_num_threads = 1
        options.enable_cpu_mem_arena = False
        options.enable_mem_pattern = False
        session = ort.InferenceSession(str(SEGFORMER / "model.onnx"), sess_options=options, providers=["CPUExecutionProvider"])
        name = session.get_inputs()[0].name

        def infer(pixels):
            tensor = prepare(Image.fromarray(pixels), config)
            start = time.perf_counter()
            logits = session.run(None, {name: tensor})[0][0]
            elapsed = (time.perf_counter() - start) * 1000
            return softmax(logits), elapsed

        return infer, seg_inventory(), {"runtime": ort.__version__, "provider": session.get_providers(),
                                       "cpu_memory_arena": False, "memory_pattern": False}
    import openvino as ov
    path = HERE / "models" / MODEL_NAME / variant["model"] / f"{MODEL_NAME}.xml"
    core = ov.Core()
    model = core.read_model(path)
    h, w = variant["shape"]
    model.reshape([1, 3, h, w])
    inventory = ov_inventory(model)
    compiled = core.compile_model(model, "CPU", {"INFERENCE_NUM_THREADS": SETTINGS["threads"], "NUM_STREAMS": 1,
                                                "INFERENCE_PRECISION_HINT": "f32"})

    def infer(pixels):
        if variant.get("pad"):
            ih, iw = pixels.shape[:2]
            if iw != w or ih > h:
                raise ValueError("Unexpected thumbnail/padding size")
            prepared = np.pad(pixels, ((0, h - ih), (0, 0), (0, 0)), mode="edge")
        else:
            prepared = np.asarray(Image.fromarray(pixels).resize((w, h), Image.Resampling.BILINEAR))
        tensor = np.ascontiguousarray(prepared[..., ::-1].transpose(2, 0, 1)[None], dtype=np.float32)
        start = time.perf_counter()
        probabilities = compiled([tensor])[compiled.output(0)][0].copy()
        elapsed = (time.perf_counter() - start) * 1000
        if probabilities.shape != (4, h, w):
            raise ValueError(f"Unexpected model output: {probabilities.shape}")
        if variant.get("pad"):
            probabilities = probabilities[:, :ih, :iw]
        return probabilities, elapsed

    return infer, inventory, {"runtime": ov.__version__, "device": "CPU", "fp32_precision_hint": True,
                              "published_quantization": variant["model"] == "FP16-INT8",
                              "note": "Published mixed-precision graph, not all-INT8 FPGA arithmetic."}


def panel(pixels, mask, filtered, score, title, path):
    w, h = 480, 270
    canvas = Image.new("RGB", (2*w, 2*h+92), "#151719")
    draw = ImageDraw.Draw(canvas)
    font = ImageFont.truetype("C:/Windows/Fonts/arial.ttf", 16)
    draw.text((8, 5), title, fill="white", font=font)
    draw.text((8, 27), "OFFLINE CPU REGRESSION - NOT FPGA OUTPUT OR DRIVING VALIDATION", fill="#edc773", font=font)
    dim = pixels.copy()
    dim[~mask] //= 5
    heat = np.stack((score, score, score), axis=-1)
    items = ((pixels, "RGB565 input"), (dim, "Accepted road + marking region"),
             (filtered, "Unchanged v4 markings gated by road mask"), ((heat*255).astype(np.uint8), "Road score (not calibrated confidence)"))
    for i, (array, caption) in enumerate(items):
        x, y = i%2*w, 50+i//2*(h+20)
        draw.text((x+8, y), caption, font=font, fill="white")
        canvas.paste(Image.fromarray(array).resize((w, h), Image.Resampling.BILINEAR), (x, y+20))
    canvas.save(path)


def verify_models():
    manifest = json.loads((HERE / "model_provenance.json").read_text(encoding="utf-8"))
    for item in manifest["files"]:
        if digest(HERE / "models" / MODEL_NAME / item["file"]) != item["sha256"]:
            raise ValueError(f"Model/source hash mismatch: {item['file']}")
    if digest(SEGFORMER / "model.onnx") != SEG_SHA:
        raise ValueError("SegFormer model hash mismatch")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=HERE / "output")
    args = parser.parse_args()
    if args.output.exists():
        raise FileExistsError("Refusing to replace an existing experiment")
    verify_models()
    protected = protected_hashes()
    dataset_path = ROOT / "tests/fixtures/road_first/dataset.json"
    dataset = json.loads(dataset_path.read_text(encoding="utf-8"))
    args.output.mkdir(parents=True)
    images = []
    for entry in dataset["images"]:
        path = (dataset_path.parent / entry["file"]).resolve()
        with Image.open(path) as loaded:
            reference = ImageOps.exif_transpose(loaded).convert("RGB").resize((1280, 720), Image.Resampling.BILINEAR)
        pixels, white, yellow, _ = detect(reference)
        images.append((entry, pixels.astype(np.uint8), white, yellow, digest(path)))
    report = {"settings": SETTINGS, "variants": VARIANTS, "dataset_sha256": digest(dataset_path),
              "evaluation_kind": "all 14 previously inspected images reused for regression; not untouched holdout",
              "pixel_ground_truth": False, "fpga_deployed": False, "training_performed": False,
              "provenance_sha256": digest(HERE / "model_provenance.json"),
              "protected_files_before": protected, "results": []}
    masks = {}
    for variant in VARIANTS:
        print(f"START {variant['id']}", flush=True)
        result = {"variant": variant, "records": []}
        try:
            infer, inventory, runtime = runner(variant)
        except Exception as error:
            result.update(status="UNSUPPORTED", error=str(error))
            report["results"].append(result)
            print(json.dumps(result), flush=True)
            continue
        result.update(status="OK", inventory=inventory, runtime=runtime)
        vdir = args.output / variant["id"]
        vdir.mkdir()
        # Warmup is excluded; the measured value remains CPU inference only.
        dummy = images[0][1]
        infer(dummy if variant["scale"] == 1 else thumbnail(dummy, variant["scale"]))
        for entry, pixels, white, yellow, source_sha in images:
            prepared = pixels if variant["scale"] == 1 else thumbnail(pixels, variant["scale"])
            probabilities, elapsed = infer(prepared)
            low, score, candidate = gate(probabilities, [6] if variant["model"] == "segformer" else [1, 3])
            mask = np.asarray(Image.fromarray(low).resize((1280, 720), Image.Resampling.NEAREST))
            filtered = pixels.copy()
            filtered[white & mask] = (0, 255, 0)
            filtered[yellow & mask] = (0, 255, 255)
            idir = vdir / entry["id"]
            idir.mkdir()
            Image.fromarray(prepared).save(idir / "input.png")
            Image.fromarray(low).save(idir / "mask.png")
            Image.fromarray(filtered).save(idir / "gated_markings.png")
            np.savez_compressed(idir / "prediction.npz", probabilities=probabilities,
                                score=score, mask=low)
            panel(pixels, mask, filtered, score, f"{variant['id']} | {entry['id']}", idir / "comparison.png")
            masks[(variant["id"], entry["id"])] = low
            record = {"id": entry["id"], "road_present": entry["road_present"], "source_sha256": source_sha,
                      "source_kind": entry["source_kind"], "road_candidate": candidate,
                      "road_fraction": float(mask.mean()), "baseline_paint_pixels": int((white | yellow).sum()),
                      "gated_paint_pixels": int(((white | yellow) & mask).sum()), "inference_ms": elapsed}
            result["records"].append(record)
            print(json.dumps({"variant": variant["id"], **record}), flush=True)
            del probabilities
        positives = [r for r in result["records"] if r["road_present"]]
        negatives = [r for r in result["records"] if not r["road_present"]]
        result["summary"] = {"road_candidate_images": sum(r["road_candidate"] for r in positives),
                             "road_images": len(positives), "false_road_candidate_images": sum(r["road_candidate"] for r in negatives),
                             "nonroad_images": len(negatives), "nonroad_false_paint_pixels": sum(r["gated_paint_pixels"] for r in negatives),
                             "median_cpu_inference_ms": float(np.median([r["inference_ms"] for r in result["records"]]))}
        report["results"].append(result)
        (args.output / "partial_results.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
        del infer
        gc.collect()
    # Agreement measures change, not correctness; neither model is ground truth.
    for result in report["results"]:
        for record in result["records"]:
            a = masks[(result["variant"]["id"], record["id"])]
            b = masks[("segformer_full", record["id"])]
            union = int((a | b).sum())
            record["mask_iou_against_segformer_not_accuracy"] = float((a & b).sum()/union) if union else None
    report["protected_files_after"] = protected_hashes()
    report["protected_files_unchanged"] = protected == report["protected_files_after"]
    if not report["protected_files_unchanged"]:
        raise RuntimeError("Protected source/bitstream changed during evaluation")
    (args.output / "results.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(json.dumps([{r["variant"]["id"]: r.get("summary", r.get("error"))} for r in report["results"]], indent=2))


if __name__ == "__main__":
    main()
