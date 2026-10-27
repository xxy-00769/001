# Version 5 Experiment: Not The Active Baseline

Archived on 2026-10-16 before restoring the version 4 algorithm.
The user reported excessive green overlays and a blurry board image.
The cause has not been diagnosed; passing unit tests did not validate camera
appearance. Do not treat this experiment as the recommended build.

The retained binary is in the project's main `bitstreams` directory:

- `5_road_roi23_precision_cmos1.sbit`
- SHA256: `7F997AF1DB0F9D4CAB46F445758FA684FC63AF99AB97C3A2DD3F4BA8AF2139E0`

This archive preserves the changed RTL, reference model, testbench, test outputs,
simulation logs, documentation, build configuration, build log, and timing report.
Unchanged dependencies and fixture inputs remain in the main project. This is
an experiment snapshot, not a standalone build tree. Archived documentation
describes version 5 as it stood before rejection; it is not current guidance.

The active baseline binary is `4_road_markings_filtered_cmos1.sbit`:

- SHA256: `ED53C960F810528BEC0A641565A00B1A6FED9C2E6FCFAEDAC1AF64F32D613467`

The main `source/rtl/lane_detect.v`, model, and testbench have been restored to
version 4 behavior. Neither named binary was rebuilt or overwritten.
The main PDS generated outputs still belong to version 5 until a new full build.
