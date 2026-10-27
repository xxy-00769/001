# Rejected Perspective-Gate Probe

This is a software feasibility probe, not a deployed FPGA change. It uses the
unchanged version 4 candidate mask and a Python approximation of the version 8
band summaries. It is not an RTL equivalence claim.

The added fixed condition requires two common distant bands, outward movement
of at least 16 pixels on each side, and width growth of at least 64 pixels.
Thresholds were chosen before this run, not tuned on the regression outputs.

Result on the previously inspected 14-image regression: **0/6 road images and
0/8 nonroad images pass**. Even the original pair requirement fails on these
images. This is not successful false-positive suppression: every road loses its
markings. Do not deploy this as a road-presence gate and do not infer absence of
a road from absence of a lane pair.

Reproduce with the project Python environment:

```powershell
.\.venv-road-seg\Scripts\python.exe experiments/road_context_gate_20261017/evaluate.py
```

The output directory must not already exist. Per-image counts, points, and
before/after panels are written there. No RTL or bitstream is modified. There
are no pixel-level labels or fresh independent test data in this experiment.
The script's release flag is only a necessary rejection screen, never a
sufficient authorization to publish a bitstream.
