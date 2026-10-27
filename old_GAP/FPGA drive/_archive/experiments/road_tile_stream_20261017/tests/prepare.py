"""Pack fixed validated CHW/OIHW vectors into channel-striped 128-bit words."""
import hashlib
import json
from pathlib import Path
import shutil
import sys

import numpy as np

HERE = Path(__file__).resolve().parents[1]
BASE = HERE.parent / "road_parallel_conv_20261017"
sys.path.insert(0, str(HERE.parent / "road_integer_ops_20261017"))
import reference as ref


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def bank_words(data, channels):
    values = np.asarray(data, dtype=np.uint8).reshape(channels, -1)
    plane = values.shape[1]
    words = []
    for start in range(0, channels, 16):
        count = min(16, channels-start)
        # Poison unused lanes: hardware must respect the exact tail mask.
        block = np.full((plane, 16), 0xA5, dtype=np.uint8)
        block[:, :count] = values[start:start+count].T
        mask = (1 << count)-1
        words.extend((mask << 128) | int.from_bytes(row.tobytes(), "little") for row in block)
    # Independent inverse mapping checks lane order, tail bytes and local addresses.
    restored = np.empty_like(values)
    for address, word in enumerate(words):
        group, position = divmod(address, plane)
        mask = word >> 128
        for lane in range(16):
            if mask & (1 << lane):
                restored[group*16+lane, position] = (word >> (lane*8)) & 255
    np.testing.assert_array_equal(restored, values)
    return words


def main():
    out = HERE / "tests/output"
    out.mkdir(exist_ok=True)
    old = BASE / "tests/output"
    verified = json.loads((BASE / "verification.json").read_text(encoding="utf-8"))
    for table in ("source_sha256", "evidence_sha256"):
        for path, value in verified[table].items():
            assert digest(BASE / path) == value, f"Previous stage changed: {path}"
    names = ("inputs.hex", "weights.hex", "coefficients.hex", "expected.hex", "cases.json", "cases.vh", "descriptors.txt")
    previous = {}
    for name in names:
        shutil.copyfile(old / name, out / name)
        previous[name] = digest(old / name)
    arrays = [np.loadtxt(out / name, dtype=np.uint8, converters=lambda value: int(value, 16))
              for name in names[:3]]
    cases = json.loads((out / "cases.json").read_text(encoding="utf-8"))
    # Same coefficients, different tile geometry: reuse must invalidate only pixels.
    source = cases[0]
    dw, ci, co, kernel, *_ = source["descriptor"]
    raw_weight = arrays[1][source["offsets"][1]:source["offsets"][1]+source["lengths"][1]]
    raw_coeff = arrays[2][source["offsets"][2]:source["offsets"][2]+source["lengths"][2]]
    gains = [int.from_bytes(raw_coeff[c*14:c*14+6].tobytes(), "little", signed=True) for c in range(co)]
    biases = [int.from_bytes(raw_coeff[c*14+6:c*14+14].tobytes(), "little", signed=True) for c in range(co)]
    ends = [cases[-1]["offsets"][i]+cases[-1]["lengths"][i] for i in range(4)]
    rng = np.random.default_rng(20261019)
    for ow, oh, stride, dilation in ((1, 1, 1, 1), (2, 3, 2, 2), (4, 2, 1, 3), (1, 4, 2, 8)):
        iw = (ow-1)*stride+(kernel-1)*dilation+1
        ih = (oh-1)*stride+(kernel-1)*dilation+1
        pixels = rng.integers(0, 256, (ci, ih, iw), dtype=np.uint8)
        p = dict(ci=ci, co=co, kernel=kernel, stride=stride, dilation=dilation, pad=0,
                 depthwise=dw, weights=raw_weight.view(np.int8).reshape(co, ci, kernel, kernel),
                 input_shape=pixels.shape, output_shape=(co, oh, ow))
        acc = ref.convolve(pixels, p)
        codes = np.array([min(255, max(0, (int(value)*gains[c]+biases[c]+(1 << 35)) >> 36))
                          for c in range(co) for value in acc[c].reshape(-1)], dtype=np.uint8)
        packed = ((acc.reshape(-1).astype(np.uint64) & 0xffffffff) << 8) | codes
        data = (pixels.reshape(-1), raw_weight, raw_coeff, packed)
        lengths = [a.size for a in data]
        cases.append(dict(id=len(cases), name=source["name"], label="reuse_geometry_change",
                          descriptor=[dw, ci, co, kernel, stride, dilation, iw, ih, ow, oh],
                          offsets=list(ends), lengths=lengths))
        for i, values in enumerate(data):
            with (out / names[i]).open("a", encoding="ascii") as stream:
                np.savetxt(stream, values, fmt="%010x" if i==3 else "%02x")
            if i<3:
                arrays[i] = np.concatenate((arrays[i], values))
            ends[i] += lengths[i]
    ref.write_json(out / "cases.json", cases)
    (out / "descriptors.txt").write_text("".join(" ".join(map(str, c["descriptor"]+c["offsets"]+c["lengths"]))+"\n"
                                                for c in cases), encoding="ascii")
    (out / "cases.vh").write_text(f"localparam CASES={len(cases)}, INPUT_BYTES={ends[0]}, WEIGHT_BYTES={ends[1]}, "
                                  f"COEFF_BYTES={ends[2]}, OUTPUT_VALUES={ends[3]};\n", encoding="ascii")
    vectors = []
    rows = []
    tags = {}
    last_key = None
    for case in cases:
        dw, ci, co, k, *_ = case["descriptor"]
        data = [a[start:start+length] for a, start, length in zip(arrays, case["offsets"], case["lengths"])]
        key = hashlib.sha256(bytes([dw, ci, co, k]) + data[1].tobytes() + data[2].tobytes()).hexdigest()
        tag = tags.setdefault(key, len(tags)+1)
        offsets, lengths = [], []
        for values, channels in zip(data, (ci, co, co)):
            words = bank_words(values, channels)
            offsets.append(len(vectors)); lengths.append(len(words)); vectors.extend(words)
        rows.append(dict(id=case["id"], tag=tag, cache_key=key, reuse=int(key==last_key),
                         offsets=offsets, lengths=lengths))
        last_key = key
    (out / "vectors.hex").write_text("".join(f"{word:036x}\n" for word in vectors), encoding="ascii")
    (out / "vector_descriptors.txt").write_text("".join(" ".join(map(str, [r["tag"], r["reuse"]]+r["offsets"]+r["lengths"]))+"\n"
                                                       for r in rows), encoding="ascii")
    (out / "vector_cases.vh").write_text(f"localparam VECTOR_WORDS={len(vectors)};\n", encoding="ascii")
    ref.write_json(out / "vector_cases.json", rows)
    ref.write_json(out / "previous_inputs.json", previous)
    ref.write_json(out / "protected_before.json", ref.l0.protected_hashes())
    print(f"Prepared {len(cases)} fixed cases, {len(vectors)} vectors, {sum(r['reuse'] for r in rows)} adjacent reuse jobs")


if __name__ == "__main__":
    main()
