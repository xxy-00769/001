"""Whole-layer golden tensors and independent memory transaction plans."""
import hashlib
import json
from pathlib import Path
import sys

import numpy as np

HERE = Path(__file__).resolve().parents[1]
OPS = HERE.parent / "road_integer_ops_20261017"
PREVIOUS = HERE.parent / "road_tile_stream_20261017"
sys.path.insert(0, str(OPS))
import reference as ref

FIELDS = (("job_id", 0, 32), ("input_base", 32, 32), ("output_base", 64, 32),
          ("weight_base", 96, 32), ("param_base", 128, 32), ("arena_base", 160, 32),
          ("arena_limit", 192, 32), ("ci", 224, 7), ("co", 231, 7),
          ("kernel", 238, 2), ("stride", 240, 2), ("dilation", 242, 4),
          ("pad", 246, 5), ("iw", 251, 10), ("ih", 261, 10),
          ("ow", 271, 10), ("oh", 281, 10), ("depthwise", 291, 1))
CANARY = int.from_bytes(bytes(range(0xC0, 0xD0)), "little")


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def pack_descriptor(values):
    result = 0
    for name, shift, bits in FIELDS:
        value = int(values[name])
        if not 0 <= value < 1 << bits:
            raise ValueError(f"Descriptor field overflow: {name}")
        result |= value << shift
    return result


def striped(data):
    values = np.asarray(data, dtype=np.uint8).reshape(data.shape[0], -1)
    words = []
    for start in range(0, len(values), 16):
        block = np.tile(np.arange(0xC0, 0xD0, dtype=np.uint8), (values.shape[1], 1))
        block[:, :min(16, len(values)-start)] = values[start:start+16].T
        words.extend(int.from_bytes(row.tobytes(), "little") for row in block)
    return words


def scalar_oracle(pixels, p):
    """Small-case oracle uses direct indexed loops, no padding/slicing helper."""
    result = np.zeros(p["output_shape"], np.uint8)
    for oc, oy, ox in np.ndindex(result.shape):
        acc = 0
        for ic in ([oc] if p["depthwise"] else range(p["ci"])):
            for ky in range(p["kernel"]):
                for kx in range(p["kernel"]):
                    y = oy*p["stride"]+ky*p["dilation"]-p["pad"]
                    x = ox*p["stride"]+kx*p["dilation"]-p["pad"]
                    if 0 <= y < pixels.shape[1] and 0 <= x < pixels.shape[2]:
                        acc += int(pixels[ic, y, x])*int(p["weights"][oc, 0 if p["depthwise"] else ic, ky, kx])
        value = (acc*int(p["gain"][oc])+int(p["offset"][oc])+(1 << 35)) >> 36
        result[oc, oy, ox] = min(255, max(0, value))
    return result


