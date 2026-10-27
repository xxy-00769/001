"""Verify the isolated diagnostic source boundary and digital simulation evidence."""
import hashlib
import json
from pathlib import Path
import re

EXPERIMENT = Path(__file__).resolve().parents[1]
PROJECT = EXPERIMENT.parents[1]
ORIGINAL = Path("D:/BaiduNetdiskDownload/HDMI_DDR3_OV5640_test/source/rtl")


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def require(condition, message):
    if not condition:
        raise ValueError(message)


def main():
    paths = list(ORIGINAL.glob("*.v"))
    require(len(paths) == 17, "Unexpected original source inventory")
    hashes = {}
    for source in paths:
        target = EXPERIMENT / "source/rtl" / source.name
        if source.name == "reg_config.v":
            baseline = source.read_bytes().decode("gbk").replace("\r\n", "\n")
            require(baseline.count("reg_index<357") == 1, "Unexpected baseline config count")
            expected = baseline.replace("reg_index<357", "reg_index<358").replace(
                "default:reg_data<=24'hffffff",
                "357: reg_data <= 24'h503d80; // Sensor-generated static color bars, not an FPGA pattern.\n\t default:reg_data<=24'hffffff")
            require(target.read_text(encoding="utf-8").rstrip() == expected.rstrip(),
                    "Unexpected diagnostic configuration edits")
            table = [0xffffff] * 357
            for index, data in re.findall(r"(\d+)\s*:\s*reg_data\s*<=\s*24'h([0-9a-f]{6})", baseline, re.I):
                table[int(index)] = int(data, 16)
            golden = [int(line, 16) for line in (EXPERIMENT / "tests/original_registers.hex").read_text().split()]
            require(table == golden, "Simulation golden writes differ from original source")
        else:
            require(sha256(target) == sha256(source), f"Unexpected source change: {source.name}")
        hashes[str(target.relative_to(EXPERIMENT))] = sha256(target)
    log = (EXPERIMENT / "tests/sensor_colorbar_config.log").read_text()
    require("PASS: two resets; 357 original writes preserved; final 0x503D=0x80; 716 serialized transactions verified" in log,
            "Missing simulation pass")
    require("Fatal:" not in log, "Simulation fatal error")
    require(sha256(PROJECT / "source/rtl/reg_config.v") == sha256(ORIGINAL / "reg_config.v"),
            "Main camera register configuration changed")
    require(sha256(PROJECT / "source/rtl/cmos_8_16bit.v") == sha256(ORIGINAL / "cmos_8_16bit.v"),
            "Main DVP receiver changed")
    protected = {
        "4_road_markings_filtered_cmos1.sbit": "ed53c960f810528bec0a641565a00b1a6fed9c2e6fcfaedac1af64f32d613467",
        "6_road_framefix_v4_cmos1.sbit": "599c5a26752885da38a8a8ecca0d3fb53f3ca30854753df0f0e20d4c83b942b9",
        "7_zebra_candidate_v4_cmos1.sbit": "808a9c281b11658d3326008db745d135aaeded0fd26bbf0e17d49e955770cd1a",
        "8_adas_lane_status_cmos1.sbit": "4714b2f26e2e71de27627a709c23daf98818421613f850f97bbe73c8a8772573",
        "9_adas_selftest_no_camera.sbit": "912bfb169f0a6205c5c79f494bd04a4b67e110567f2b762b61998d48e7d30843",
    }
    for filename, expected in protected.items():
        require(sha256(PROJECT / "bitstreams" / filename) == expected, f"Protected bitstream changed: {filename}")
    require(sha256(EXPERIMENT / "hdmi_ddr_ov5640_top.fdc") == sha256(PROJECT / "hdmi_ddr_ov5640_top.fdc"),
            "Constraints were changed")
    for path in (EXPERIMENT / "references").iterdir():
        hashes[str(path.relative_to(EXPERIMENT))] = sha256(path)
    for relative in ("hdmi_ddr_ov5640_top.fdc", "flow.tcl", "tests/sensor_colorbar_config_tb.v",
                     "tests/original_registers.hex", "tests/sensor_colorbar_config.log"):
        hashes[relative] = sha256(EXPERIMENT / relative)
    bitstream_name = "10_sensor_colorbar_cmos1.sbit"
    expected_bitstream = "b7c53ac342437d4da2f8030f12922f429fe02fc4bacc4edcfb166f3cd79257a3"
    for path in (EXPERIMENT / "generate_bitstream/hdmi_ddr_ov5640_top.sbit",
                 EXPERIMENT / "bitstreams" / bitstream_name, PROJECT / "bitstreams" / bitstream_name):
        require(path.stat().st_size == 2101696 and sha256(path) == expected_bitstream,
                f"Published diagnostic file mismatch: {path}")
    timing_path = EXPERIMENT / "report_timing/hdmi_ddr_ov5640_top.rtr"
    require("Design Summary : All Constraints Met." in timing_path.read_text(), "Final timing summary did not pass")
    build_path = EXPERIMENT / "build_sensor_colorbar_v10.log"
    build_log = build_path.read_text(encoding="utf-8")
    require("Executing : gen_bit_stream successfully." in build_log and not re.search(r"^E:", build_log, re.M),
            "Build log did not pass")
    for path in (timing_path, build_path, EXPERIMENT / "bitstreams" / bitstream_name):
        hashes[str(path.relative_to(EXPERIMENT))] = sha256(path)
    report = {"status": "PASS", "source_files": 17, "unchanged_verilog_files": 16,
              "serialized_writes_tested": 716, "hardware_tested": False,
              "source_hashes": hashes, "protected_bitstreams": protected}
    (EXPERIMENT / "tests/source_verification.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print("PASS: 16 byte-identical source copies; only append 0x503D=0x80 in config; golden writes verified; old bitstreams intact")


if __name__ == "__main__":
    main()
