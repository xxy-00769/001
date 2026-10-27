"""Reuse fixed serial vectors and add independently computed lane/bank edge cases."""
import hashlib
import json
from pathlib import Path
import shutil
import sys

import numpy as np

HERE = Path(__file__).resolve().parents[1]
BASE = HERE.parent / "road_integer_ops_20261017"
sys.path.insert(0, str(BASE))
import reference as ref


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def main():
    out = HERE / "tests/output"
    out.mkdir(exist_ok=True)
    old = BASE / "tests/output"
    evidence = json.loads((BASE / "verification.json").read_text(encoding="utf-8"))
    for table in ("source_sha256", "evidence_sha256"):
        for path, value in evidence[table].items():
            assert digest(BASE / path) == value, f"Baseline changed: {path}"
    cases = json.loads((old / "cases.json").read_text(encoding="utf-8"))
    assert len(cases) == 3214
    files = ("inputs.hex", "weights.hex", "coefficients.hex", "expected.hex")
    baseline_inputs = {}
    for name in files:
        shutil.copyfile(old / name, out / name)
        baseline_inputs[name] = digest(old / name)
    offsets = [cases[-1]["offsets"][i] + cases[-1]["lengths"][i] for i in range(4)]
    rng = np.random.default_rng(20261018)
    descriptors = []
    # Lane boundaries, partial groups, maximum channel counts and maximum dilation.
    for co in (1, 3, 15, 16, 17, 31, 32, 33, 63, 64, 65, 79, 80):
        for dw in (0, 1):
            ci = co if dw else (co * 7) % 80 + 1
            for k, s, d, ow, oh in ((1, 1, 1, 3, 2), (2, 2, 3, 2, 4), (3, 2, 8, 4, 3)):
                iw, ih = (ow-1)*s+(k-1)*d+1, (oh-1)*s+(k-1)*d+1
                if ci*iw*ih <= 32768 and co*(1 if dw else ci)*k*k <= 8192:
                    descriptors.append([dw, ci, co, k, s, d, iw, ih, ow, oh])
    # High local-bank addresses and maximum MAC length despite a partial group.
    descriptors.extend([[0, 80, 11, 3, 1, 1, 6, 6, 4, 4],
                        [0, 53, 17, 3, 1, 1, 6, 6, 4, 4],
                        [1, 61, 61, 3, 2, 8, 23, 23, 4, 4],
                        [1, 80, 80, 3, 1, 8, 20, 20, 4, 4]])
    for number, desc in enumerate(descriptors):
        dw, ci, co, k, s, d, iw, ih, ow, oh = desc
        pixels = rng.integers(0, 256, (ci, ih, iw), dtype=np.uint8)
        weights = rng.integers(-128, 128, (co, 1 if dw else ci, k, k), dtype=np.int16).astype(np.int8)
        if number % 5 == 0:
            pixels.fill(255)
            weights.fill(-128 if number % 2 else 127)
        gains = np.array([(-(1 << 47), (1 << 47)-1, 1 << 36, -(1 << 36), 0, 1234567)[i % 6]
                          for i in range(co)], dtype=np.int64)
        biases = np.array([(-(1 << 63), (1 << 63)-1, 127 << 36, 255 << 36, 1 << 35)[i % 5]
                           for i in range(co)], dtype=np.int64)
        p = dict(ci=ci, co=co, kernel=k, stride=s, dilation=d, pad=0, depthwise=dw,
                 weights=weights, gain=gains, offset=biases,
                 input_shape=pixels.shape, output_shape=(co, oh, ow))
        acc = ref.convolve(pixels, p)
        # Python integers avoid int64 overflow with extreme 48-bit/64-bit coefficients.
        codes = np.empty(acc.shape, dtype=np.uint8)
        for c in range(co):
            for y in range(oh):
                for x in range(ow):
                    value = (int(acc[c, y, x])*int(gains[c]) + int(biases[c]) + (1 << 35)) >> 36
                    codes[c, y, x] = min(255, max(0, value))
        coeffs = ref.coefficient_bytes(p)
        packed = ((acc.reshape(-1).astype(np.uint64) & 0xffffffff) << 8) | codes.reshape(-1)
        arrays = (pixels.reshape(-1), weights.reshape(-1).view(np.uint8), coeffs, packed)
        lengths = [a.size for a in arrays]
        cases.append(dict(id=len(cases), name="synthetic_lane_banks", label=f"lane_edge_{number}",
                          descriptor=desc, offsets=list(offsets), lengths=lengths))
        for i, (name, values) in enumerate(zip(files, arrays)):
            with (out / name).open("a", encoding="ascii") as stream:
                np.savetxt(stream, values, fmt="%010x" if i == 3 else "%02x")
            offsets[i] += lengths[i]
    ref.write_json(out / "cases.json", cases)
    ref.write_json(out / "baseline_inputs.json", baseline_inputs)
    ref.write_json(out / "protected_before.json", ref.l0.protected_hashes())
    (out / "descriptors.txt").write_text("".join(" ".join(map(str, c["descriptor"]+c["offsets"]+c["lengths"]))+"\n"
                                                for c in cases), encoding="ascii")
    (out / "cases.vh").write_text(f"localparam CASES={len(cases)}, INPUT_BYTES={offsets[0]}, WEIGHT_BYTES={offsets[1]}, "
                                  f"COEFF_BYTES={offsets[2]}, OUTPUT_VALUES={offsets[3]};\n", encoding="ascii")
    print(f"Prepared {len(cases)} cases / {offsets[3]} outputs; {len(descriptors)} new lane/bank cases")


if __name__ == "__main__":
    main()
