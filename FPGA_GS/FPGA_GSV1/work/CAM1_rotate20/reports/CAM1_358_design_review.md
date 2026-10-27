# CAM1 3.5.8: design and clock budget

## Accepted baseline and scope

3.5.7 rear image accepted by user; final4740=20, RGB5654300=61, rising-edge
input registers, CAM1 byte gearbox and geometry watchdog rules unchanged. Frozen
rollback/hash: `baseline_acceptance.md`. No3.4 WIP. No network speed changes.

## Sensor sources and rotation

Archived OmniVision OV3660 preliminary datasheet v1.3 (2011-05-13):
PDF43 table3-1 and PDF111 table7-8:3820[2:1]=11 vertical flip,
3821[2:1]=11 horizontal mirror. Preserve nonbin3820bit6 and all other current
profile bits. Thus40/00 ->46/06. Table3-1 footnoteb requires4514=BB for full
mirror+flip. Archived Espressif `set_image_options()` independently specifies
this exact46/06/BB profile;4520=B0 and3814/15=11 retained.

Top parameter `CAM1_ROTATE_180=1`;0 selects40/00/88. Sensor-local transformation
precedes DDR, so single/quad direction agrees and downstream Chinese OSD stays
upright. Mandatory SCCB readbacks cover all three registers; wrong companion
or orientation value prevents ready. No global output or other source rotation.

## XCLK and clocks: facts versus assumptions

Board DOUBLE-DVP-OV5640-1113 schematic identifies an onboard24MHz oscillator as
camera XCLK source. FPGA `clk_25M` clocks the SCCB configuration for CAM0; it
does NOT drive CAM1 XCLK. There is no FPGA XCLK input/output measurement pin in
this design. The physical oscillator frequency has not been probed. Therefore
24MHz is the schematic nominal, not a measured result.

Keep all previously working sensor PLL registers unchanged:
303A=00,303B=18,303C=12,303D=20,3824=01,460C=22.
Per datasheet PDF39-41 fig2-7/table2-9, at nominal24MHz:
REFIN12MHz, VCO288MHz, PLLCLK144MHz, SYSCLK36MHz,
manual byte PCLK72MHz; FPGA pixel clock=PCLK/2=36MHz.
REFIN within4..13.5MHz; VCO within150..500MHz; PLLCLK below216MHz.

Actual byte PCLK is now passively measured against the existing50MHz reference:
8bit prescaler -> two-stage single-bit CDC ->1second count, resolution256Hz.
This neither generates nor gates a clock. On-board UART reports measured PCLK,
and the decoder infers XCLK=PCLK/3 using the verified PLL settings. This is an
indirect measurement, not a probe of the oscillator. Actual result pending the
candidate download. Previous G1 good/bad source-count cadence was approximately
12.5Hz, consistent with the nominal calculation, but not a precision clock test.

## Native720 timing choice

Old geometry read1920x1080, then sensor ISP downscaled to1280x720.
2172x1322 at36MHz =>12.537508fps. Increasing just the existing PLL cannot
reliably reach20fps while retaining that full readout (datasheet1080p maximum20).

Chosen one candidate: native centered1280x720, no binning, no upscaling, scaler
disabled by clearing only5001bit5 (A3->83). Datasheet PDF44-46 documents arbitrary
sensor windowing; archived `set_res_raw()` programs this geometry independently
of output scaling. Physical window X384..1695,Y408..1139; offsets16/6; output
1280x720. **Field of view is narrower than3.5.7**. This is a native-resolution
readout choice for speed, not black cropping to hide an error. No abnormal row
or pixel is excluded from the720-line geometry verdict.

Datasheet PDF97-98 table5-3 native720 example: HTS1604, frame approximately749
rows,720 active; values depend on mode. Chosen HTS1800,VTS800 exceed that example
and accommodate the1312x732 physical window. These are not asserted universal
minimums. Active1280 pixels require2560 byte clocks=35.556us; one line3600 byte
clocks=50us; remaining14.444us horizontal blanking.720 lines=36ms plus4ms
vertical blanking =>40ms/frame, **nominal25fps**. Sensor720p advertised maximum45.
No sensor or FPGA PLL change, no sampling edge change, no constraint relaxation.

## Exposure and darkness

