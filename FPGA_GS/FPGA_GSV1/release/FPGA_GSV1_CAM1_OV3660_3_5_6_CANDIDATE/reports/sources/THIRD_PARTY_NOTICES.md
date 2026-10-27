# OV3660 configuration sources

The derived `cam_ov3660_table.v` changes the archived Espressif OV3660 defaults
by retaining standby until configuration completes, setting fixed 720p geometry,
RGB565 output, explicit clock/polarity, and reset/settling delays. It is generated
by `scripts/generate_ov3660_table.py`; the per-entry origin is in the manifest.

Espressif esp32-camera repository: https://github.com/espressif/esp32-camera
Source URLs and immutable content hashes are archived in manifest.json.
Its repository license is Apache License 2.0, copied in esp32_camera_LICENSE.txt.
The archived ov3660.c additionally carries this notice:

> This file is part of the OpenMV project.
> Copyright (c) 2013/2014 Ibrahim Abdelkader <i.abdalkader@gmail.com>
> This work is licensed under the MIT license, see the file LICENSE for details.

MIT License

Copyright (c) 2013/2014 Ibrahim Abdelkader <i.abdalkader@gmail.com>

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

Sensor register semantics and PLL limits come from OmniVision OV3660
PRELIMINARY Specification v1.3 (2011-05-13), archived for project reference.
This is separate from the software license and does not establish the TY
module's connector pinout.
