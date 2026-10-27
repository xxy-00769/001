"""Generate unannotated board test cards and independent v4 pixel expectations."""
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

from road_marking_model import detect


def main():
    output = Path(__file__).parent / "output" / "zebra"
    output.mkdir(parents=True, exist_ok=True)
    for name, color, bars, width, gap, top, bottom in [
        ("01_positive_bars", (255, 255, 255), 4, 40, 40, 440, 519),
        ("02_negative_two_lines", (255, 255, 255), 2, 16, 320, 300, 719),
        ("03_negative_white_area", (255, 255, 255), 1, 480, 0, 400, 650),
        ("04_negative_cyan", (0, 255, 255), 4, 40, 40, 440, 519),
        ("05_negative_yellow", (255, 255, 0), 4, 40, 40, 440, 519),
        ("06_negative_blank", (255, 255, 255), 0, 40, 40, 440, 519),
    ]:
        image = Image.new("RGB", (1280, 720), (66, 69, 66))
        draw = ImageDraw.Draw(image)
        for bar in range(bars):
            x = 400 + bar * (width + gap)
            draw.rectangle((x, top, x + width - 1, bottom), fill=color)
        image.save(output / f"{name}.png")
        if name == "01_positive_bars":
            pixels, white, yellow, _ = detect(image)
            rgb = pixels.astype(np.uint32)
            packed = ((rgb[..., 0] >> 3) << 11) | ((rgb[..., 1] >> 2) << 5) | (rgb[..., 2] >> 3)
            overlay = np.where(yellow, 0x07FF, np.where(white, 0x07E0, packed))
            np.savetxt(output / "positive.hex", ((packed << 16) | overlay).reshape(-1), fmt="%08X")
    print(f"Created 6 unannotated 1280x720 test cards and v4 pixel oracle in {output}")


if __name__ == "__main__":
    main()
