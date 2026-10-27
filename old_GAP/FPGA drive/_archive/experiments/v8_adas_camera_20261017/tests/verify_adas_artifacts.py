"""Cross-check saved RTL captures and previews; this is not a board test."""
from pathlib import Path
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "host"))
from adas_protocol import Decoder


def rgb(path):
    with Image.open(path) as image:
        assert image.size == (1280, 720), (path, image.size)
        return np.array(image.convert("RGB"))


def main():
    output = Path(__file__).parent / "output" / "adas"
    assert (output / "rtl_packets.bin").read_bytes() == (output / "packets_expected.bin").read_bytes()
    decoder = Decoder()
    records = decoder.feed((output / "rtl_pipeline_packets.bin").read_bytes())
    expected = [int(line, 16).to_bytes(32, "little")
                for line in (output / "snapshots.hex").read_text().splitlines()]
    assert len(records) == len(expected) == 14
    assert [record.payload() for record in records] == expected
    assert not decoder.buffer and not decoder.crc_errors and not decoder.invalid_packets
    print("PASS: 114 unit bytes, 532 pipeline bytes and 14 decoded payloads match independent vectors")

    for index, frame in enumerate((1, 4, 8, 11)):
        actual = rgb(output / f"rtl_preview_{index}.ppm")
        assert np.array_equal(actual, rgb(output / f"expected_{frame:02d}.png")), index
        Image.fromarray(actual).save(output / f"rtl_preview_{index}.png")
    print("PASS: four full 1280x720 RTL previews match independent pixel oracles")

    expected_image = rgb(output / "expected_01.png")
    # This captured transition frame uses current shifted RGB and prior centered geometry.
    glyphs = {
        "T": ("11111", "00100", "00100", "00100", "00100", "00100", "00100"),
        "E": ("11111", "10000", "10000", "11110", "10000", "10000", "11111"),
        "S": ("01111", "10000", "10000", "01110", "00001", "00001", "11110"),
    }
    expected_image[80:108, 32:128] = (66, 69, 66)
    for column, char in enumerate("TEST"):
        for gy, row in enumerate(glyphs[char]):
            for gx, bit in enumerate(row):
                if bit == "1":
                    y, x = 80 + gy * 4, 32 + column * 24 + gx * 4
                    expected_image[y:y+4, x:x+4] = (255, 255, 0)
    actual = rgb(output / "rtl_selftest.ppm")
    assert np.array_equal(actual, expected_image)
    Image.fromarray(actual).save(output / "rtl_selftest.png")
    print("PASS: complete selftest preview, including all TEST watermark pixels and one-frame delay")


if __name__ == "__main__":
    main()
