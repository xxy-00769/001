# Sensor Color-Bar Diagnostic, Version 10

## Built Artifact

Build completed with PDS 2022.2-SP6.1. Published file:
`../../bitstreams/10_sensor_colorbar_cmos1.sbit`, 2,101,696 bytes.

```text
SHA256 b7c53ac342437d4da2f8030f12922f429fe02fc4bacc4edcfb166f3cd79257a3
```

The final `report_timing/hdmi_ddr_ov5640_top.rtr` says `All Constraints Met`.
Its fast-corner DDR hold slack is +0.135 ns. The router logs failure to reach
the extra 0.200 ns hold-repair target; this must not be confused with a negative
final hold slack. The existing unconstrained camera inputs, configuration-clock
endpoints and other interface warnings remain. This is not complete timing
sign-off. Configuration simulation passed; no physical board test was performed
by the agent. Source checks: `tests/source_verification.json`.

## Purpose

Subsequent field feedback: the user reports normal white in the sensor bars.
The typed phrase about corruption/shaking is provisionally read as "none";
no bar photograph or raw capture was provided with that response. The user
suggests phone capture as a possible cause of earlier tint. This is not proof
that real-scene AWB/exposure/optics are correct. No color-setting patch is made.
The generated source-verification JSON retains `hardware_tested: false` because
it records tool-side verification at publication, not this later user report.

The user reports that the live camera white paper looks pink, while direct PC
HDMI and version 9 FPGA-generated white HUD text do not. This makes the camera
input path a higher-priority suspect, but does not prove a damaged sensor or
fully certify the output path at every color/intensity/clock condition.

This build requests static standard color bars from the OV5640 itself. Unlike
version 9, the pattern must travel over the camera DVP connection, byte packing,
DDR frame buffer and HDMI. It does not measure optical focus and does not bypass
every sensor ISP function. It is neither color correction nor road recognition.

## Change Boundary

- Snapshot the original `D:/BaiduNetdiskDownload/HDMI_DDR3_OV5640_test/source/rtl`
  17 Verilog files. Sixteen are byte-identical copies.
- In the snapshot `reg_config.v` only, preserve writes 0..356 and append write
  357: `0x503D = 0x80`. Change the write-count limit from 357 to 358.
- The copied register file was decoded from GBK into UTF-8 to preserve existing
  comments when applying the edit. Main source bytes were not changed.
- Use the original CMOS1 raw-video top. No `img_proc`, lane detector, overlay,
  color gain adjustment or FPGA pattern source participates in this build.
- Retain the current main-project constraints and shared vendor IP by relative
  path. This is a diagnostic snapshot depending on the main project's IP,
  not a portable standalone project.
- Build outputs remain in this experiment. Main generic outputs and all older
  named bitstreams are not replaced. No automatic board programming.

## Register Evidence

The saved Espressif OV5640 header describes `PRE_ISP_TEST_SETTING_1 = 0x503D`:
bit 7 enables the test; bit 6 enables rolling; bits 3:2 select bar style;
bits 1:0 select the pattern. `0x80` requests enabled, static standard color bars.
The driver `set_colorbar()` uses this register; its rolling-mode setting differs
from our explicitly static value. These are primary driver references, not a
claim that this board uses Espressif software.

Source locations retrieved during this diagnostic (upstream `master`, with the
exact saved content identified by hashes because revision API was rate-limited):

```text
https://raw.githubusercontent.com/espressif/esp32-camera/master/sensors/private_include/ov5640_regs.h
https://raw.githubusercontent.com/espressif/esp32-camera/master/sensors/ov5640.c
```

Saved SHA256 values:

```text
ov5640_regs.h  c0c8a2b608300ff0d513b94a60b1587e408312b0051f770d22fb18569ae0f230
ov5640.c       df60065649695167db86787d7904b584ec82f73f8c0a686743f93f8d2d5b35ac
```

The original initialization table has unequal values at `0x5583` / `0x5584`.
They were deliberately NOT changed: that observation alone is not proof of
the white-paper tint's cause. Likewise no guessed RGB gain or white-balance
setting was applied from phone photographs.

## Tests And Reproduction

From this experiment's `tests` directory:

```powershell
& 'D:/Xilinx/Vivado/2018.3/bin/xvlog.bat' --sv ../source/rtl/reg_config.v ../source/rtl/i2c_com.v sensor_colorbar_config_tb.v
& 'D:/Xilinx/Vivado/2018.3/bin/xelab.bat' sensor_colorbar_config_tb --O3 -s sensor_colorbar_config_sim
& 'D:/Xilinx/Vivado/2018.3/bin/xsim.bat' sensor_colorbar_config_sim -runall -log sensor_colorbar_config.log
```

The test accelerates the divider but retains both real FSMs, decodes actual
SCL/SDA data bits, checks every original write plus the new one, and repeats
after reset. Passing output: 716 serialized transactions across two resets.
`original_registers.hex` contains all 357 baseline table entries, including the
pre-existing default writes. This is a digital simulation, not a sensor model.

The inherited initialization FSM does not check ACK before marking completion.
The inherited I2C sender also overwrites its first ACK sample. This diagnostic
does not repair that broader behavior or add register readback. An init LED
alone is not evidence that the physical sensor accepted the test-mode write.

From this experiment root, use a fresh run script copied from `flow.tcl`:

```powershell
Copy-Item -LiteralPath flow.tcl -Destination impl.tcl
& 'D:/PDS/PDS_2022.2-SP6.1/bin/pds_shell.exe' -file impl.tcl -continue
```

PDS modifies the run script, so do not run `flow.tcl` itself. Always inspect
the fresh build log and timing report, not just the existence of an old sbit.
Camera input-delay constraints remain incomplete; satisfying the supplied
constraints is not full timing sign-off of the camera interface.

## Board Check

1. Keep the camera on CMOS1 and retain the same HDMI output connection.
2. Load the explicitly named `10_sensor_colorbar_cmos1.sbit` once published.
3. Expect sensor-generated static color bars, not the room or a road scene.
   Moving an object in front of the lens should not change those bars.
4. Record whether the white bar appears white, whether primary colors are
   distinct, and whether there are stripes, noise or unstable edges. Photograph
   the entire display and report the naked-eye color impression.
5. If bars do not appear, report what does appear. Do not treat the init LED
   as proof of success or make a color diagnosis from the wrong video source.

Normal bars strengthen the case for real-scene capture/optics/ISP adaptation;
abnormal bars keep sensor configuration, DVP reception, RGB ordering and the
camera-driven path under investigation. Neither outcome alone proves a failed
sensor. Focus/blur requires a separate optical image, not a synthetic pattern.

Restore the original raw CMOS1 file or retained version 4 to return to live
camera video. If test bars persist, power off and on and reload the intended
file. Do not unplug the camera while powered.
