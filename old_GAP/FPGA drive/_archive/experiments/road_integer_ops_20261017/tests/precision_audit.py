"""Exhaustive first-block accumulator-domain and residual-pair rounding audit."""
from pathlib import Path
import sys

import numpy as np

HERE = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(HERE))
import reference as ref


def main():
    model = ref.load_model()
    rows = []
    for layer in (2,4,6):
        p = ref.extract_conv(model, f"L{layer:04d}_Conv2d_BN/WithoutBiases")
        for c in range(p["co"]):
            acc = np.arange(p["acc_low"][c], p["acc_high"][c]+1, dtype=np.int64)
            fixed = np.clip((acc*p["gain"][c]+p["offset"][c]+(1<<35)) >> 36, 0, 255)
            ideal = np.clip(np.floor(acc*p["gain_real"][c]+p["bias_real"][c]+0.5), 0, 255)
            mismatches = np.flatnonzero(fixed != ideal)
            rows.append({"layer":layer, "channel":c, "domain":acc.size, "mismatches":mismatches.size,
                         "first_mismatch_accumulators":acc[mismatches[:8]].tolist()})
    rp = ref.residual_params(model)
    a,b = np.indices((256,256), dtype=np.uint16)
    a,b = np.broadcast_to(a.astype(np.uint8),(16,256,256)), np.broadcast_to(b.astype(np.uint8),(16,256,256))
    actual = ref.residual(a,b,rp)
    ideal = ref.encode(np.maximum(ref.decode(a,rp["a"])+ref.decode(b,rp["b"]),0),rp["out"])
    result = {"shift":36,"checked_accumulator_channel_pairs":sum(r["domain"] for r in rows),
              "affine_mismatches":sum(r["mismatches"] for r in rows),"channels":rows,
              "residual_channel_pairs":actual.size,"residual_mismatches":int(np.count_nonzero(actual!=ideal)),
              "scope":"Compared with float64 formulas, not original fused model bit-equivalence."}
    ref.write_json(HERE / "precision_audit.json", result)
    print({k:v for k,v in result.items() if k!="channels"})


if __name__=="__main__": main()
