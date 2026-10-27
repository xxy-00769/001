"""Fetch a pinned OMZ release and verify the publisher's size/SHA384 manifest."""
import hashlib
import json
from pathlib import Path
import urllib.request

import yaml

HERE = Path(__file__).resolve().parent
REVISION = "27a654e312e7aa89ad72648784753d522e3a0a4e"
BASE = f"https://raw.githubusercontent.com/openvinotoolkit/open_model_zoo/{REVISION}"
MODEL = "road-segmentation-adas-0001"


def fetch(url, path):
    path.parent.mkdir(parents=True, exist_ok=True)
    if not path.exists():
        with urllib.request.urlopen(url, timeout=90) as response:
            data = response.read()
        path.write_bytes(data)
    return path.read_bytes()


def main():
    root = HERE / "models" / MODEL
    provenance = {"repository": "openvinotoolkit/open_model_zoo", "release": "2023.0.0",
                  "commit": REVISION, "files": []}
    for name in ("README.md", "model.yml", "accuracy-check.yml", "LICENSE"):
        relative = name if name == "LICENSE" else f"models/intel/{MODEL}/{name}"
        url = f"{BASE}/{relative}"
        data = fetch(url, root / name)
        provenance["files"].append({"file": name, "url": url, "bytes": len(data),
                                    "sha256": hashlib.sha256(data).hexdigest()})
    manifest = yaml.safe_load((root / "model.yml").read_text(encoding="utf-8"))
    for item in manifest["files"]:
        if not item["name"].startswith(("FP32/", "FP16-INT8/")):
            continue
        data = fetch(item["source"], root / item["name"])
        if len(data) != item["size"] or hashlib.sha384(data).hexdigest() != item["checksum"]:
            raise ValueError(f"Publisher checksum/size mismatch: {item['name']}")
        provenance["files"].append({"file": item["name"], "url": item["source"],
                                    "bytes": len(data), "sha384": item["checksum"],
                                    "sha256": hashlib.sha256(data).hexdigest(),
                                    "publisher_checksum_verified": True})
        print(f"VERIFIED {item['name']} {len(data)} bytes", flush=True)
    (HERE / "model_provenance.json").write_text(json.dumps(provenance, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
