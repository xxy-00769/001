# FPGA Completion Track

Updated: 2026-10-19. This is implementation status, not permission to program
hardware or a claim that the entire FPGA feature set is complete.

## Fixed Division

FPGA acquires and organizes pixels, manages buffers, crops/downscales, provides
optional basic image features, transports images/control, reports buttons and
executes LED commands. Orange Pi owns semantic recognition, temporal decisions,
driving rules, panorama, user interface and final HDMI.

Color is primary; auxiliary features must retain source/frame identity and the
crop/scale transform. Legacy lane decisions and HUD remain diagnostic history.
They are not being extended as the product's normal path.

## Completion And Remaining Work

| Work item | Current implementation/evidence | Still required |
| --- | --- | --- |
| Single CMOS1 acquisition, normalized RGB565, DDR, clean HDMI | V1 RTL/full PDS build; user reports smooth clean HDMI | Exact-bitstream board acceptance for each changed release; measured color/geometry/long-run checks |
| DDR return completion and final row | S3a/S3b fixes and directed simulations; unchanged in V2 | Full-controller/physical DDR and adverse-load coverage |
| Raw geometry, frame ID, source ID, time and error counts | V2 source observation; V3 now aligns ID/acquisition time with clean pixels and committed DDR banks, requires matching raw-frame validity; directed/full-raster RTL PASS | Current-release board acceptance and a readable control/status interface |
| Stopped-clock/frame watchdog and pipeline restart | V2 free-running reference watchdog, processing reset and HDMI display guard; actual processing restart/reset RTL test passes | Board fault/restart observation using a safe controllable source; no electrical hot-plug assumption |
| Complete-frame DDR publication and buffer ownership | V3 implemented; 38 directed checks, 6 full 720p frames / 5529600 correct pixels, 2560 fault-output black pixels; final-input RTL and full PDS through bitstream PASS under existing constraints. [Current evidence](../reintegration/10_frame_ownership_v3.md) retains implementation/STA warnings. Two-bank ownership replaces independent VS bank selection | User programming and physical DDR/normal-video acceptance; new-frame-rate observation; full IO/CDC signoff not established |
| Configurable crop and downscale | Not integrated | Frame-boundary configuration, bounds checking, pixel oracle and original-to-output transform metadata; preserve full-color stream |
| Grayscale/simple filter/Sobel/threshold auxiliary stream | V4 KEY8-selectable original/grayscale/median/Sobel/candidate/legacy diagnostic views: key 55 checks; 8 full image frames and 6 native-DDR display frames PASS; full PDS through bitstream PASS. Clean RTL output retained; single DDR display cache follows selected view. [Evidence](../reintegration/11_key8_video_modes.md) | User board acceptance, remotely configurable auxiliary transport and configurable thresholds remain pending |
| Configuration/status, buttons and LED commands | Standalone S5a diagnostic protocol and host tests; not main-top physical communication | Product configuration registers, button debounce/event sequence, command timeout/LED safe state and physical readback |
| Gigabit UDP video/control | Standalone application and fixed-size RX validation only | ETH1 PHY/MAC/ARP/TX/RX/CDC integration, image packetization/reassembly, host receiver and real link acceptance |
| Stereo parallel | Two camera configuration blocks exist; acquisition remains **one selected source** | Independent capture and buffer ownership per camera, source numbering, timestamp/skew measurement and bandwidth tests |
| Camera + HDMI input | HDMI output currently works; no accepted HDMI input capture path | Receive interface and clock/format checks, independent stream/buffers |
| Network fourth input | Not implemented | Validated reassembly, frame timeout/discard, separate storage/input arbitration and recovery |
| Power-cycle startup | Old artifacts/history exist | Bind flash/startup procedure and repeated power-cycle observations to a selected release |

## Delivery Order

The user explicitly moved visible basic-processing comparison ahead of crop/
downscale: V4 implements KEY8 switching now. It does not imply crop/resize,
physical image networking or semantic recognition is complete.

1. V2 single-source monitoring/recovery, preserving V1's clean color.
2. Complete-frame DDR ownership/publication; this is not established by V2.
3. Configurable crop/downscale and transform metadata.
4. Optional basic processing with bypass and source-frame binding.
5. Physical configuration/status/video communication and button/LED round trip.
6. Stereo parallel, camera+HDMI, then network fourth input.
7. Stress, fault recovery and selected-release startup acceptance.

Communication is itself required FPGA functionality. It is not evidence that
all image processing is done, and no image transmission has yet been achieved.
Development can proceed independently where hardware identity does not affect
the operation; missing photos are not a global gate.
