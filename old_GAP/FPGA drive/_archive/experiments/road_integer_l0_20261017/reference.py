"""Pinned OMZ first-layer integer reference and tiled memory layout; no DDR driver."""
from __future__ import annotations

import hashlib
import json
from pathlib import Path
import sys

import numpy as np

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
MODEL_DIR = ROOT / "experiments/road_model_budget_20261017"
sys.path.insert(0, str(MODEL_DIR))
from evaluate import MODEL_NAME, protected_hashes, verify_models

W, H = 320, 192
TW, TH, IC, OC = 8, 8, 3, 16
IW, IH = 17, 17
SHIFT = 36


def constant(node):
    if node.get_type_name() == "Convert":
        return constant(node.input_value(0).get_node()).astype(np.float32)
    if node.get_type_name() != "Constant":
        raise ValueError(f"Expected constant, got {node.get_type_name()}")
    return np.asarray(node.data).copy()


def extract():
    import openvino as ov
    verify_models()
    path = MODEL_DIR / "models" / MODEL_NAME / "FP16-INT8" / f"{MODEL_NAME}.xml"
    model = ov.Core().read_model(path)
    model.reshape([1, 3, H, W])
    nodes = {n.get_friendly_name(): n for n in model.get_ordered_ops()}
    conv = nodes["L0000_Conv2d_BN/WithoutBiases"]
    attrs = conv.get_attributes()
    assert attrs["strides"] == [2, 2] and attrs["dilations"] == [1, 1]
    assert attrs["pads_begin"] == attrs["pads_end"] == [1, 1]
    fq_in = conv.input_value(0).get_node()
    fq_out = nodes["L0002_Conv2d_BN/WithoutBiases/fq_input_0"]
    limits = []
    for fq in (fq_in, fq_out):
        assert fq.get_type_name() == "FakeQuantize" and fq.get_attributes()["levels"] == 256
        low, high, olow, ohigh = [float(constant(fq.input_value(i).get_node()).item()) for i in range(1, 5)]
        assert low == olow == 0 and high == ohigh and high > 0
        limits.append(high)
    weight_multiply = conv.input_value(1).get_node()
    assert weight_multiply.get_type_name() == "Multiply"
    weights = constant(weight_multiply.input_value(0).get_node()).astype(np.int8)
    scales = constant(weight_multiply.input_value(1).get_node()).reshape(-1).astype(np.float64)
    bias = constant(nodes["L0000_Conv2d_BN"].input_value(1).get_node()).reshape(-1).astype(np.float64)
    assert weights.shape == (OC, IC, 3, 3) and len(scales) == len(bias) == OC
    input_step, output_step = np.asarray(limits) / 255.0
    lut = np.clip(np.floor(np.arange(256) * 255.0 / limits[0] + 0.5), 0, 255).astype(np.uint8)
    gain = np.floor(input_step * scales / output_step * (1 << SHIFT) + 0.5).astype(np.int64)
    offset = np.floor(bias / output_step * (1 << SHIFT) + 0.5).astype(np.int64)
    assert np.all((gain >= 0) & (gain < 1 << 31))
    assert np.all(np.abs(offset) < 1 << 47)
    # Exhaustively cross-check all possible raw channel values with the graph's FQ.
    p = ov.opset13.parameter([1, 3, 1, 256], np.float32)
    fq = ov.opset13.fake_quantize(p, *[constant(fq_in.input_value(i).get_node()) for i in range(1, 5)], 256)
    compiled = ov.Core().compile_model(ov.Model([fq], [p]), "CPU", {"INFERENCE_PRECISION_HINT": "f32", "INFERENCE_NUM_THREADS": 2})
    samples = np.tile(np.arange(256, dtype=np.float32), (1, 3, 1, 1))
    actual = compiled([samples])[compiled.output(0)]
    codes = np.rint(actual / input_step).astype(np.uint8)
    np.testing.assert_array_equal(codes[0, 0, 0], lut)
    params = {"weights": weights, "input_lut": lut, "gain": gain, "offset": offset,
              "weight_scales": scales, "float_bias": bias, "input_step": input_step,
              "output_step": output_step, "input_high": limits[0], "output_high": limits[1]}
    # This cut ends at the next layer's input FQ, including first-layer bias and ReLU.
    cut = ov.Model([fq_out.output(0)], model.get_parameters())
    cut_compiled = ov.Core().compile_model(cut, "CPU", {"INFERENCE_PRECISION_HINT": "f32", "INFERENCE_NUM_THREADS": 2, "NUM_STREAMS": 1})
    return params, cut_compiled


