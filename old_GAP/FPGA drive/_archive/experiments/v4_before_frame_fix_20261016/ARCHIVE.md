# Version 4 Before The Frame Fix

Snapshot taken on 2026-10-16 before modifying `img_proc.v` for version 6.
The original binary remains `bitstreams/4_road_markings_filtered_cmos1.sbit`
in the main project. Its SHA256 is:

`ED53C960F810528BEC0A641565A00B1A6FED9C2E6FCFAEDAC1AF64F32D613467`

This preserves the image-processing source, detector, top level, model, old
testbench, original failing frame probe, documentation, and build configuration.
It is not a standalone copy of the IP dependencies or all generated outputs.
The frame probe was run with 12 active rows to expose repeated DE/pixels in
blanking; its legacy log is retained here. Version 6 adds frame-aware row
handling and full-height tests without changing the version 4 detector rules.
