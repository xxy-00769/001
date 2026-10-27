# Version 6 Frame Integrity Test Build

Built on 2026-10-16 from the archived sources and unchanged version 4 detector.
Only `img_proc.v` changed in the active design. The bitstream is retained at
`bitstreams/6_road_framefix_v4_cmos1.sbit` in the main project.

SHA256:

- Bitstream: `599C5A26752885DA38A8A8ECCA0D3FB53F3CA30854753DF0F0E20D4C83B942B9`
- `img_proc.v`: `8E22EF27BCC688C174DF5EE58D52A4B82641439DB15EBA79920F99D36A7D8DA8`
- `lane_detect.v`: `6E0DF02DE7B5CA383BC7293F2141C28A9AB3B506CC908A907B2ED9509E5CA110`

Four final RTL regressions passed with 6,501,120 compared pixels. The final PDS
build completed and its timing report states `All Constraints Met` under the
existing constraints. Camera input-delay warnings remain unresolved.

This snapshot includes the changed pipeline, detector, top level, tests, model,
logs, build configuration, and timing report. IP dependencies and input fixtures
remain in the main project; this directory is not a standalone build checkout.

The original version 4 binary remains untouched and is the comparison baseline.
Version 6 has not been programmed or visually validated on the board by the agent.
Its tests establish RTL stream integrity, not camera/DDR/HDMI hardware correctness
or semantic lane accuracy. The user's already-overlaid monitor photo is diagnostic
evidence, not raw RGB input or a ground-truth accuracy annotation.