def main():
    out = HERE / "tests/output"
    out.mkdir(exist_ok=True)
    provenance = {}
    for base in (PREVIOUS, OPS):
        verified = json.loads((base / "verification.json").read_text(encoding="utf-8"))
        for table in ("source_sha256", "evidence_sha256"):
            for path, value in verified[table].items():
                assert digest(base / path) == value, f"Previous evidence changed: {base.name}/{path}"
        provenance[str((base / "verification.json").relative_to(HERE.parent))] = digest(base / "verification.json")
    ref.write_json(out / "protected_before.json", ref.l0.protected_hashes())
    initial, golden, transactions, records = [CANARY]*8, [CANARY]*8, [], []

    def allocate(values, preload):
        base = len(initial)
        initial.extend(values if preload else [CANARY]*len(values))
        golden.extend(values)
        initial.extend([CANARY]*4)
        golden.extend([CANARY]*4)
        return base

    def add(p, pixels, input_base=None):
        result = ref.requant(ref.convolve(pixels, p), p)
        if result.size < 10000:
            np.testing.assert_array_equal(result, scalar_oracle(pixels, p))
        ib = allocate(striped(pixels), True) if input_base is None else input_base
        wb = allocate(striped(p["weights"].view(np.uint8)), True)
        cb = allocate(striped(ref.coefficient_bytes(p).reshape(p["co"], 14)), True)
        ob = allocate(striped(result), False)
        ci, ih, iw = pixels.shape
        co, oh, ow = result.shape
        fields = dict(job_id=len(records)+1, input_base=ib, output_base=ob, weight_base=wb,
                      param_base=cb, arena_base=8, ci=ci, co=co, kernel=p["kernel"],
                      stride=p["stride"], dilation=p["dilation"], pad=p["pad"],
                      iw=iw, ih=ih, ow=ow, oh=oh, depthwise=int(p["depthwise"]))
        start = len(transactions)
        reads = padding = tiles = 0

        def read(address):
            nonlocal reads
            transactions.append((address << 144) | golden[address])
            reads += 1

        for y in range(0, oh, 4):
            for x in range(0, ow, 4):
                if tiles == 0:
                    for base, length in ((cb, ((co+15)//16)*14),
                                         (wb, ((co+15)//16)*p["weights"].size//co)):
                        for offset in range(length):
                            read(base+offset)
                th, tw = min(4, oh-y), min(4, ow-x)
                tih = (th-1)*p["stride"]+(p["kernel"]-1)*p["dilation"]+1
                tiw = (tw-1)*p["stride"]+(p["kernel"]-1)*p["dilation"]+1
                for group in range((ci+15)//16):
                    for ly in range(tih):
                        for lx in range(tiw):
                            gy, gx = y*p["stride"]+ly-p["pad"], x*p["stride"]+lx-p["pad"]
                            if 0 <= gy < ih and 0 <= gx < iw:
                                read(ib+(group*ih+gy)*iw+gx)
                            else:
                                padding += 1
                for group in range((co+15)//16):
                    keep = (1 << min(16, co-group*16))-1
                    for ly in range(th):
                        for lx in range(tw):
                            address = ob+(group*oh+y+ly)*ow+x+lx
                            transactions.append((1 << 176) | (address << 144) | (keep << 128) | golden[address])
                tiles += 1
        records.append(dict(name=p["name"], fields=fields, transaction_start=start,
                            transaction_count=len(transactions)-start, read_words=reads,
                            write_words=((co+15)//16)*oh*ow, output_bytes=result.size,
                            tiles=tiles, zero_padding_vectors=padding, chained=input_base is not None))
        return result, ob

    rng = np.random.default_rng(20261020)
    shapes = [(1, 1, 1, 1, 1, 0, 5, 3, False), (3, 17, 3, 2, 1, 1, 9, 7, False),
              (17, 15, 2, 1, 3, 0, 10, 8, False), (17, 17, 3, 1, 2, 2, 7, 5, True),
              (80, 11, 3, 1, 1, 1, 7, 5, False), (61, 61, 3, 1, 8, 8, 5, 5, True),
              (1, 1, 3, 1, 8, 0, 19, 17, False), (3, 5, 3, 1, 1, 1, 1, 1, False),
              (1, 1, 1, 1, 1, 0, 1023, 1, False), (1, 1, 1, 1, 1, 0, 1, 1023, False)]
    for _ in range(16):
        ci = int(rng.choice([1, 3, 8, 16, 17, 31, 64, 80]))
        dw = bool(rng.integers(0, 2))
        co = ci if dw else int(rng.choice([1, 7, 16, 17, 33, 80]))
        k, d, s = int(rng.integers(1, 4)), int(rng.integers(1, 4)), int(rng.integers(1, 3))
        if not dw and (co*ci*k*k > 8192 or ((co+15)//16)*ci*k*k > 1024):
            k = 1
        pad = ((k-1)*d)//2
        shapes.append((ci, co, k, s, d, pad, 9, 7, dw))
    for index, (ci, co, k, s, d, pad, iw, ih, dw) in enumerate(shapes):
        ow, oh = (iw+2*pad-(k-1)*d-1)//s+1, (ih+2*pad-(k-1)*d-1)//s+1
        p = dict(name=f"synthetic_{index}", ci=ci, co=co, kernel=k, stride=s, dilation=d,
                 pad=pad, depthwise=dw, input_shape=(ci, ih, iw), output_shape=(co, oh, ow),
                 weights=rng.integers(-128, 128, (co, 1 if dw else ci, k, k), dtype=np.int8),
                 gain=rng.integers(-(1 << 27), 1 << 27, co, dtype=np.int64),
                 offset=rng.integers(30, 220, co, dtype=np.int64) << 36)
        pixels = rng.integers(0, 256, p["input_shape"], dtype=np.uint8)
        add(p, pixels)

    saved_path = OPS / "tests/output/legacy_road_3_block.npz"
    provenance[str(saved_path.relative_to(HERE.parent))] = digest(saved_path)
    model = ref.load_model()
    with np.load(saved_path) as saved:
        pixels, base = saved["input_codes"].copy(), None
        for number in (2, 4, 6):
            p = ref.extract_conv(model, f"L{number:04d}_Conv2d_BN/WithoutBiases")
            pixels, base = add(p, pixels, base)
        np.testing.assert_array_equal(pixels, saved["branch_codes"])
    for record in records:
        record["fields"]["arena_limit"] = len(initial)
        record["descriptor"] = f"{pack_descriptor(record['fields']):080x}"
    for name, values, width in (("initial.hex", initial, 32), ("golden.hex", golden, 32),
                                ("transactions.hex", transactions, 45)):
        (out / name).write_text("".join(f"{v:0{width}x}\n" for v in values), encoding="ascii")
    (out / "descriptors.hex").write_text("".join(r["descriptor"]+"\n" for r in records), encoding="ascii")
    (out / "jobs.txt").write_text("".join(" ".join(str(r[k]) for k in
        ("transaction_start", "transaction_count", "read_words", "write_words", "tiles", "zero_padding_vectors"))+"\n"
        for r in records), encoding="ascii")
    (out / "cases.vh").write_text(f"localparam CASES={len(records)}, MEMORY_WORDS={len(initial)}, TRANSACTIONS={len(transactions)};\n", encoding="ascii")
    ref.write_json(out / "cases.json", records)
    ref.write_json(out / "previous_inputs.json", provenance)
    print(f"Prepared {len(records)} layers, {len(initial)} memory words, {len(transactions)} transactions; three chained real-feature layers")


if __name__ == "__main__":
    main()
