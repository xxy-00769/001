# Native DDR Bridge: Stage 2 Progress

Date: 2026-10-17. Implemented in an isolated experiment. No main RTL,
existing experiment, named bitstream or board configuration was changed.
This is not a complete semantic road model or an accuracy improvement.

**Stage 2 is still in progress.** The native adapter and arbitration tests
are implemented; actual camera/HDMI framebuffer and FIFO integration,
bandwidth/latency acceptance and board testing are still outstanding.
`verification.json` is the machine-readable record, including the actual
vendor-simulation outcome. A failed vendor run must not be counted as a pass.

## Interface And Address Evidence

The board uses `source/rtl/DDR3_50H/DDR3_50H.v`, not standard AXI:

- AW/AR use valid/ready and a 4-bit length (beats minus one).
- Each native beat is 256 bits. The vendor requests write data using
  `axi_wready`; there is no WVALID or B response input/output.
- Read data has no RREADY. Every returned beat must be consumed or buffered.
- `axi_wusero_id/last` and `axi_rid/last` are checked against the active burst.

The local official `test_wr_ctrl_v1_0.v` increments its address by 8 per beat,
and by 128 per sixteen-beat command. `test_rd_ctrl_v1_0.v` uses the same
increment. Its mask checker documents 0 as masked. The existing `wr_ctrl.v`
uses all-one strobes for full writes.

For the x32 memory configuration, one native address unit is four bytes:

```text
abstract 128-bit word address = A
native 256-bit beat address   = (A >> 1) << 3
selected 128-bit half         = A[0]  (0 = low, 1 = high)
native byte strobe           = strb << (16 * A[0])
```

The bridge checks the complete abstract address before narrowing it.
Even arena boundaries prevent a native beat straddling a protected partition.
Default windows, not yet wired into the main design:

| Owner | Address Units | Interval | Byte Range |
| --- | --- | --- | --- |
| Video | Native 32-bit words | `[0, 0x00800000)` | First 32 MiB |
| Accelerator | Abstract 128-bit words | `[0x00200000, 0x00400000)` | 32..64 MiB |

The video reservation follows the existing `fram_buf.v` 22-bit linear
offset and `wr_buf.v` / `rd_buf.v` one-bit ping-pong frame selection.
Changing framebuffer geometry or offsets requires rechecking this map.
Misaligned/overlapping/overflowed accelerator windows reject requests.
Invalid video commands halt the adapter before issuing a native command.

## Arbitration And Completion

`source/road_ddr_bridge.v` accepts one accelerator request at a time and
one native burst at a time across both directions:

- At command boundaries, video wins over queued accelerator work.
  Competing video read/write channels alternate.
- A captured command remains stable while native ready is low. New video
  demand cannot preempt a command already captured or split a data burst.
- Write-data ownership lasts to the checked final beat. Video must have
  its burst data available before submitting the command.
- Video read returns are forwarded without stalling. The accelerator's
  single-beat response is buffered until accepted; it does not block video.
- Tags are echoed exactly. Invalid requests return errors without DDR traffic.
  Zero-mask writes succeed without issuing a command.

**Write-data acceptance is not a write acknowledgement.** After each
accelerator write, the bridge issues an ordinary read to the same beat and
compares all selected bytes. Only a matching readback returns success.
Mismatches can retry sixteen times, yielding to video between attempts;
exhaustion returns an error. Unknown simulation bytes cannot pass verification.
There is no invented AXI B channel or fixed-cycle commit assumption.

Strict video priority has no accelerator starvation bound. Native commands and
returns also have no watchdog. A missing native return can hold ownership until
common reset. Readback retry count is not an elapsed-time timeout. These limits
must be considered before real-time integration.

## Reset And Faults

- `rst_n` is a common fabric/controller reset contract. Resetting only this
  bridge while the controller retains transactions is unsafe.
- `acc_rst_n` can cancel a layer independently. A captured native command
  still issues, and its burst is drained before the accelerator port reopens.
  A held old response is discarded. Video continues.
- A cancelled/failed output tensor must be discarded. Partial writes are not
  rolled back; a cancelled write need not be committed when draining completes.
  Do not immediately reuse abandoned buffers without an external lifetime policy.
- ID/last errors, unsolicited native data or lost initialization latch a fatal
  adapter fault, stop new commands and return an accelerator error when possible.
  Recovery requires common controller/fabric reset.

## Verification

From this directory:

```powershell
./tests/run.ps1
./tests/run_vendor.ps1
./build.ps1
../../.venv-road-model/Scripts/python.exe -X utf8 tests/verify.py
```

The BFM models the actual channel shape, unstallable returns, arbitrary command
stalls and delayed physical write visibility. It does not substitute for the
separate encrypted vendor-controller/PHY test.

Functional test scope:

- 256 byte-mask write patterns; low/high halves, lane masks and neighbor guards.
- Five bad addresses and five unsafe partition configurations rejected.
- Same-edge command/data beats, response backpressure, delayed write visibility,
  failed readback, five cancellation phases and eleven fault scenarios.
- Video bursts of lengths 1..16, all 4-bit IDs, video arbitration during held
  accelerator responses, stable stalled native commands and burst ownership.
- The unchanged stage-1 DMA/core runs 29 full layers through the bridge.
  All 518,967 output bytes and the normalized write report match the pinned
  prior record; 74,027 final memory words, including guards, are checked.
- The 124,374 tagged layer requests expand to 239,078 native commands in the
  BFM test, including readback retries and video. No intermediate feature tensor
  is refilled by the host. This still is not a complete residual block/network.

The vendor test compiles the supplied encrypted controller and PHY, the actual
`DDR3_50H` wrapper, installed Pango primitive models and two supplied x16 DDR3
models. It exercises 256 tagged requests, both halves and masked neighbor
preservation, alongside competing native video bursts. No controller/PHY/PLL
implementation is replaced or patched. Memory debug printing alone is disabled.

The final vendor run passed all 256 requests, 136 video read beats and 272 video
write beats (417 native commands). Its source hashes were checked before/after
the run. There were 92 memory timing warnings during initialization and none
after initialization. These warnings are recorded, not suppressed or rebranded
as physical timing closure.

ModelSim SE-64 10.7's optimized run failed in the supplied PLL primitive with
division-by-zero/NaN and a simulator crash before traffic began. The reproducible
run uses `-novopt`; deprecation diagnostic 12110 alone is suppressed in addition
to the original example's diagnostics. Real simulation errors remain fatal.
Calibration-time memory timing warnings and vendor port-width/unused-port
warnings remain visible; the verifier rejects timing warnings after
`VENDOR_INITIALIZED`. Failure logs are retained in `tests/vendor_run/`.
This simulation cannot certify physical DDR timing or camera/display operation.

The independent combined DMA/core/bridge synthesis shell maps to 6,209 LUT,
5,948 FF, 48 DRM18K and 37.5 APM. The same 10 ns clock target estimates
9.499 ns, +0.501 ns slack. External IO is unconstrained and deliberately
multiplexed for resource probing, not a pinout. No place/route, full video
integration, new `.sbit`, programming or road-accuracy evaluation was performed.

## Remaining Stage 2 Gate

Connect the adapter to the actual framebuffer/FIFOs in an isolated integration
build. Verify sustained camera writes, display reads, FIFO margins, latency,
reset interaction and memory ownership before accepting this stage.
Do not start new recognition features or claim a burn-ready model from these
memory-interface tests.
