"""Model-derived integer convolution/residual contracts, not a full FPGA model."""
from __future__ import annotations

import importlib.util
import json
from pathlib import Path
import sys

import numpy as np
import openvino as ov

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
L0_DIR = HERE.parent / "road_integer_l0_20261017"
spec = importlib.util.spec_from_file_location("first_layer_reference", L0_DIR / "reference.py")
l0 = importlib.util.module_from_spec(spec)
spec.loader.exec_module(l0)
SHIFT = 36
OPTIONS = {"INFERENCE_PRECISION_HINT": "f32", "INFERENCE_NUM_THREADS": 2, "NUM_STREAMS": 1}
MAX_INPUT = 32768
MAX_WEIGHTS = 8192
MAX_CHANNELS = 80


def load_model():
    l0.verify_models()
    path = l0.MODEL_DIR / "models" / l0.MODEL_NAME / "FP16-INT8" / f"{l0.MODEL_NAME}.xml"
    model = ov.Core().read_model(path)
    model.reshape([1, 3, l0.H, l0.W])
    return model


def const(node):
    if node.get_type_name() == "Reshape":
        value = const(node.input_value(0).get_node())
        return value.reshape(list(node.get_output_shape(0)))
    return l0.constant(node)


def quant_limits(node, channels):
    if node.get_type_name() != "FakeQuantize" or node.get_attributes()["levels"] != 256:
        raise ValueError("Expected 256-level activation FakeQuantize")
    low, high, olow, ohigh = [const(node.input_value(i).get_node()).reshape(-1).astype(np.float64) for i in range(1, 5)]
    if not np.array_equal(low, olow) or not np.array_equal(high, ohigh):
        raise ValueError("Range-changing FakeQuantize not supported")
    low, high = np.broadcast_to(low, (channels,)).copy(), np.broadcast_to(high, (channels,)).copy()
    if not np.all(np.isfinite(low)) or not np.all(high > low):
        raise ValueError("Invalid activation range")
    return {"low": low, "step": (high - low) / 255.0, "high": high}


def decode(codes, limits):
    return codes.astype(np.float64) * limits["step"][:, None, None] + limits["low"][:, None, None]


def encode(real, limits):
    return np.clip(np.floor((real - limits["low"][:, None, None]) / limits["step"][:, None, None] + 0.5), 0, 255).astype(np.uint8)


def fixed_coeff(gain, offset):
    gains = np.floor(np.asarray(gain, dtype=np.float64) * (1 << SHIFT) + 0.5).astype(np.int64)
    offsets = np.floor(np.asarray(offset, dtype=np.float64) * (1 << SHIFT) + 0.5).astype(np.int64)
    if np.any(np.abs(gains) >= 1 << 47) or np.any(np.abs(offsets) >= 1 << 63):
        raise ValueError("Coefficient does not fit hardware")
    return gains, offsets


