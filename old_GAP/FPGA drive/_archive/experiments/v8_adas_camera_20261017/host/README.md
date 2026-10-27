# ADAS Result Protocol And Receiver

These files implement a **transport-neutral** result protocol. There is no
connected MCU, assigned communication pin, FPGA ethernet MAC, SPI peripheral,
UART bridge or video-transfer path in this deliverable. A successful decode is
not proof of physical FPGA/MCU communication, nor of the competition's high-speed
communication requirement. Confirm the actual MCU, interface voltage, connector,
pinout and bandwidth before integration. Do not repurpose camera, JTAG or LED
pins merely because a byte encoder is available.

## Payload And Framing

`adas_packet.v` takes a 256-bit snapshot on `sample_valid && sample_ready` and
produces `data/valid/ready` bytes on the same clock. Paused output holds its byte
stable. An input sample offered while busy is dropped and increments a saturating
counter. A reset aborts the current packet. The encoder has no CDC or physical
serial interface. Connect through a proper FIFO/handshake when clocks differ.

The main video top does not instantiate a physical transport, so its unused
packet-related logic is not present on the board. `img_proc.adas_valid` and
`img_proc.adas_snapshot` expose the results for future integration. Simulations
connect those ports to the encoder and check the resulting bytes.

Each packet is 38 bytes:

| Byte(s) | Meaning |
| --- | --- |
| 0..1 | Magic A5 5A |
| 2 | Protocol version 01 |
| 3 | Payload length 20 hexadecimal (32 bytes) |
| 4..35 | Payload below, least-significant byte of snapshot first |
| 36..37 | CRC low byte, high byte |

CRC: polynomial 0x1021, initial value 0xFFFF, MSB-first, no reflection, final XOR
zero; covers bytes 2..35, excluding magic and CRC. `123456789` gives 0x29B1.
The Python oracle uses `binascii.crc_hqx`, independent of the RTL CRC loop.

All multi-byte payload values are little-endian:

| Payload Byte(s) | Field |
| --- | --- |
| 0 | Flags |
| 1 | Left type bits 1:0, right type bits 3:2, offset warning bits 5:4; bits 7:6 zero |
| 2..3 | Wrapping 16-bit frame ID |
| 4..5 | Signed 16-bit image-center minus lane-center offset, pixels |
| 6..7 | Lane width at the shared near band, pixels |
| 8..15 | Left x0, y0, x1, y1, each uint16 |
| 16..23 | Right x0, y0, x1, y1, each uint16 |
| 24..27 | Left and right support-row counts, uint16 |
| 28..31 | Crosswalk candidate y0 and y1, uint16 |

Flag bits: 0 left candidate valid; 1 right candidate valid; 2 pair valid;
3 crosswalk candidate; 4 crosswalk confirmed; 5 malformed frame; 6 experimental
(always one); 7 reserved zero. Line types: 0 unknown, 1 continuous/solid candidate,
2 dashed candidate. Warning types: 0 none, 1 image-center proxy left of lane
center, 2 image-center proxy right of lane center. These are not calibrated
vehicle states or traffic-law decisions.

Geometry fields are zero when their side is invalid. Width, offset and warning
are zero when the pair is invalid. Consumers MUST inspect validity flags:
zero offset alone does not mean centered. A malformed frame contains no valid
geometry. Crosswalk confirmation implies a candidate. Every accepted packet
is checked for these invariants by both receiver implementations.

## Python

Python 3.10+; no third-party packages. Replay a binary capture as JSON lines:

```powershell
python host/adas_protocol.py tests/output/adas/rtl_pipeline_packets.bin
python tests/test_adas_protocol.py --vectors -v
```

The CLI labels file/stdin data `CAPTURE_REPLAY`, not live hardware. For future
live integration, feed byte chunks to `Decoder.feed()`, pass accepted observations
to `Freshness.accept(observation, time.monotonic())`, and query `current()` on
every control/display update. Its default freshness timeout is 0.5 seconds.
Do not refresh a watchdog merely because duplicate bytes arrive. Out-of-order
and duplicate sequence IDs are rejected while fresh; after timeout, a restarted
FPGA sequence can be acquired again. Use a finite, monotonic local clock.

## Portable C

`adas_protocol.h/.c` use C99, fixed-size storage, no OS and no dynamic allocation.
Feed one received byte at a time into `adas_decoder_feed()`. Only its return value
1 grants a new valid `adas_observation`; partial/corrupted bytes never update it.
Call `adas_accept_frame()` and `adas_is_fresh()` using a monotonic millisecond
tick, a nonzero timeout below 2^31 ms, and an initially zeroed freshness struct.
Both sequence-ID and uint32 millisecond rollover are handled.

The receiver was compiled and executed on the PC, not cross-compiled or flashed
to an unknown MCU. Interrupt/DMA integration, cache maintenance, pin setup and
target toolchain validation remain hardware-specific work.

```powershell
gcc -std=c99 -Wall -Wextra -Werror host/adas_protocol.c tests/adas_protocol_c_test.c -o tests/output/adas/adas_protocol_c_test.exe
tests/output/adas/adas_protocol_c_test.exe tests/output/adas/rtl_pipeline_packets.bin
```

## Software-Only Scenarios

```powershell
python host/adas_demo.py --demo
```

This explicitly uses invented speed/distance/turn inputs to exercise a toy
overspeed reminder, proximity/TTC reminder and turn-indicator state. Its output
is labelled `SOFTWARE_SIMULATION_ONLY`, `lane_change_safety=NOT_ASSESSED` and
`actuator_output=false`. The two-second threshold is a demonstration parameter,
not a validated collision model. No real speed measurement, ranging, pedestrian
recognition, obstacle detector, turn-signal pin or vehicle control is implemented.
