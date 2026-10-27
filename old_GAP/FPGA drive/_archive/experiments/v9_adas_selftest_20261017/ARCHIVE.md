# Version 9 Synthetic Self-Test Archive

Artifact: `bitstreams/9_adas_selftest_no_camera.sbit`, 2,101,696 bytes.
SHA256: `912BFB169F0A6205C5C79F494BD04A4B67E110567F2B762B61998D48E7D30843`.

The archived top has `SELF_TEST=1`, MODE=4, DIAG_CYCLE=0, ZEBRA_ENABLE=1 and
ADAS_ENABLE=1. It selects an internal six-phase pattern clocked by the existing
25 MHz PLL output, independent of camera pixel clock/configuration. TEST is
permanently drawn. DDR, HDMI, PLL and board power still need to work. All other
direct RTL is identical to version 8. This is not live camera recognition.

Final build: `build_adas_selftest_v9_final.txt`, completed at tool-local
2026-10-17 00:59:41. The archived report is dated 00:59:15 and states
`All Constraints Met`; processing-clock setup slack is 15.866 ns on the
automatically inferred PLL CLKOUT2 clock. The historical declared clk_25M
constraint points at unused CLKOUT3; the actual CLKOUT2 path is timed by the
inferred 40 ns clock. Existing unconstrained-interface warnings remain.

This is a partial reproducibility snapshot, not a standalone vendor project.
It contains direct RTL sources, configuration, named bitstream, final build
log, timing/map reports, host software, benches/generators, original fixtures,
final test logs and selected generated outputs. Vendor IP directories remain
in the main project; their project-relative hashes are in `IP_SHA256SUMS.csv`.
Large full-frame HEX files, simulator work directories and C executables are
omitted and can be regenerated using `tests/ADAS.md` in a suitable project copy.

`SHA256SUMS.csv` covers archive files other than itself. No board was programmed.
After preserving this snapshot, the main top was restored to SELF_TEST=0 for
camera mode. Thus current generic PDS output directories belong to version 9,
while the working source default is version 8. Program only explicitly named
files and use their corresponding archived report, not a generic filename.

The shared acceptance document describes both versions. Synthetic scenes and
simulated software inputs are functional tests, not physical MCU communication,
real obstacle/pedestrian recognition, speed measurement, ranging or driving
safety validation. Burn this version first to isolate the display/processing
path, then version 8 for camera checks.