def extract_conv(model, name):
    nodes = {n.get_friendly_name(): n for n in model.get_ordered_ops()}
    node = nodes[name]
    kind = node.get_type_name()
    if kind not in ("Convolution", "GroupConvolution"):
        raise ValueError("Not a convolution")
    ci = int(node.get_input_shape(0)[1])
    co = int(node.get_output_shape(0)[1])
    attrs = node.get_attributes()
    depthwise = kind == "GroupConvolution"
    weight_source = node.input_value(1).get_node()
    if weight_source.get_type_name() == "Reshape":
        weight_source = weight_source.input_value(0).get_node()
    if weight_source.get_type_name() != "Multiply":
        raise ValueError("Expected compressed weights with per-channel scales")
    weight_raw = const(weight_source.input_value(0).get_node())
    if not np.all(weight_raw == np.rint(weight_raw)) or np.any(weight_raw < -128) or np.any(weight_raw > 127):
        raise ValueError("Weights are not signed INT8")
    weights = weight_raw.astype(np.int8)
    sw = const(weight_source.input_value(1).get_node()).reshape(-1).astype(np.float64)
    if depthwise and (co != ci or weights.shape[1] != 1):
        raise ValueError("Only depthwise group convolutions supported")
    kernel = weights.shape[-1]
    if weights.shape != (co, 1 if depthwise else ci, kernel, kernel):
        raise ValueError("Only square convolution kernels supported")
    if any(attrs[k][0] != attrs[k][1] for k in ("strides", "dilations", "pads_begin", "pads_end")):
        raise ValueError("Asymmetric geometry not supported")
    input_node = node.input_value(0).get_node()
    qin = input_node
    # MaxPool only selects existing per-channel codes; it does not change scale.
    while qin.get_type_name() == "MaxPool":
        qin = qin.input_value(0).get_node()
    limits_in = quant_limits(qin, ci)
    if np.any(limits_in["low"] != 0):
        raise ValueError("Nonzero convolution input low requires a padding/zero-point extension")
    if not depthwise and not np.all(limits_in["step"] == limits_in["step"][0]):
        raise ValueError("Regular convolution input scales must be uniform")
    bias_node = nodes.get(name.removesuffix("/WithoutBiases"))
    if bias_node is None:
        raise ValueError("No supported bias/output-quantizer chain (final float classifier)")
    if bias_node.get_type_name() != "Add" or bias_node.input_value(0).get_node() != node:
        raise ValueError("Missing convolution bias")
    bias = const(bias_node.input_value(1).get_node()).reshape(-1).astype(np.float64)
    successors = [p.get_node() for p in bias_node.output(0).get_target_inputs() if p.get_node().get_type_name() != "ShapeOf"]
    relu = False
    if len(successors) == 1 and successors[0].get_type_name() == "Relu":
        relu = True
        successors = [p.get_node() for p in successors[0].output(0).get_target_inputs() if p.get_node().get_type_name() != "ShapeOf"]
    if len(successors) != 1 or successors[0].get_type_name() != "FakeQuantize":
        raise ValueError("No unique direct output quantizer (e.g. final float classifier)")
    qout = successors[0]
    limits_out = quant_limits(qout, co)
    if relu and np.any(limits_out["low"] != 0):
        raise ValueError("ReLU/output-low combination needs explicit activation")
    sx = limits_in["step"] if depthwise else limits_in["step"][0]
    gain_real = sx * sw / limits_out["step"]
    bias_real = (bias - limits_out["low"]) / limits_out["step"]
    gain, offset = fixed_coeff(gain_real, bias_real)
    pos = np.maximum(weights.astype(np.int64), 0).sum(axis=(1, 2, 3)) * 255
    neg = np.minimum(weights.astype(np.int64), 0).sum(axis=(1, 2, 3)) * 255
    if np.any(pos >= 1 << 31) or np.any(neg < -(1 << 31)):
        raise ValueError("Accumulator overflow")
    # NumPy uses signed int64; also guard its reference implementation, not just RTL.
    for c in range(co):
        if max(abs(int(neg[c])*int(gain[c])+int(offset[c])), abs(int(pos[c])*int(gain[c])+int(offset[c]))) >= (1 << 63) - (1 << 35):
            raise ValueError("Reference fixed-point overflow")
    return {"name": name, "depthwise": depthwise, "ci": ci, "co": co,
            "kernel": kernel, "stride": attrs["strides"][0], "dilation": attrs["dilations"][0],
            "pad": attrs["pads_begin"][0], "input_shape": list(node.get_input_shape(0))[1:],
            "output_shape": list(node.get_output_shape(0))[1:], "weights": weights,
            "gain": gain, "offset": offset, "gain_real": gain_real, "bias_real": bias_real,
            "weight_scales": sw, "float_bias": bias,
            "qin_name": input_node.get_friendly_name(), "qout_name": qout.get_friendly_name(),
            "limits_in": limits_in, "limits_out": limits_out, "acc_low": neg, "acc_high": pos,
            "relu": relu}


def convolve(codes, p):
    if tuple(codes.shape) != tuple(p["input_shape"]) or codes.dtype != np.uint8:
        raise ValueError("Wrong input feature shape/type")
    _, oh, ow = p["output_shape"]
    s, d, pad = p["stride"], p["dilation"], p["pad"]
    values = np.pad(codes.astype(np.int64), ((0, 0), (pad, pad), (pad, pad)))
    acc = np.zeros((p["co"], oh, ow), dtype=np.int64)
    for y in range(p["kernel"]):
        for x in range(p["kernel"]):
            patch = values[:, y*d:y*d+oh*s:s, x*d:x*d+ow*s:s]
            w = p["weights"][:, :, y, x].astype(np.int64)
            if p["depthwise"]:
                acc += patch * w[:, 0, None, None]
            else:
                acc += (w @ patch.reshape(p["ci"], -1)).reshape(acc.shape)
    return acc


def requant(acc, p):
    return np.clip((acc * p["gain"][:, None, None] + p["offset"][:, None, None] + (1 << 35)) >> SHIFT, 0, 255).astype(np.uint8)


def affine_oracle(acc, p):
    return np.clip(np.floor(acc * p["gain_real"][:, None, None] + p["bias_real"][:, None, None] + 0.5), 0, 255).astype(np.uint8)