def conv_acc(raw_bgr, params):
    if raw_bgr.shape != (H, W, IC):
        raise ValueError("First-layer input must be 192x320 BGR")
    values = params["input_lut"][raw_bgr].astype(np.int64)
    padded = np.pad(values, ((1, 1), (1, 1), (0, 0)))
    acc = np.zeros((OC, H // 2, W // 2), dtype=np.int64)
    for ci in range(IC):
        for ky in range(3):
            for kx in range(3):
                patch = padded[ky:ky+H:2, kx:kx+W:2, ci]
                acc += params["weights"][:, ci, ky, kx, None, None].astype(np.int64) * patch[None]
    return acc


def requant(acc, params):
    fixed = acc * params["gain"][:, None, None] + params["offset"][:, None, None]
    return np.clip((fixed + (1 << (SHIFT - 1))) >> SHIFT, 0, 255).astype(np.uint8)


def float_reference_codes(acc, params):
    real = acc * (params["input_step"] * params["weight_scales"][:, None, None]) + params["float_bias"][:, None, None]
    return np.clip(np.floor(real / params["output_step"] + 0.5), 0, 255).astype(np.uint8)


def tile(raw_bgr, tx, ty):
    if raw_bgr.shape != (H, W, IC) or not 0 <= tx < W // (2 * TW) or not 0 <= ty < H // (2 * TH):
        raise ValueError("Invalid tile or frame dimensions")
    padded = np.pad(raw_bgr, ((1, 1), (1, 1), (0, 0)))
    return padded[ty * 16:ty * 16 + IH, tx * 16:tx * 16 + IW].copy()


def transfer_plan(tx, ty, base=0, frame_id=0):
    """32-byte aligned memory reads; invalid top/left samples are local zero fill."""
    if base % 32 or base < 0 or base + H * W * IC > 1 << 28:
        raise ValueError("Base must be nonnegative and 32-byte aligned")
    if not 0 <= tx < 20 or not 0 <= ty < 12:
        raise ValueError("Tile outside first-layer output")
    rows = []
    for row in range(IH):
        y = ty * 16 + row - 1
        x = tx * 16 - 1
        if y < 0:
            rows.append({"tile_row": row, "zero_prefix_bytes": 51, "source_byte": None, "payload_bytes": 0, "reads": []})
            continue
        left = max(x, 0)
        zero = max(-x, 0) * 3
        source = base + (y * W + left) * 3
        count = (IW - max(-x, 0)) * 3
        first = source // 32 * 32
        end = (source + count + 31) // 32 * 32
        if end > base + H * W * 3:
            raise ValueError("Aligned transfer crosses allocated image")
        rows.append({"tile_row": row, "zero_prefix_bytes": zero, "source_byte": source,
                     "payload_bytes": count, "reads": list(range(first, end, 32))})
    return {"frame_id": frame_id, "tile_x": tx, "tile_y": ty, "input_base_byte": base,
            "output_layout": "CHW full tensor; each tile output has channel-major 8x8 order",
            "rows": rows, "read_bytes": sum(32 * len(r["reads"]) for r in rows),
            "payload_bytes": sum(r["payload_bytes"] for r in rows),
            "local_zero_bytes": sum(r["zero_prefix_bytes"] for r in rows)}


def replay_plan(raw_bgr, plan):
    memory = raw_bgr.reshape(-1)
    out = np.zeros(IW * IH * IC, dtype=np.uint8)
    base = plan["input_base_byte"]
    for row in plan["rows"]:
        if not row["reads"]:
            continue
        fetched = np.concatenate([memory[a - base:a - base + 32] for a in row["reads"]])
        offset = row["source_byte"] - row["reads"][0]
        start = row["tile_row"] * 51 + row["zero_prefix_bytes"]
        out[start:start + row["payload_bytes"]] = fetched[offset:offset + row["payload_bytes"]]
    return out.reshape(IH, IW, IC)


def write_plan(tx, ty, base=0x200000, frame_id=0):
    """Abstract CHW feature writes with 32-byte data and per-byte strobes."""
    if base % 32 or base < 0 or base + OC * (H // 2) * (W // 2) > 1 << 28:
        raise ValueError("Invalid aligned output allocation")
    if not 0 <= tx < 20 or not 0 <= ty < 12:
        raise ValueError("Tile outside first-layer output")
    writes = []
    for channel in range(OC):
        for row in range(TH):
            byte = base + (channel * (H // 2) + ty*TH + row) * (W // 2) + tx*TW
            lane = byte % 32
            assert lane + TW <= 32
            writes.append({"address": byte // 32 * 32, "lane": lane,
                           "byte_enable": ((1 << TW) - 1) << lane,
                           "tile_offset": (channel * TH + row) * TW})
    return {"frame_id": frame_id, "tile_x": tx, "tile_y": ty, "output_base_byte": base,
            "payload_bytes": OC * TH * TW, "bus_bytes": len(writes) * 32, "writes": writes}


def replay_writes(memory, tile_features, plan):
    flat = np.asarray(tile_features, dtype=np.uint8).reshape(-1)
    if flat.size != OC * TH * TW or memory.size != OC * (H // 2) * (W // 2):
        raise ValueError("Feature tile or output allocation has wrong size")
    for write in plan["writes"]:
        data = np.zeros(32, dtype=np.uint8)
        lane, source = write["lane"], write["tile_offset"]
        data[lane:lane+TW] = flat[source:source+TW]
        address = write["address"] - plan["output_base_byte"]
        for byte in range(32):
            if write["byte_enable"] & (1 << byte):
                memory[address + byte] = data[byte]


def hash_file(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def export_rom(params):
    path = HERE / "source/layer0_params.v"
    lines = ["`timescale 1ns/1ps", "// Generated by tests/generate.py from pinned model constants; do not edit.",
             "module layer0_params(input [7:0] raw_pixel, input [8:0] weight_addr, input [3:0] channel,",
             "    output reg [7:0] input_code, output reg signed [7:0] weight,",
             "    output reg signed [31:0] gain, output reg signed [47:0] offset);",
             "always @* begin", "  case (raw_pixel)"]
    for i, v in enumerate(params["input_lut"]):
        lines.append(f"    8'd{i}: input_code = 8'd{v};")
    lines += ["    default: input_code = 0;", "  endcase", "end", "always @* begin", "  case (weight_addr)"]
    for i, v in enumerate(params["weights"].reshape(-1)):
        lines.append(f"    9'd{i}: weight = 8'h{int(v) & 255:02x};")
    lines += ["    default: weight = 0;", "  endcase", "end", "always @* begin", "  case (channel)"]
    for i, (g, b) in enumerate(zip(params["gain"], params["offset"])):
        lines.append(f"    4'd{i}: begin gain = 32'h{int(g):08x}; offset = 48'h{int(b) & ((1<<48)-1):012x}; end")
    lines += ["    default: begin gain = 0; offset = 0; end", "  endcase", "end", "endmodule", ""]
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(lines), encoding="ascii")


def write_json(path, data):
    path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
