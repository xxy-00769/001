"""Fixed 720p table from archived Espressif OV3660 driver and sensor datasheet.

The analog/ISP defaults are preserved, not copied from OV5640. See the archived
source manifest for hashes and OV3660 datasheet v1.3 tables 2-4, 2-8, 2-9.
"""
from pathlib import Path
import re
import json

root = Path(__file__).resolve().parents[1]
settings = (root / 'reports/sources/sensors_private_include_ov3660_settings.h').read_text()
regs = (root / 'reports/sources/sensors_private_include_ov3660_regs.h').read_text()
names = {k: int(v, 16) for k, v in re.findall(r'#define\s+(\w+)\s+(0x[0-9a-fA-F]+)', regs)}
names['REG_DLY'] = 0xffff
block = settings.split('sensor_default_regs[][2] = {')[1].split('};')[0]
block = re.sub(r'//[^\n]*', '', block)
entries = []
for addr, val in re.findall(r'\{\s*(\w+)\s*,\s*(0x[0-9a-fA-F]+|\d+)\s*\}', block):
    if addr == 'REGLIST_TAIL':
        break
    address = int(addr, 16) if addr.startswith('0x') else names[addr]
    value = int(val, 0)
    # Keep standby until geometry/format/clock programming is complete.
    if (address, value) == (0x3008, 0x02):
        continue
    if address == 0xffff:
        value = 100  # driver reset() also waits 100 ms after software reset
    entries.append((address, value, 'OV3660 sensor_default_regs'))

def add(a, v, reason):
    entries.append((a, v, reason))

def word(a, value, reason):
    add(a, value >> 8, reason)
    add(a + 1, value & 255, reason)

# Espressif ratio_table[16x9], set_framesize(1280x720): full-resolution readout
# with ISP DOWNscaling, no binning, no low-resolution image enlarged to 720p.
for a, v in [(0x3800, 64), (0x3802, 242), (0x3804, 2015), (0x3806, 1333),
             (0x3808, 1280), (0x380a, 720), (0x380c, 2172), (0x380e, 1322),
             (0x3810, 16), (0x3812, 6)]:
    word(a, v, 'OV3660 set_framesize HD/16x9, non-binned')
for a, v in [(0x5001, 0xa3), (0x3820, 0x40), (0x3821, 0x00),
             (0x4514, 0x88), (0x4520, 0xb0), (0x3814, 0x11), (0x3815, 0x11)]:
    add(a, v, 'OV3660 set_framesize/set_image_options normal/non-binned')
add(0x501f, 1, 'OV3660 sensor_fmt_rgb565')
add(0x4300, 0x61, 'datasheet table 2-4: RGB565 R-high-byte then B-low-byte')
# 24 MHz board oscillator. REFIN=12 MHz, VCO=288 MHz (150..500 MHz),
# PLLCLK=144 MHz (<=216 MHz), SYSCLK=36 MHz; manual /1 -> DVP PCLK=72 MHz.
# RGB565 needs two bytes/pixel: PCLK/SYSCLK=2 also keeps the 2560 active
# bytes inside HTS=2172 SYSCLK cycles. Do not use PCLK /2 with this HTS.
# Use actual OV3660 303A..D controls, NOT OV5640 3034..37 clock registers.
for a, v in [(0x303a, 0), (0x303b, 24), (0x303c, 0x12),
             (0x303d, 0x20), (0x3824, 1), (0x460c, 0x22)]:
    add(a, v, 'OV3660 datasheet figure 2-7/tables 2-8,2-9; 24MHz XCLK')
# Restore the datasheet reset/default DVP sync polarity profile. The previous
# 0x23 selection inverted both sync signals relative to fig5-7 on this module:
# G1 measured only 2*HTS=4344 pixels in one row, exactly the two-line VS interval.
# Bits5/3/2 (PCLK polarity and clock gating) stay unchanged. Do not alter clocks.
add(0x4740, 0x20, 'datasheet table 5-2 default sync profile; G1 4344/1/03 signature; PCLK unchanged')
add(0x3008, 0x02, 'exit software standby after complete configuration')
add(0xffff, 100, 'settle after enabling output, then verify critical registers')

lines = ['`timescale 1ns/1ps',
         '// Derived OV3660-only table. Espressif/OpenMV attribution and licenses',
         '// and archived source hashes in reports/sources. Regenerate with',
         '// scripts/generate_ov3660_table.py. No OV5640 table is used.',
         'module cam_ov3660_table(input [8:0] index,output reg [23:0] entry);',
         'always @* begin', '  case(index)']
for i, (a, v, why) in enumerate(entries):
    lines.append(f"    9'd{i}:entry=24'h{a:04x}{v:02x}; // {why}")
lines += ["    default:entry=24'h000000;", '  endcase', 'end', 'endmodule', '']
(root / 'rtl/capture/cam_ov3660_table.v').write_text('\n'.join(lines))
(root / 'sim/ov3660_expected.hex').write_text(''.join(f'{a:04x}{v:02x}\n' for a,v,_ in entries))
(root / 'reports/ov3660_table_manifest.json').write_text(json.dumps({
    'entries': len(entries), 'last_index': len(entries)-1,
    'clock_hz_calculated': {'XCLK': 24000000, 'REFIN': 12000000, 'VCO': 288000000,
                            'PLLCLK': 144000000, 'SYSCLK': 36000000, 'DVP_PCLK': 72000000},
    'entries_with_origin': entries,
}, indent=2), encoding='utf-8')
print(f'Generated {len(entries)} OV3660-only entries; final index {len(entries)-1}')