def tile(codes, p, x, y, ow=4, oh=4):
    if not 1 <= ow <= 4 or not 1 <= oh <= 4 or x < 0 or y < 0 or x+ow > p["output_shape"][2] or y+oh > p["output_shape"][1]:
        raise ValueError("Invalid output tile")
    iw = (ow-1)*p["stride"] + (p["kernel"]-1)*p["dilation"] + 1
    ih = (oh-1)*p["stride"] + (p["kernel"]-1)*p["dilation"] + 1
    padded = np.pad(codes, ((0, 0), (p["pad"], p["pad"]), (p["pad"], p["pad"])))
    pixels = padded[:, y*p["stride"]:y*p["stride"]+ih, x*p["stride"]:x*p["stride"]+iw].copy()
    if pixels.shape != (p["ci"], ih, iw) or pixels.size > MAX_INPUT or p["weights"].size > MAX_WEIGHTS:
        raise ValueError("Tile exceeds hardware storage")
    desc = [int(p["depthwise"]), p["ci"], p["co"], p["kernel"], p["stride"], p["dilation"], iw, ih, ow, oh]
    return desc, pixels


def coefficient_bytes(p):
    return np.frombuffer(b"".join(int(g).to_bytes(6, "little", signed=True) + int(b).to_bytes(8, "little", signed=True)
                                  for g, b in zip(p["gain"], p["offset"])), dtype=np.uint8).copy()


def native_tile(codes, p):
    """Independent OpenVINO op graph; not the original full-network fusion."""
    param = ov.opset13.parameter([1, *codes.shape], np.float32)
    w = p["weights"].astype(np.float32) * p["weight_scales"].astype(np.float32)[:, None, None, None]
    args = dict(strides=[p["stride"]]*2, pads_begin=[0, 0], pads_end=[0, 0], dilations=[p["dilation"]]*2)
    if p["depthwise"]:
        value = ov.opset13.group_convolution(param, w.reshape(p["co"], 1, 1, p["kernel"], p["kernel"]), **args)
    else:
        value = ov.opset13.convolution(param, w, **args)
    value = ov.opset13.add(value, p["float_bias"].astype(np.float32)[None, :, None, None])
    if p["relu"]:
        value = ov.opset13.relu(value)
    low = p["limits_out"]["low"].astype(np.float32)[None, :, None, None]
    high = p["limits_out"]["high"].astype(np.float32)[None, :, None, None]
    value = ov.opset13.fake_quantize(value, low, high, low, high, 256)
    compiled = ov.Core().compile_model(ov.Model([value], [param]), "CPU", OPTIONS)
    actual = compiled([decode(codes, p["limits_in"]).astype(np.float32)[None]])[compiled.output(0)][0].copy()
    return encode(actual, p["limits_out"])


def residual_params(model):
    nodes = {n.get_friendly_name(): n for n in model.get_ordered_ops()}
    a = quant_limits(nodes["L0007_AddBackward1/fq_input_0"], 16)
    b = quant_limits(nodes["L0002_Conv2d_BN/WithoutBiases/fq_input_0"], 16)
    out = quant_limits(nodes["L0009_Conv2d_BN/WithoutBiases/fq_input_0"], 16)
    if np.any(out["low"] != 0):
        raise ValueError("Residual ReLU requires zero output low")
    ga, offset = fixed_coeff(a["step"]/out["step"], (a["low"]+b["low"]-out["low"])/out["step"])
    gb, _ = fixed_coeff(b["step"]/out["step"], np.zeros(16))
    return {"gain_a": ga, "gain_b": gb, "offset": offset, "a": a, "b": b, "out": out}


def residual(a, b, p):
    if a.shape != b.shape or a.dtype != np.uint8 or b.dtype != np.uint8:
        raise ValueError("Residual features must have equal uint8 shapes")
    fixed = a.astype(np.int64)*p["gain_a"][:, None, None] + b.astype(np.int64)*p["gain_b"][:, None, None] + p["offset"][:, None, None]
    return np.clip((fixed + (1 << 35)) >> SHIFT, 0, 255).astype(np.uint8)


def write_json(path, data):
    Path(path).write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")


def inventory(model):
    supported, unsupported = [], []
    for node in model.get_ordered_ops():
        if node.get_type_name() not in ("Convolution", "GroupConvolution"):
            continue
        try:
            p = extract_conv(model, node.get_friendly_name())
            dummy = np.zeros(p["input_shape"], np.uint8)
            desc, pixels = tile(dummy, p, 0, 0, min(4,p["output_shape"][2]), min(4,p["output_shape"][1]))
            supported.append({"name": p["name"], "descriptor": desc, "input_tile_bytes": pixels.size,
                              "weight_bytes": p["weights"].size, "qout": p["qout_name"],
                              "gain_bits": int(max(abs(int(v)) for v in p["gain"])).bit_length()+1,
                              "offset_bits": int(max(abs(int(v)) for v in p["offset"])).bit_length()+1})
        except ValueError as error:
            unsupported.append({"name": node.get_friendly_name(), "reason": str(error)})
    return {"supported": supported, "unsupported": unsupported, "scope": "Convolution arithmetic only; not complete model execution or hardware scheduling."}


if __name__ == "__main__":
    report = inventory(load_model())
    write_json(HERE / "operator_inventory.json", report)
    print(f"Supported convolution contracts: {len(report['supported'])}; unsupported: {report['unsupported']}")
