# Version 7 Crosswalk-Candidate Snapshot

Captured 2026-10-16 after the successful build ending at 23:32:05 in the local
PDS log. The timing report is dated 23:31:40 and says All Constraints Met under
the current constraints. Existing unconstrained-interface warnings remain.

Artifact: `bitstreams/7_zebra_candidate_v4_cmos1.sbit`, 2,101,696 bytes.
SHA256: `808A9C281B11658D3326008DB745D135AAEDED0FD26BBF0E17D49E955770CD1A`.
This has NOT been programmed or visually validated on the board.

This is a snapshot, not a standalone project: vendor IP, the remaining original
RTL and tool installation are still dependencies in the main project. These
archived sources are not included in its active build. Restore intentionally
into a separate complete project copy rather than overwriting current work.

Included: changed RTL plus unchanged lane RTL, build/project/constraint files,
six passing simulation logs and their sources, reference generators, original
road fixtures, six unannotated board cards, confirmed RTL PNG, bitstream, timing
and mapping reports, and the user-facing acceptance notes. Generated hex vectors
and simulator build directories are omitted; regenerate using the documented
Python commands. The confirmed PNG is simulation output, not a camera capture.

Version 4 remains the primary hardware comparison baseline. Version 6 remains
the frame-integrity-only test. Neither named binary was overwritten. No camera,
DDR or HDMI interface change was made for version 7.

`SHA256SUMS.csv` is a generated manifest of the files in this snapshot, excluding
the manifest itself. See `tests/ZEBRA.md` for scope and recognition limitations.
