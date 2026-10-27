"""Independent frame-level geometry oracle and full RGB/overlay test vectors."""
from pathlib import Path
import json
import sys

import numpy as np
from PIL import Image, ImageDraw

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "host"))
from adas_protocol import Observation
from road_marking_model import detect

W, H = 1280, 720


def row_runs(row):
    points = np.flatnonzero(row)
    if not len(points):
        return []
    groups = np.split(points, np.flatnonzero(np.diff(points) > 5) + 1)
    return [(int(group[0]), int(group[-1])) for group in groups if 2 <= group[-1] - group[0] + 1 <= 64]


class GeometryModel:
    def __init__(self):
        self.frame = 0
        self.direction = 0
        self.warning_count = 0

    def run(self, mask, zebra=(False, False, 0, 0)):
        rows = [[], []]
        previous = [None, None]
        for y in range(405, 712):
            gated = mask[y].copy()
            gated[:128] = False
            gated[1152:] = False
            runs = row_runs(gated)
            mids = [(start + end) // 2 for start, end in runs] if len(runs) <= 6 else []
            candidates = [max((x for x in mids if x < 616), default=None),
                          min((x for x in mids if x > 664), default=None)]
            for side, value in enumerate(candidates):
                if value is not None and previous[side] is not None and abs(value - previous[side]) > 12:
                    value = None
                previous[side] = value
                if value is not None:
                    rows[side].append((y, value))
        coords, kinds, near, supports, valid = [], [], [], [], []
        for hits in rows:
            anchors = []
            near_point = None
            for anchor in (496, 560, 624, 688):
                values = [x for y, x in hits if anchor - 4 <= y <= anchor + 3]
                veto = zebra[0] and anchor + 3 >= zebra[2] and anchor - 4 <= zebra[3]
                if len(values) >= 6 and max(values) - min(values) <= 64 and not veto:
                    point = ((min(values) + max(values)) // 2, anchor)
                    anchors.append(point)
                    if anchor == 688:
                        near_point = point[0]
            ys = np.array([y for y, _ in hits], dtype=int)
            groups = np.split(ys, np.flatnonzero(np.diff(ys) > 1) + 1) if len(ys) else []
            segments = sum(len(group) >= 12 for group in groups)
            largest_gap = int(max(np.diff(ys), default=1) - 1) if len(ys) else 0
            good = len(anchors) >= 2 and anchors[-1][1] >= 624 and len(hits) >= 32
            kind = 0
            if good and not zebra[0]:
                if len(hits) * 4 >= 307 * 3 and largest_gap <= 8:
                    kind = 1
                elif segments >= 2 and largest_gap >= 12:
                    kind = 2
            valid.append(good)
            supports.append(len(hits))
            kinds.append(kind)
            near.append(near_point)
            coords.extend((*anchors[0], *anchors[-1]) if good else (0, 0, 0, 0))
        pair = all(valid) and all(x is not None for x in near) and 256 <= near[1] - near[0] <= 1024
        width = near[1] - near[0] if pair else 0
        offset = 640 - ((near[0] + near[1]) // 2) if pair else 0
        direction = (1 if offset < 0 else 2) if pair and abs(offset) * 6 >= width else 0
        if not direction:
            self.warning_count = 0
        else:
            self.warning_count = min(3, self.warning_count + 1) if direction == self.direction else 1
        self.direction = direction
        warning = direction if self.warning_count >= 3 else 0
        self.frame = (self.frame + 1) & 0xFFFF
        flags = 0x40 | int(valid[0]) | (int(valid[1]) << 1) | (int(pair) << 2) | (int(zebra[0]) << 3) | (int(zebra[1]) << 4)
        return Observation(flags, kinds[0] | (kinds[1] << 2) | (warning << 4), self.frame, offset, width,
                           *coords, *supports, zebra[2] if zebra[0] else 0, zebra[3] if zebra[0] else 0).validate()


# Human-readable 5x7 font oracle, independent of the RTL ROM implementation.
FONT = {
    "0": "01110 10001 10011 10101 11001 10001 01110",
    "1": "00100 01100 00100 00100 00100 00100 01110",
    "2": "01110 10001 00001 00010 00100 01000 11111",
    "3": "11110 00001 00001 01110 00001 00001 11110",
    "4": "00010 00110 01010 10010 11111 00010 00010",
    "5": "11111 10000 10000 11110 00001 00001 11110",
    "6": "01110 10000 10000 11110 10001 10001 01110",
    "7": "11111 00001 00010 00100 01000 01000 01000",
    "8": "01110 10001 10001 01110 10001 10001 01110",
    "9": "01110 10001 10001 01111 00001 00001 01110",
    "A": "01110 10001 10001 11111 10001 10001 10001",
    "B": "11110 10001 10001 11110 10001 10001 11110",
    "C": "01111 10000 10000 10000 10000 10000 01111",
    "D": "11110 10001 10001 10001 10001 10001 11110",
    "E": "11111 10000 10000 11110 10000 10000 11111",
    "F": "11111 10000 10000 11110 10000 10000 10000",
    "G": "01111 10000 10000 10111 10001 10001 01111",
    "H": "10001 10001 10001 11111 10001 10001 10001",
    "I": "01110 00100 00100 00100 00100 00100 01110",
    "K": "10001 10010 10100 11000 10100 10010 10001",
    "L": "10000 10000 10000 10000 10000 10000 11111",
    "M": "10001 11011 10101 10101 10001 10001 10001",
    "N": "10001 11001 10101 10011 10001 10001 10001",
    "O": "01110 10001 10001 10001 10001 10001 01110",
    "P": "11110 10001 10001 11110 10000 10000 10000",
    "R": "11110 10001 10001 11110 10100 10010 10001",
    "S": "01111 10000 10000 01110 00001 00001 11110",
    "T": "11111 00100 00100 00100 00100 00100 00100",
    "W": "10001 10001 10001 10101 10101 10101 01010",
    "X": "10001 10001 01010 00100 01010 10001 10001",
    "Z": "11111 00001 00010 00100 01000 10000 11111",
    ":": "00000 00100 00100 00000 00100 00100 00000",
    "+": "00000 00100 00100 11111 00100 00100 00000",
    "-": "00000 00000 00000 11111 00000 00000 00000",
    "?": "01110 10001 00001 00010 00100 00000 00100",
}


def to_rgb(packed):
    r, g, b = (packed >> 11) & 31, (packed >> 5) & 63, packed & 31
    return np.stack(((r << 3) | (r >> 2), (g << 2) | (g >> 4), (b << 3) | (b >> 2)), axis=-1).astype(np.uint8)


def render(base, shown, zebra):
    output = base.copy()
    yy, xx = np.indices(base.shape)
    if zebra[1]:
        edge = (xx >= 400) & (xx <= 679) & (yy >= 440) & (yy <= 519)
        edge &= (xx == 400) | (xx == 679) | (yy == 440) | (yy == 519)
        output[edge] = 0xF81F
    icon = (xx >= 16) & (xx < 48) & (yy >= 16) & (yy < 40) & (xx % 8 < 4)
    output[icon] = 0xF81F if zebra[1] else (0xFD20 if zebra[0] else 0x8410)
    if shown.pair_valid:
        center = (shown.left_x1 + shown.right_x1) // 2
        tick = ((yy >= 680) & (yy < 696) & (xx >= center) & (xx <= center + 1))
        tick |= (yy >= 700) & (yy < 712) & (xx >= 640) & (xx <= 641)
        output[tick] = 0xFFFF
    for flag, kind, points, color in (
        (2, shown.right_kind, (shown.right_x0, shown.right_y0, shown.right_x1, shown.right_y1), 0xFD20),
        (1, shown.left_kind, (shown.left_x0, shown.left_y0, shown.left_x1, shown.left_y1), 0x041F),
    ):
        x0, y0, x1, y1 = points
        if shown.flags & flag:
            error = (xx - x0) * (y1 - y0) - (yy - y0) * (x1 - x0)
            line = (yy >= y0) & (yy <= y1) & (np.abs(error) <= y1 - y0)
            if kind == 2:
                line &= (yy & 8) != 0
            output[line] = color
    kind_char = lambda flag, kind: "-" if not shown.flags & flag else "?SD"[kind]
    offset = f"{shown.offset_px:+04d}" if shown.pair_valid else "?---"
    z = "1" if shown.flags & 16 else ("?" if shown.flags & 8 else "0")
    text = f"L:{kind_char(1, shown.left_kind)} R:{kind_char(2, shown.right_kind)} OFF:{offset} PX Z:{z} F:{shown.frame_id:04X}"
    warning = (shown.types >> 4) & 3
    status = "NO PAIR" if not shown.pair_valid else ("TRACKING", "WARN LEFT", "WARN RIGHT")[warning]
    hud = output[16:48, 64:424]
    hud[:] = ((hud & 0xF800) >> 1) & 0xF800 | ((hud & 0x07E0) >> 1) & 0x07E0 | ((hud & 31) >> 1)
    for line_index, line in enumerate((text, status.ljust(15) + "EXPERIMENT")):
        for column, char in enumerate(line):
            color = 0xF800 if line_index == 1 and warning and column < 10 else 0xFFFF
            for gy, bits in enumerate(FONT.get(char, "00000 " * 7).split()):
                for gx, bit in enumerate(bits):
                    if bit == "1":
                        py, px = 16 + line_index * 16 + gy * 2, 64 + column * 12 + gx * 2
                        output[py:py+2, px:px+2] = color
    return output


def fixture(name):
    image = Image.new("RGB", (W, H), (66, 69, 66))
    draw = ImageDraw.Draw(image)
    if name == "zebra":
        for i in range(4):
            draw.rectangle((400+i*80, 440, 439+i*80, 519), fill="white")
    elif name != "blank":
        shift = -100 if name == "right_offset" else (100 if name == "left_offset" else 0)
        for y in range(405, 720):
            if name == "dashed" and not (y <= 515 or 548 <= y <= 643 or y >= 672):
                continue
            left = 500 - (y-405)//2 + shift
            right = 780 + (y-405)//2 + shift
            draw.line((left-3, y, left+3, y), fill="white")
            draw.line((right-3, y, right+3, y), fill="white")
    return image


def main():
    output = Path(__file__).parent / "output" / "adas"
    output.mkdir(parents=True, exist_ok=True)
    cache = {}
    for name in ("center", "right_offset", "left_offset", "blank", "dashed", "zebra"):
        image = fixture(name)
        image.save(output / f"card_{name}.png")
        rgb, white, yellow, _ = detect(image)
        rgb = rgb.astype(np.uint32)
        packed = ((rgb[..., 0] >> 3) << 11) | ((rgb[..., 1] >> 2) << 5) | (rgb[..., 2] >> 3)
        painted = np.where(yellow, 0x07FF, np.where(white, 0x07E0, packed)).astype(np.uint32)
        cache[name] = packed, painted, white | yellow
    sequence = ["center"] + ["right_offset"] * 4 + ["blank"] * 2 + ["dashed"] * 2 + ["zebra"] * 3 + ["blank"] * 2
    model = GeometryModel()
    previous = Observation(0x40, 0, 0, *([0] * 14))
    previous_zebra = (False, False, 0, 0)
    observations = []
    for i, name in enumerate(sequence):
        raw, painted, mask = cache[name]
        zebra = (name == "zebra", name == "zebra" and previous_zebra[0], 440, 519)
        result = model.run(mask, zebra)
        final = render(painted, previous, previous_zebra)
        np.savetxt(output / f"frame_{i:02d}.hex", ((raw << 16) | final).reshape(-1), fmt="%08X")
        if i in (1, 4, 8, 11):
            Image.fromarray(to_rgb(final)).save(output / f"expected_{i:02d}.png")
        observations.append(result)
        previous, previous_zebra = result, zebra
    assert observations[0].types == 5 and observations[0].offset_px == 0
    assert observations[3].types >> 4 == 2
    assert observations[6].flags == 0x40 and observations[6].types == 0
    assert observations[8].left_kind == 2 and observations[8].right_kind == 2
    assert observations[11].flags & 0x18 == 0x18 and not observations[11].pair_valid
    (output / "snapshots.hex").write_text("\n".join(f"{int.from_bytes(o.payload(), 'little'):064X}" for o in observations) + "\n", encoding="ascii")
    (output / "expected_results.json").write_text(json.dumps([{"fixture": n, **o.as_dict()} for n, o in zip(sequence, observations)], indent=2) + "\n", encoding="utf-8")
    # Exercise the same geometry oracle on the original user photographs.
    road_results = []
    road_model = GeometryModel()
    for path in sorted((Path(__file__).parent / "fixtures").glob("road_*.png")):
        image = Image.open(path).convert("RGB").resize((W, H), Image.Resampling.BILINEAR)
        _, white, yellow, _ = detect(image)
        road_results.append(road_model.run(white | yellow))
    (output / "roads_snapshots.hex").write_text("\n".join(f"{int.from_bytes(o.payload(), 'little'):064X}" for o in road_results) + "\n", encoding="ascii")
    print(json.dumps([{"fixture": n, **o.as_dict()} for n, o in zip(sequence, observations)], indent=2))
    print("Generated 14 complete-frame RGB/output vectors, snapshots, six board cards and four oracle previews")


if __name__ == "__main__":
    main()
