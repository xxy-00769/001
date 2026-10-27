# S5a: Isolated UDP Diagnostic Application

This is an application layer, not a MAC, IPv4/UDP implementation, RGMII
interface or a downloadable board release. Existing V1 design inputs and
the main PDS/flow/FDC remain unchanged. No new files are added to that build.

## Entry Points

From the repository root:

```powershell
.\tools\s5_diag\run.ps1
.\tools\s5_diag\synthesize.ps1 -SimulationResult '<new PASS directory>\result.json'
.\tools\s5_diag\package.ps1
.\tools\s5_diag\inspect_vendor.ps1
```

All commands create independent, unique output directories below workspace
`tmp`. The synthesis entry copies just this application into a new directory,
checks matching simulation input hashes, and runs PDS compile/synthesize.
It intentionally does not schedule device mapping, PNR, final STA, bitstream
generation or programming. Its unconstrained synthesis estimates are not
RGMII or production-clock timing signoff.

`run.ps1` uses the installed Python and ModelSim. Overrides are available for
`-Python`, `-ModelSim`, and `-OutputParent`. Host tests use real OS UDP
sockets on `127.0.0.1/127.0.0.2`, never a physical adapter. There is no package
installation and no changes to adapter settings or firewall rules.

## Application Interface

`mes50hp_diag.v` uses one clock domain. `tick_ms` must be a single-cycle pulse
per real millisecond in this domain. `link_up` must be safely synchronized
and backed by actual PHY link/speed evidence before integration.
`rst_n` is sampled synchronously. Do not directly connect asynchronous PHY
status or another clock domain. This clock/tick source must keep running when
the RX clock stops; otherwise session/LED expiry cannot be guaranteed.

- Input: one **complete and validated** 32-byte UDP payload per
  `rx_valid && rx_ready` edge.
- Output: one 32-byte payload per `tx_valid && tx_ready` edge, stable while
  stalled. Reset/link loss cancels queued output.
- Byte 0 occupies `[255:248]`; no video RGB565/network framing is defined.
- `led_requested` is a logical request, not an electrically mapped output.
  The adapter/top must map the correct LED and its polarity.
- At session expiry, incoming handshake pauses for the expiry edge.
  Existing queued output remains a snapshot; it does not keep a lease alive.
- Counters are uint32 and wrap naturally. Reset clears them; link loss
  clears session/lease but preserves counters.

The future adapter must validate complete length, configured peer/source and
destination addresses/ports, IPv4 header/checksum/fragmentation policy, UDP
length/checksum policy, Ethernet FCS and PHY RX error before commit. Partial
packets, truncation, CDC overflow and RX timeout must never be presented as a
validated command. A packet buffer that cannot accept input must discard it
as a whole and count the discard, not overwrite a pending command.

The vendor `udp_rec_data_valid` stream is **not** this interface: it exposes
bytes before final MAC FCS decision and is not a packet acceptance strobe.
Do not wire it to LED execution. `inspect_vendor.ps1` preserves selected
read-only text evidence without importing the old stack into the main build.

## Protocol Version 1

All integer fields are unsigned, big endian. Fixed length: 32 bytes.

| Byte | Length | Meaning |
| --- | --- | --- |
| 0 | 4 | ASCII `M5D1` |
| 4 | 1 | version 1 |
| 5 | 1 | type |
| 6 | 2 | reserved, zero |
| 8 | 4 | nonzero client session ID |
| 12 | 4 | sequence |
| 16 | 4 | value |
| 20 | 4 | LED lease milliseconds |
| 24 | 4 | detail |
| 28 | 4 | application CRC32 of bytes 0..27 |

CRC is reflected IEEE CRC32 (`0xEDB88320`, initial/final XOR `0xFFFFFFFF`),
equivalent to Python `zlib.crc32`. This is not Ethernet FCS or authentication.

| Type | Command / Response |
| --- | --- |
| `0x01` HELLO | Establish a session; value/lease/detail zero |
| `0x02` PING | Request status; value/lease/detail zero |
| `0x03` LED | value 0/1, lease 1..5000ms, detail zero |
| `0x80` STATUS | value = effective LED request, lease = remaining ms, detail = accepted commands |
| `0x81` ACK | value/lease = resulting request, detail = code below |

ACK codes: 0 accepted, 1 duplicate sequence, 2 unknown/expired session,
3 stale sequence, 4 other session busy.

Only a HELLO can open a session; active sessions cannot be preempted.
Valid new HELLO/PING/LED refresh a 5000ms session timeout. Duplicate/stale,
malformed, unknown-session or busy-session commands do not refresh the
session or LED lease and do not change LED state. Same sequence with changed
content is still a duplicate, never a new command. Sequence wrap is not
supported: expire and establish a fresh session before uint32 exhaustion.
Malformed commands are silently discarded and counted, with no reply.

The protocol only diagnoses transport and LED execution. It has no image
header, camera identity, driver-rule meaning, security authentication or
safety-control semantics. Use an isolated test link. No throughput, drop-rate
or video-FPS claims follow from these tests.

## Coverage

Host tests: encoding/known CRC, every single-bit corruption, invalid lengths
and semantic fields, duplicate lease behavior, session expiry/contention,
real UDP CLI subprocess exchange and request timeout.

RTL: independent Python `struct/zlib` golden packets, status/ACK bytes,
lease boundary, 256 single-bit corruptions, invalid fields, duplicate/stale
and foreign sessions, output backpressure, simultaneous dequeue/enqueue,
link loss, reset/restart, session timeout and sequence wrap rejection.
The 50ms session parameter in the RTL bench accelerates expiry; it is not a
measured board timeout. Production defaults remain 5000ms.

Not tested: actual MAC/ARP/UDP/FCS chain, PHY, physical link speed,
RGMII IO timing/CDC, full integration, real board LED mapping or image transfer.