Datasheet PDF50-54,112-114:3503[1:0]=0 keeps AEC/AGC;3A00bit2=0 disallows night
frame extension;3A05bit6=0 disallows night frame insertion. Preserve other bits
in3A00=3A and3A05=30. Both50/60Hz maximum exposure ceilings are796 rows=39.8ms,
below VTS800; four-row reserve.50Hz band step200rows=10ms,max bands3;60Hz
166rows~8.3ms,max bands4. Keep existing gain ceiling3A18/19=00F8 (~15.5x),
AE targets, gamma and ISP color processing. Read back ceilings, bands and night
controls before ready.

Daylight: AEC can choose a short exposure, less motion blur. Dark scene: AEC
raises gain, with more noise and possibly a darker image; exposure cannot grow
without bound to brighten the picture. At flicker-quantized long exposure,
30ms(50Hz)/33.2ms(60Hz) is possible; even39.8ms does not exceed40ms frame period.
Brightness/low-light cadence must be observed on board; no guaranteed25fps claim
is made from register calculations alone.

## Capture/publication bottleneck and smallest scoped fix

The unchanged raw geometry verdict arrives at the next VS. Two-cycle capture
pipe lets the old owner close the prior frame immediately before its next SOF.
However DDR end synchronization +32 settle clocks +32 reset clocks take at
least640ns at100MHz, exceeding that one/two pixel-cycle lead. SOF-only grant
acceptance therefore misses that next frame. Two slots can also be pinned by
display+pending until the next60Hz boundary, up to16.67ms. Merely setting the
sensor25fps would not guarantee20 published new frames.

CAM1 uses the existing three-slot owner with a default-off `BLANKING_GRANT`
parameter. CAM0 keeps its exact default behavior and independent network pin.
For CAM1 only, latch the opening tags at VS rising, accept a returned writer
grant during the remaining VS-high blank interval, and pulse writer VS once.
Never begin halfway through an active line/frame. The two-line VS interval is
100us, comfortably above the roughly microsecond turnover; the full production
test checks actual handshakes rather than assuming this budget is sufficient.
Verdict still closes only at NEXT VS, and publication still requires all720
DDR line completions and zero raw/byte/owner errors. No early publication.

CAM1 third slot0x2800000 words is disjoint from every existing slot (front
third0x2000000,right third0x2400000). Each image uses46080032bit words.
The table/audit checks all11 physical slot ranges; existing slots are unchanged.
Reader bank stays pinned through any outstanding native read, including hidden
source transitions. An ungranted frame is dropped whole. Triple buffering and
late-blanking acceptance are enabled only onCAM1.

Write average46.08MB/s at25fps, active byte ingress72MB/s. Native line80 DDR
beats at100MHz takes0.8us of payload versus50us between line events; arbitration
and gaps consume some of that margin. The production test adds legal DDR gaps,
checks every valid frame's write pixel and reads both native and960x540 modes.
This local budget is not proof of four sources at20fps; those remain later work.

## Measurement definitions and remaining board work

COM23 original1152008N1 and N2 envelope remain; C1R8 words12..19 replace reserved
camera words. CAM1-only optional byte-error bit5 is included in its source
verdict/counters; a geometrically complete frame with odd bytes/FIFO overflow
is not counted as a good capture. The option defaults off on other sources.
W13 pixels;W14 flags/errors/rows;W15 bad16/good16;W16 capture
frame-start ms;W17 published16/displayed16;W18 reference ms;W19 measured PCLKHz.
Counts are atomic per UART line. Source fps uses first/last source timestamps;
publication/display use the same UART endpoints and reference time. Geometry
reports lag capture by one frame; the two time windows are reported explicitly.

Displayed counter requires all720 single or540 quad rows requested, selected,
no line underflow, a distinct source identity, and captures that ID before row1.
It also excludes frames hidden by the existing final health/presentation guard.
It does not count HDMI60Hz repeats, hidden source activity, or use frame-ID
differences as frame counts. It observes source images delivered to the output
pipeline, not physical monitor photons. No counter changes ownership or pixels.

Nominal PCLK72MHz remains below unchanged constrained84.034MHz; /2 remains
constrained42.017MHz. Final full PNR/STA must pass all retained constraints.
External camera pad skew is not physically characterized; network2 inherited
nominal PHY model is not newly claimed as full PVT/PCB signoff.

After build: user downloads once, four-corner marks verify180deg, short COM23
window checks921600/720/errors0 and all three rates. Then one60second measurement
with rear visible throughout. Do not substitute HDMI refresh or front uploadfps.
