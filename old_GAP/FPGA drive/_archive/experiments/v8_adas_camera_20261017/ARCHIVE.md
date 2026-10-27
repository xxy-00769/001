# Version 8 Camera Experiment Archive

Artifact: `bitstreams/8_adas_lane_status_cmos1.sbit`, 2,101,696 bytes.
SHA256: `4714B2F26E2E71DE27627A709C23DAF98818421613F850F97BBE73C8A8772573`.

The archived top has `SELF_TEST=0`, CMOS1, MODE=4, DIAG_CYCLE=0,
ZEBRA_ENABLE=1 and ADAS_ENABLE=1. It preserves the version 4 lane detector,
version 6 frame repair and version 7 crosswalk candidate. New geometry/status
and thin overlays are experimental. The byte encoder is not connected to a
physical board interface. No automatic programming or board validation occurred.

Final build: `build_adas_camera_v8_final.txt`, completed at tool-local
2026-10-17 00:47:10. The archived report is dated 00:46:44 and states
`All Constraints Met`; cmos1_pclk_16bit setup slack is 2.333 ns. Existing
unconstrained-interface warnings remain. `build_adas_v8_first.txt` in the main
project was an earlier exploratory build and is NOT evidence for this artifact.

This is a partial reproducibility snapshot, not a standalone vendor project.
It contains direct RTL sources, configuration, named bitstream, final build
log, timing/map reports, host software, benches/generators, original fixtures,
final test logs and selected generated outputs. Vendor IP directories remain
in the main project; their project-relative hashes are in `IP_SHA256SUMS.csv`.
Large full-frame HEX files, simulator work directories and C executables are
omitted and can be regenerated using `tests/ADAS.md` in a suitable project copy.

`SHA256SUMS.csv` covers archive files other than itself. Never restore by
overwriting an active project without reviewing its newer changes. Keep the
named version 4/6/7 binaries intact. The final main working top is restored to
this version's default; generic PDS output directories were subsequently
overwritten by version 9, whose source/report evidence is archived separately.

The shared acceptance document also describes version 9. The archive's own top,
bitstream, log and report identify version 8. Tests only establish the stated
simulation/software contracts, not real recognition accuracy, physical
communication, pedestrian detection, calibrated speed/range or driving safety.
