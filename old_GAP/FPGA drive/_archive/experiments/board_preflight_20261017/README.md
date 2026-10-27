# Board Preflight And V4 Baseline Restoration

## Actual Outcome

On 2026-10-17, JTAG detected PGL50H with ID `0x00521899` on cable index 0.
Its initial configuration status was `0x00100c80`, with DONE=0.

The user's previously selected baseline was programmed successfully:

- File: `../../bitstreams/4_road_markings_filtered_cmos1.sbit`
- SHA256: `ed53c960f810528bec0a641565a00b1a6fed9c2e6fcfaedac1af64f32d613467`
- PDS tool: `cdt_cfg_shell.exe`, 2022.2-SP6.1
- JTAG frequency: 1 MHz
- Vendor log: `COMMAND[Program] execute successfully, takes 17.1 secs.`
- Post-program status: `0x001ffca0`, DONE=1 and DONE_I=1
- A separate reconnect/scan/status-read session confirmed the same state.
- CRC, readback-CRC, timeout, overflow, ID-error and over-temperature bits were 0.

Evidence is in `runs/20261017_152942_993/`: `before.log`, `program.log`,
`after.log` and `result.json`. The result timestamp preserves the host's UTC
offset. Binary hashes were checked before and after programming.

This was volatile FPGA configuration, NOT a Flash write. Power cycling may
load whatever was already in Flash; it does not persist this download.
No eFuse, encryption-key, Flash-erase or Flash-program command was executed.
The user's running PDS project and lock were left alone.

## Important Incomplete Work

This restores v4's camera/marking-candidate baseline. It is NOT a new semantic
road detector, and its known indoor false positives remain. No new bitstream
was built. The requested complete independent road-recognition release has
NOT been delivered: only the first-layer arithmetic prototype exists; remaining
network operators, scheduling, DDR integration and end-to-end validation are
still missing. Nothing in this programming result changes that status.

The camera/HDMI picture was not observed remotely. Programming success and
configuration status do not establish picture quality, algorithm accuracy,
frame rate, or suitability for vehicle control.

Full `cfg_verify` readback comparison was not performed: v4's corresponding
archived `.smsk` is unavailable. The current generic build mask belongs to a
different build and must not be substituted. No readback-verify PASS is claimed.

## Scripts

`probe.tcl` only connects, selects 1 MHz, scans, reads ID/status and disconnects.
It never loads, programs or resets a device. Commands were checked against the
locally installed vendor Fabric Configuration User Guide, sections 4.5.1 and
4.5.2. The old root `scan_chain.tcl` uses unavailable command names and does not
actually scan this tool version; it was not used as connection evidence.

`run_v4.ps1` explicitly restores the approved v4 hash using `program_v4.tcl`.
It is a board-changing operation, not a dry run or semantic-model deployment.
It checks the preflight log and artifact hash, runs programming once, then
reconnects and validates status bits. It never substitutes another bitstream
on failure. For this local single-board setup, run intentionally from the
experiment directory:

```powershell
./run_v4.ps1
```

The vendor tool can return process exit code 0 after errors. The wrapper also
requires positive command-completion markers, PGL50H/ID evidence, no error
diagnostics and healthy post-program status. Each run has a new evidence folder.
It times out after 180 seconds per tool invocation and does not auto-retry a
programming failure; inspect board state before any retry.

Earlier attempts stopped before programming: an omitted required connection
argument, and PDS's handling of Tcl source paths. The working wrapper explicitly
sets the native process working directory and passes a simple script filename.
These failed logs are retained and are not evidence of a successful download.
