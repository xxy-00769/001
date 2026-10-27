"""Audit the entire bounded accumulator domain, not thresholds fitted to image examples."""
from pathlib import Path
import sys

import numpy as np

HERE = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(HERE))
import reference as ref


def main():
    params, _ = ref.extract()
    records = []
    for shift in (30, 34, 36, 40, 44):
        counts, checked = [], 0
        for channel in range(16):
            weights = params["weights"][channel].astype(np.int64)
            low = int(weights[weights < 0].sum()) * 255
            high = int(weights[weights > 0].sum()) * 255
            acc = np.arange(low, high+1, dtype=np.int64)
            alpha = params["input_step"] * params["weight_scales"][channel] / params["output_step"]
            beta = params["float_bias"][channel] / params["output_step"]
            gain = int(np.floor(alpha * (1 << shift) + 0.5))
            offset = int(np.floor(beta * (1 << shift) + 0.5))
            fixed = np.clip((acc * gain + offset + (1 << (shift-1))) >> shift, 0, 255)
            ideal = np.clip(np.floor(acc * alpha + beta + 0.5), 0, 255)
            counts.append(int(np.count_nonzero(fixed != ideal)))
            checked += len(acc)
        records.append({"shift": shift, "checked_accumulator_channel_pairs": checked,
                        "code_differences_against_float64_affine": sum(counts),
                        "differences_by_channel": counts})
        print(records[-1], flush=True)
    ref.write_json(HERE / "precision_audit.json", {"scope": "Exhaustive integer accumulator interval bounded by 27 uint8*int8 terms; float64 affine is a numeric oracle, not bit-exact OpenVINO float32 execution.",
                                                "records": records})


if __name__ == "__main__":
    main()
