"""Pin previous-stage evidence and reuse its full-layer vectors unchanged."""
import hashlib
import json
from pathlib import Path
import shutil
import sys

HERE = Path(__file__).resolve().parents[1]
ROOT = HERE.parents[1]
PREVIOUS = HERE.parent / "road_config_pipe_20261017"
OUT = HERE / "tests/output"


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def read_json(path):
    return json.loads(Path(path).read_text(encoding="utf-8-sig"))


def write_json(path, value):
    path.write_text(json.dumps(value, indent=2, ensure_ascii=True) + "\n", encoding="ascii")


def protected():
    sys.path.insert(0, str(HERE.parent / "road_integer_ops_20261017"))
    import reference
    return reference.l0.protected_hashes()


def main():
    OUT.mkdir(exist_ok=True)
    pin = read_json(PREVIOUS / "verification.json")
    for table in ("source_sha256", "evidence_sha256"):
        for name, value in pin[table].items():
            assert digest(PREVIOUS / name) == value, f"Previous evidence changed: {name}"
    provenance = {}
    for name in ("cases.vh", "cases.json", "initial.hex", "golden.hex",
                 "transactions.hex", "descriptors.hex", "jobs.txt"):
        src = PREVIOUS / "tests/layer/output" / name
        shutil.copyfile(src, OUT / name)
        provenance[str(src.relative_to(HERE.parent))] = digest(src)
    write_json(OUT / "previous_inputs.json", provenance)
    before = OUT / "protected_before.json"
    if before.exists():
        assert read_json(before) == protected(), "Protected main files changed"
    else:
        write_json(before, protected())
    print("Pinned stage-1 evidence verified; layer vectors copied without regeneration")


if __name__ == "__main__":
    main()
