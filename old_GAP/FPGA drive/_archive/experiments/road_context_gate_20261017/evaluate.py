"""Fixed-rule feasibility probe. Not road segmentation or an FPGA deliverable."""
from __future__ import annotations

import json
from pathlib import Path
import sys

import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tests"))
from road_marking_model import detect


def geometry(mask):
    """Mirror the v8 narrow-run band summary, then test perspective separately."""
    height, width = mask.shape
    top = height * 9 // 16
    bands = (height - 224, height - 160, height - 96, height - 32)
    samples = [[[] for _ in bands] for _ in range(2)]
    total = [0, 0]
    previous = [None, None]
    for y in range(top, height - 8):
        row = mask[y].copy()
        row[:width // 10] = False
        row[width * 9 // 10:] = False
        starts = np.flatnonzero(np.diff(np.pad(row.astype(np.int8), (1, 1))) == 1)
        ends = np.flatnonzero(np.diff(np.pad(row.astype(np.int8), (1, 1))) == -1)
        runs = []
        for start, end in zip(starts.tolist(), ends.tolist()):
            if runs and start - runs[-1][1] <= 4:
                runs[-1][1] = end
            else:
                runs.append([start, end])
        midpoints = [(start + end - 1) // 2 for start, end in runs if 2 <= end - start <= 64]
        left = [x for x in midpoints if x < width // 2 - 24]
        right = [x for x in midpoints if x > width // 2 + 24]
        chosen = [max(left) if left else None, min(right) if right else None]
        for side, x in enumerate(chosen):
            good = x is not None and len(midpoints) <= 6
            good = good and (previous[side] is None or abs(x - previous[side]) <= 12)
            previous[side] = x if good else None
            if good:
                total[side] += 1
                for b, center in enumerate(bands):
                    if center - 4 <= y <= center + 3:
                        samples[side][b].append(x)
    points = []
    for side in range(2):
        points.append([(b, (min(xs) + max(xs)) // 2)
                       for b, xs in enumerate(samples[side])
                       if len(xs) >= 6 and max(xs) - min(xs) <= 64])
    valid = [len(p) >= 2 and p[-1][0] >= 2 and total[s] >= 32
             for s, p in enumerate(points)]
    pair = (all(valid) and all(p[-1][0] == 3 for p in points)
            and width // 5 <= points[1][-1][1] - points[0][-1][1] <= width * 4 // 5)
    perspective = False
    if pair:
        common = sorted(set(dict(points[0])) & set(dict(points[1])))
        if len(common) >= 2 and common[-1] - common[0] >= 2:
            far, near = common[0], common[-1]
            left, right = dict(points[0]), dict(points[1])
            # Fixed before running this regression; no dataset-derived tuning.
            perspective = (left[far] - left[near] >= 16
                           and right[near] - right[far] >= 16
                           and (right[near] - left[near]) - (right[far] - left[far]) >= 64)
    return {"pair": bool(pair), "perspective": bool(perspective),
            "support": total, "points": points, "bands": bands}


def run():
    dataset_path = ROOT / "tests/fixtures/road_first/dataset.json"
    dataset = json.loads(dataset_path.read_text(encoding="utf-8"))
    output = Path(__file__).with_name("output")
    if output.exists():
        raise FileExistsError(output)
    output.mkdir()
    records = []
    panels = []
    for entry in dataset["images"]:
        path = (dataset_path.parent / entry["file"]).resolve()
        source = Image.open(path).convert("RGB").resize((1280, 720), Image.Resampling.BILINEAR)
        pixels, white, yellow, _ = detect(source)
        state = geometry(white | yellow)
        overlay = pixels.copy()
        overlay[white] = (0, 255, 0)
        overlay[yellow] = (0, 255, 255)
        filtered = overlay if state["perspective"] else pixels
        record = {"id": entry["id"], "road_present": entry["road_present"],
                  "baseline_pixels": int((white | yellow).sum()), **state}
        records.append(record)
        panel = Image.new("RGB", (960, 298), "#202020")
        draw = ImageDraw.Draw(panel)
        draw.text((8, 5), f'{entry["id"]}: baseline | fixed perspective gate={state["perspective"]}', fill="white")
        panel.paste(Image.fromarray(overlay).resize((480, 270)), (0, 28))
        panel.paste(Image.fromarray(filtered).resize((480, 270)), (480, 28))
        panel.save(output / (entry["id"] + ".png"))
        panels.append(panel)
        print(json.dumps(record), flush=True)
    # A gate that removes all candidates is a failure, not a successful filter.
    positives = [r for r in records if r["road_present"]]
    negatives = [r for r in records if not r["road_present"]]
    summary = {"road_images_passing": sum(r["perspective"] for r in positives),
               "road_images": len(positives),
               "nonroad_images_passing": sum(r["perspective"] for r in negatives),
               "nonroad_images": len(negatives),
               "board_release_allowed": all(r["perspective"] for r in positives)
               and not any(r["perspective"] for r in negatives),
               "limits": "Previously inspected regression only; no pixel truth or board validation. Passing image counts would not establish semantic accuracy."}
    (output / "results.json").write_text(json.dumps({"summary": summary, "records": records}, indent=2), encoding="utf-8")
    print(json.dumps(summary), flush=True)
    for label, indices in (("roads", range(6)), ("nonroads", range(6, 14))):
        sheet = Image.new("RGB", (960, 298 * len(indices)))
        for row, index in enumerate(indices):
            sheet.paste(panels[index], (0, 298 * row))
        sheet.save(output / (label + ".png"))


if __name__ == "__main__":
    run()
