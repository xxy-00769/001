# Stage 1: Configuration Timing

Date: 2026-10-17. Scope: repair the registered configuration path that failed
the previous experiment's 10 ns synthesis clock target, with no arithmetic or
writeback changes. Stages 2 (DDR), 3 (complete model) and 4 (board integration)
are not started in this round. No new bitstream or board programming.

**Status: Stage 1 acceptance passed.** Both simulation suites and the final
source/evidence/timing verifier completed successfully; see `verification.json`.

## Acceptance

The stage passes only when all of these checks pass:

1. The unchanged 10 ns synthesis constraints pass for the core + whole-layer DMA
   + multiplexed resource probe, without false-path or multicycle exceptions.
2. All three prior tile-loading strategies produce byte-identical output,
   post-start cycle and transfer reports.
3. Whole-layer writes and recovery outputs match the previously verified reports;
   address/mask/guard, backpressure, final acknowledgement and error tests pass.
4. Configuration-phase resets, immutable descriptor capture and exclusion of
   speculative configuration/load/start traffic pass.
5. Previous experiment evidence and 229 protected main files remain unchanged.

`verification.json` is generated only after those checks pass. This acceptance
is for the prior synthesis violation, not routed system timing or road accuracy.

## Change

This experiment copies the previous core into `source/conv_cached.v`. Previous
experiment files are not edited. The whole-layer DMA, layer probe and tile probe
are unchanged copies; the RAM, MAC, quantizer and runtime FSM sections remain
byte-identical to the original core.

The old core validated a live descriptor using chained multiplications and
capacity comparisons in the same clock that accepted it. The new sequence is:

```text
CONFIG handshake: capture all fields, basic checks and cache-identity check
CFG_PLANE:         compute input/weight planes, groups and required dimensions
CFG_SIZE:          compute complete byte/word sizes; compare geometry
CFG_CHECK:         validate captured checks and storage limits
CFG_APPLY:         initialize the original operational state and enter LOAD
```

A valid descriptor adds four clocks before loading is enabled. Arithmetic after
`start_valid && start_ready`, indexed output ordering, masks and cache identity
rules are unchanged. The parent DMA already waits for `vec_ready`, so it needs
no modification. Added setup clocks can be hidden by an initial memory read;
they are not assumed to be free in every tile or memory-latency pattern.

The extra geometry registers retain enough bits for *all encoded inputs*, not
only valid channels/shapes: unsigned input bytes use 17 bits; weight bytes use
18 bits; the pre-validation weight plane uses 11 bits. Invalid descriptors must
not wrap into an apparently valid storage size.

## Handshake and Failure Contract

- A descriptor is captured once, only on `cfg_valid && cfg_ready`. Live ports may
  change immediately after that edge; later validation never rereads them.
- `busy` is asserted during configuration processing. Configuration, byte/vector
  loads and start are not ready until validation/application has finished.
- A fresh accepted descriptor immediately invalidates the old cache. Its new ID
  is applied only after validation succeeds.
- A reuse request compares against the old valid cache and old operational
  channel/kernel/depthwise fields at acceptance. The captured result is used
  later; changing live fields cannot turn a mismatch into a match.
- Invalid configuration now raises a latched fault three clocks after acceptance,
  instead of in the acceptance clock. No RAM write or start occurs before then.
- A valid reuse keeps its cached weights/coefficient bytes and still reloads
  every input tile. Reset clears all pending checks and cache metadata, while
  RAM remains unreset and cannot execute until a complete valid load.
- Invalid configuration faults still require reset. Previous successful output
  IDs and partial-memory-write handling follow the unchanged layer DMA contract.

The interface therefore no longer promises that `load_ready`/`vec_ready` is high
on the cycle immediately following a configuration handshake. Callers must wait
for the actual ready signal; the adapted testbench checks this explicitly.

## Reproduce

From this experiment directory in PowerShell:

```powershell
./tests/run.ps1
./build.ps1
../../.venv-road-model/Scripts/python.exe -X utf8 tests/verify.py
```

To run one suite: `./tests/run.ps1 -Suite tile` or `-Suite layer`.
`-SkipPrepare` reuses existing pinned vectors. Tools are Vivado 2018.3 and
PDS 2022.2-SP6.1. Each suite runs in a separate directory and hashes its inputs.
Generated vectors, simulator databases and reports are ignored by Git.

The preparation script verifies prior source/evidence manifests before copying
vectors. Verification compares complete saved report hashes against those
already independently checked at previous stages, not just summary counts.

## Regression Coverage

- 9,855 tile jobs, 1,874,628 exact accumulator/code outputs, three loading policies,
  output stalls, weight reuse and cycle-equivalent direct/probe execution.
- 26 invalid descriptors, including maximal encoded fields and storage overflow.
- Four resets interrupt each pending-configuration phase before LOAD.
- Live configuration fields and load/start commands are corrupted after a valid
  acceptance; the captured geometry/identity must survive without accepting data.
- 29 whole-layer jobs, 518,967 output bytes and a separate recovery job.
- 124,374 memory transactions, 74,027 final memory words including guards/tails,
  18 injected faults and two pending read/write resets.
- The same three model-derived feature layers run without host intermediate
  reloads. No new classifier, residual connection or semantic road test is added.

## Synthesis Result

The 10 ns synthesis target passes: estimated period **9.499 ns**, slack
**+0.501 ns**, versus the prior 13.133 ns and -3.133 ns. The reported worst path
is now in DMA address generation, not the former configuration-validation chain.

Core + DMA + test probe map to 5,230 LUT, 4,991 FF, 48 DRM18K, 37.5 APM and
172 IO. Versus the previous combined experiment: +325 LUT, +102 FF, with unchanged
DRM/APM counts. This is not the full video system's resource utilization.

No placement/routing or external IO timing closure has been performed. The probe
is not a production pinout. This result does not establish measured board
frequency, real-time inference, DDR connectivity or improved road recognition.

## Stage Boundary

On successful verification, Stage 1 is complete for its stated synthesis and
regression criteria. Stage 2 is a separate deliverable: the real vendor-memory
adapter and video-priority arbitration, with its own tests and acceptance.
Do not burn this experiment as a new camera/road-recognition version. The user's
v4 baseline is unchanged.
