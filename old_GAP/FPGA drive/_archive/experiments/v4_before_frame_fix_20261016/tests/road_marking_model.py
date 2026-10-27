"""Integer reference for lane_detect.v; overlays are candidates, not accuracy scores."""

import argparse
import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw


WIDTH, HEIGHT = 1280, 720
CONTRAST_RADIUS = 8
SUPPORT_RADIUS = 6
MIN_ROWS = 6
YELLOW_MIN_WIDTH = 64
YELLOW_MAX_WIDTH = 96


def suppress_wide_yellow(mask):
    """Reject whole horizontal blobs, including their leading/trailing edges."""
    height, width = mask.shape
    padded = np.pad(mask, ((0, 0), (4, 4)))
    # Horizontal closing joins gaps up to four pixels within foliage-like blobs.
    closed = np.logical_and.reduce([
        np.logical_or.reduce([padded[:, start + k:start + k + width] for k in range(5)])
        for start in range(5)
    ])
    filtered = mask.copy()
    for row in range(height):
        limit = min(YELLOW_MAX_WIDTH, YELLOW_MIN_WIDTH
                    + max(0, row - height * 9 // 16) // 8)
        edges = np.diff(np.pad(closed[row].astype(np.int8), (1, 1)))
        starts, ends = np.flatnonzero(edges == 1), np.flatnonzero(edges == -1)
        for start, end in zip(starts, ends):
            if end - start > limit:
                filtered[row, start:end] = False
    return filtered


def rgb565(image):
    pixels = np.asarray(image.convert("RGB"), dtype=np.uint16)
    r, g, b = pixels[..., 0] >> 3, pixels[..., 1] >> 2, pixels[..., 2] >> 3
    return np.stack(((r << 3) | (r >> 2), (g << 2) | (g >> 4),
                     (b << 3) | (b >> 2)), axis=-1).astype(np.int32)


def features(image):
    pixels = rgb565(image)
    height, width = pixels.shape[:2]
    r, g, b = pixels.transpose(2, 0, 1)
    y = (77 * r + 150 * g + 29 * b) >> 8
    padded = np.pad(y, 1, mode="edge")
    smooth = np.zeros_like(y)
    for dy, wy in enumerate((1, 2, 1)):
        for dx, wx in enumerate((1, 2, 1)):
            smooth += wy * wx * padded[dy:dy + height, dx:dx + width]
    y = smooth >> 4
    return pixels, y


def detect(image):
    pixels, y = features(image)
    height, width = y.shape
    r, g, b = pixels.transpose(2, 0, 1)
    left = np.zeros_like(y)
    right = np.zeros_like(y)
    left[:, CONTRAST_RADIUS:] = y[:, :-CONTRAST_RADIUS]
    right[:, :-CONTRAST_RADIUS] = y[:, CONTRAST_RADIUS:]
    contrast = y - np.minimum(left, right)

    # Yellow paint is chromatic; white paint must stand out from nearby asphalt.
    yellow = ((r >= 96) & (g >= 80) & (r >= b + 28) & (g >= b + 20)
              & (r + 32 >= g) & (g + 80 >= r))
    white = ((np.minimum(np.minimum(r, g), b) >= 96)
             & (np.maximum(np.maximum(r, g), b)
                - np.minimum(np.minimum(r, g), b) <= 56)
             & (y >= 112) & (contrast >= 20))

    yy, xx = np.indices((height, width))
    roi_top = height * 9 // 16
    depth = np.maximum(0, yy - roi_top)
    half_width = width // 4 + 3 * depth
    roi = ((yy >= roi_top) & (yy < height - 2)
           & (np.abs(xx - width // 2) <= half_width)
           & (xx >= CONTRAST_RADIUS) & (xx < width - CONTRAST_RADIUS))
    white &= roi & ~yellow
    yellow &= roi
    candidate = white | yellow
    scores = np.zeros_like(y, dtype=np.uint8)
    for row in range(1, height):
        padded = np.pad(scores[row - 1], SUPPORT_RADIUS)
        best = np.maximum.reduce([padded[offset:offset + width]
                                  for offset in range(2 * SUPPORT_RADIUS + 1)])
        scores[row] = np.where(candidate[row], np.minimum(best + 1, 7), 0)
    accepted = scores >= MIN_ROWS
    return (pixels.astype(np.uint8), white & accepted,
            suppress_wide_yellow(yellow & accepted), candidate)


def filter_fixture():
    image = Image.new("RGB", (WIDTH, HEIGHT), (70, 70, 70))
    draw = ImageDraw.Draw(image)
    draw.rectangle((250, 430, 510, 690), fill=(220, 180, 45))
    for x in range(275, 500, 22):
        draw.rectangle((x, 430, x + 2, 690), fill=(70, 70, 70))
    draw.rectangle((610, 430, 625, 710), fill=(220, 180, 45))
    draw.rectangle((644, 430, 661, 710), fill=(220, 180, 45))
    draw.line([(760, 430), (1100, 710)], fill=(235, 235, 235), width=8)
    # A blob touching the right active edge must not leak into the next row.
    draw.rectangle((1140, 560, 1279, 690), fill=(220, 180, 45))
    # Exercise exact and over-limit widths through both threshold extremes.
    for top, bottom, exact_x, wide_x in [(410, 425, 350, 460), (580, 710, 20, 145)]:
        for row in range(top, bottom + 1):
            limit = min(YELLOW_MAX_WIDTH,
                        YELLOW_MIN_WIDTH + (row - HEIGHT * 9 // 16) // 8)
            draw.line((exact_x, row, exact_x + limit - 1, row), fill=(220, 180, 45))
            draw.line((wide_x, row, wide_x + limit, row), fill=(220, 180, 45))
    return image


def synthetic_tests():
    height, width = HEIGHT, WIDTH
    background = np.full((height, width, 3), 70, dtype=np.uint8)
    for color in [(70, 70, 70), (180, 180, 180), (30, 150, 35)]:
        flat = np.empty_like(background)
        flat[:] = color
        _, white, yellow, _ = detect(Image.fromarray(flat))
        assert not (white | yellow).any(), f"Flat background accepted: {color}"
    noise = np.random.default_rng(0).integers(-16, 17, background.shape[:2])
    texture = np.repeat(np.clip(95 + noise, 0, 255)[..., None], 3, axis=2).astype(np.uint8)
    _, white, yellow, _ = detect(Image.fromarray(texture))
    assert not (white | yellow).any(), "Low-contrast asphalt texture accepted"

    image = Image.fromarray(background)
    draw = ImageDraw.Draw(image)
    draw.line([(620, 365), (190, 715)], fill=(235, 235, 235), width=6)
    draw.line([(660, 365), (1100, 715)], fill=(235, 235, 235), width=6)
    draw.line([(638, 365), (600, 715)], fill=(220, 180, 45), width=8)
    draw.line([(646, 365), (635, 715)], fill=(220, 180, 45), width=8)
    _, white, yellow, _ = detect(image)
    assert white[:, :width // 2].sum() > 200
    assert white[:, width // 2:].sum() > 200
    assert yellow.sum() > 1000
    assert not (white[:height // 2] | yellow[:height // 2]).any()

    # A new dash must acquire support independently; no lines bridge the gap.
    dashed = Image.fromarray(background)
    draw = ImageDraw.Draw(dashed)
    draw.line([(700, 450), (760, 490)], fill="white", width=6)
    draw.line([(850, 550), (910, 590)], fill="white", width=6)
    _, white, yellow, _ = detect(dashed)
    assert white[452:490].sum() > 50
    assert white[552:590].sum() > 50
    assert not (white[500:540] | yellow[500:540]).any()

    _, white, yellow, _ = detect(filter_fixture())
    assert not yellow[440:691, 250:511].any(), "Perforated yellow blob leaked"
    assert not yellow[570:691, 1140:].any(), "Right-edge yellow blob leaked"
    assert yellow[440:710, 610:626].all(), "Thin center line lost"
    assert yellow[440:710, 644:662].all(), "Second thin center line lost"
    assert white.sum() > 500, "White markings changed by yellow filter"
    for row in range(590, 711):
        limit = min(YELLOW_MAX_WIDTH, YELLOW_MIN_WIDTH
                    + (row - HEIGHT * 9 // 16) // 8)
        assert yellow[row, 20:20 + limit].all(), "Exact-limit marking lost"
        assert not yellow[row, 145:146 + limit].any(), "Over-limit marking leaked"

    # Exact-width runs survive; over-width runs disappear entirely, not just tails.
    masks = np.zeros((HEIGHT, WIDTH), dtype=bool)
    row = 600
    limit = min(YELLOW_MAX_WIDTH, YELLOW_MIN_WIDTH + (row - HEIGHT * 9 // 16) // 8)
    masks[row, 20:20 + limit] = True
    masks[row, 200:201 + limit] = True
    masks[row, :10] = True
    masks[row, -10:] = True
    filtered = suppress_wide_yellow(masks)
    assert filtered[row, 20:20 + limit].all()
    assert not filtered[row, 200:201 + limit].any()
    assert filtered[row, :10].all() and filtered[row, -10:].all()
    print("Synthetic checks passed: negatives, diagonal/dashed lines, "
          "wide/perforated blobs, thin double lines, width/row-edge boundaries.")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("images", nargs="*")
    parser.add_argument("--output", type=Path, default=Path("tests/output"))
    parser.add_argument("--vectors", action="store_true")
    parser.add_argument("--filter-fixture", action="store_true")
    args = parser.parse_args()
    synthetic_tests()
    args.output.mkdir(parents=True, exist_ok=True)
    results = []
    sources = list(args.images or sorted((Path(__file__).parent / "fixtures").glob("road_*.png")))
    if args.filter_fixture:
        fixture_path = args.output / "filter_fixture.png"
        filter_fixture().save(fixture_path)
        sources.append(fixture_path)
    for index, name in enumerate(sources, 1):
        image = Image.open(name).convert("RGB").resize((WIDTH, HEIGHT), Image.Resampling.BILINEAR)
        pixels, white, yellow, raw = detect(image)
        overlay = pixels.copy()
        overlay[white] = (0, 255, 0)
        overlay[yellow] = (0, 255, 255)
        mask = np.zeros_like(pixels)
        mask[white] = (0, 255, 0)
        mask[yellow] = (0, 255, 255)
        Image.fromarray(overlay).save(args.output / f"road_{index}_overlay.png")
        Image.fromarray(mask).save(args.output / f"road_{index}_mask.png")
        if args.vectors:
            _, luminance = features(image)
            p = pixels.astype(np.uint32)
            packed = ((p[..., 0] >> 3) << 11) | ((p[..., 1] >> 2) << 5) | (p[..., 2] >> 3)
            vectors = ((packed << 16) | (luminance.astype(np.uint32) << 8)
                       | (white.astype(np.uint32) << 1) | yellow.astype(np.uint32))
            np.savetxt(args.output / f"road_{index}.hex", vectors.reshape(-1), fmt="%08x")
        results.append({"source": str(Path(name).resolve()), "white_pixels": int(white.sum()),
                        "yellow_pixels": int(yellow.sum()), "raw_candidates": int(raw.sum())})
    (args.output / "results.json").write_text(json.dumps(results, indent=2), encoding="utf-8")
    print(json.dumps(results, indent=2))


if __name__ == "__main__":
    main()
