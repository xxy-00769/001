"""Independent array-based box-mean reference for the streaming RTL."""
from pathlib import Path
import json
import sys

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tests"))
from road_marking_model import rgb565


def pack(p):
    p = p.astype(np.uint32)
    return ((p[..., 0] >> 3) << 11) | ((p[..., 1] >> 2) << 5) | (p[..., 2] >> 3)


def reference(pixels):
    h, w = pixels.shape[:2]
    if h % 8 or w % 8:
        raise ValueError("Dimensions must be divisible by eight")
    return pixels.reshape(h // 8, 8, w // 8, 8, 3).sum(axis=(1, 3), dtype=np.uint32) // 64


def write_pair(name, pixels, output):
    for variant in range(2):
        p = pixels if variant == 0 else 255 - pixels
        small = reference(p)
        expected = np.repeat(np.repeat(pack(small), 8, axis=0), 8, axis=1)
        vector = (pack(p) << 16) | expected
        np.savetxt(output / f"{name}_{variant}.hex", vector.reshape(-1), fmt="%08x")
        Image.fromarray(small.astype(np.uint8)).save(output / f"{name}_{variant}.png")


def main():
    output = Path(__file__).with_name("output")
    output.mkdir(exist_ok=True)
    y, x = np.indices((32, 64), dtype=np.uint16)
    synthetic = np.stack(((x * 13 + y * 7) % 256, (x * 7 + y * 11) % 256,
                          (x * 3 + y * 19) % 256), axis=-1).astype(np.uint8)
    write_pair("small", rgb565(Image.fromarray(synthetic)), output)
    extreme = np.zeros((32, 64, 3), dtype=np.uint8)
    for block, color in enumerate(((255, 255, 255), (0, 0, 0), (255, 0, 0),
                                   (0, 255, 0), (0, 0, 255), (255, 255, 0),
                                   (0, 255, 255), (255, 0, 255))):
        extreme[:, block*8:(block+1)*8] = color
    write_pair("extreme", rgb565(Image.fromarray(extreme)), output)
    for name, source in (("road", ROOT / "tests/fixtures/road_3.png"),
                         ("shelf", ROOT / "tests/fixtures/road_first/negative_shelf_dark.png")):
        image = Image.open(source).convert("RGB").resize((1280, 720), Image.Resampling.BILINEAR)
        write_pair(name, rgb565(image), output)
    for color in ((0, 0, 0), (255, 255, 255), (255, 0, 0), (0, 255, 0), (0, 0, 255)):
        flat = rgb565(Image.new("RGB", (64, 32), color))
        assert (reference(flat) == flat[0, 0]).all()
    (output / "reference.json").write_text(json.dumps({
        "scale": 8, "method": "RGB565 decode to 8-bit channels, floor 8x8 box mean, encode RGB565",
        "cases": ["small", "extreme", "road", "shelf"], "variants_per_case": 2,
        "flat_color_checks": 5,
        "limits": "Input preparation only; no semantic accuracy or FPGA inference claim."
    }, indent=2), encoding="utf-8")
    print("PASS: generated four independent vector pairs; five flat-color checks")


if __name__ == "__main__":
    main()
