"""Reuse pinned tile/layer vectors without modifying the previous experiments."""
import hashlib
import json
from pathlib import Path
import shutil
import sys

HERE = Path(__file__).resolve().parents[1]
OPS = HERE.parent / "road_integer_ops_20261017"
sys.path.insert(0, str(OPS))
import reference as ref

BASES = {"tile": HERE.parent / "road_tile_stream_20261017",
         "layer": HERE.parent / "road_layer_dma_20261017"}


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def read_json(path):
    return json.loads(Path(path).read_text(encoding="utf-8-sig"))


def main():
    provenance = {}
    for kind, base in BASES.items():
        manifest = base / "verification.json"
        verified = read_json(manifest)
        for table in ("source_sha256", "evidence_sha256"):
            for path, value in verified[table].items():
                assert digest(base / path) == value, f"Previous artifact changed: {base.name}/{path}"
        provenance[str(manifest.relative_to(HERE.parent))] = digest(manifest)
        names = ("cases.vh", "cases.json", "inputs.hex", "weights.hex", "coefficients.hex",
                 "expected.hex", "descriptors.txt", "vectors.hex", "vector_cases.vh",
                 "vector_cases.json", "vector_descriptors.txt") if kind == "tile" else (
                 "cases.vh", "cases.json", "initial.hex", "golden.hex", "transactions.hex",
                 "descriptors.hex", "jobs.txt")
        target = HERE / "tests" / kind / "output"
        target.mkdir(exist_ok=True)
        for name in names:
            source = base / "tests/output" / name
            shutil.copyfile(source, target / name)
            provenance[str(source.relative_to(HERE.parent))] = digest(source)
    out = HERE / "tests/output"
    out.mkdir(exist_ok=True)
    ref.write_json(out / "previous_inputs.json", provenance)
    ref.write_json(out / "protected_before.json", ref.l0.protected_hashes())
    print("Pinned tile and whole-layer vectors copied; prior evidence and protected main files verified")


if __name__ == "__main__":
    main()
