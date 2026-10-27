"""Check simulation evidence, resource mapping, and protected source boundary."""
from pathlib import Path
import hashlib
import json
import re

EXPERIMENT = Path(__file__).resolve().parents[1]
ROOT = EXPERIMENT.parents[1]


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    cases = {}
    for case in ("small", "extreme", "road", "shelf"):
        log = (EXPERIMENT / "tests" / (case + ".log")).read_text(encoding="utf-8")
        match = re.search(r"PASS: (\d+)x(\d+) input; (\d+) thumbnail pixels; (\d+) frozen reads; protected snapshots", log)
        if not match or re.search(r"Fatal:|\$fatal|ERROR:", log):
            raise ValueError("No clean pass: " + case)
        width, height, thumbnails, reads = map(int, match.groups())
        expected = (64, 32, 480, 416) if case in ("small", "extreme") else (1280, 720, 57600, 43200)
        if (width, height, thumbnails, reads) != expected:
            raise ValueError("Unexpected coverage: " + case)
        cases[case] = dict(width=width, height=height, thumbnail_pixels=thumbnails, frozen_reads=reads)
    log = (EXPERIMENT / "synthesis.log").read_text(encoding="utf-8", errors="replace")
    if "Executing : dev_map successfully." not in log or re.search(r"^E:", log, re.M):
        raise ValueError("Device mapping did not succeed")
    resources = {}
    for key, pattern in (("luts", r"Total LUTs: (\d+)"), ("registers", r"Total Registers: (\d+)"),
                         ("drm18k", r"Total DRM18K = ([\d.]+)"), ("apms", r"Total APMs = ([\d.]+)")):
        resources[key] = float(re.search(pattern, log).group(1))
    protected = {
        "source/rtl/lane_detect.v": "6e0df02de7b5ca383bc7293f2141c28a9ab3b506cc908a907b2ed9509e5ca110",
        "source/rtl/reg_config.v": "3fb595d4000aaaaedf9261551613c7c35d79dd5db69e174ef901ea8c9f1a9469",
        "source/rtl/cmos_8_16bit.v": "76641afe2520541a75c3d9ebd4950ed683b4c86be7e99227a6b14ece0d037516",
        "bitstreams/4_road_markings_filtered_cmos1.sbit": "ed53c960f810528bec0a641565a00b1a6fed9c2e6fcfaedac1af64f32d613467",
        "bitstreams/6_road_framefix_v4_cmos1.sbit": "599c5a26752885da38a8a8ecca0d3fb53f3ca30854753df0f0e20d4c83b942b9",
        "bitstreams/7_zebra_candidate_v4_cmos1.sbit": "808a9c281b11658d3326008db745d135aaeded0fd26bbf0e17d49e955770cd1a",
        "bitstreams/8_adas_lane_status_cmos1.sbit": "4714b2f26e2e71de27627a709c23daf98818421613f850f97bbe73c8a8772573",
        "bitstreams/9_adas_selftest_no_camera.sbit": "912bfb169f0a6205c5c79f494bd04a4b67e110567f2b762b61998d48e7d30843",
        "bitstreams/10_sensor_colorbar_cmos1.sbit": "b7c53ac342437d4da2f8030f12922f429fe02fc4bacc4edcfb166f3cd79257a3",
    }
    for name, expected in protected.items():
        if sha256(ROOT / name) != expected:
            raise ValueError("Protected file mismatch: " + name)
    sources = [*sorted((EXPERIMENT / "source").glob("*.v")), EXPERIMENT / "tests/road_input_tb.v",
               EXPERIMENT / "tests/fixtures.py", EXPERIMENT / "flow.tcl"]
    result = {"simulation_cases": cases, "mapped_resources": resources,
              "source_sha256": {str(p.relative_to(EXPERIMENT)): sha256(p) for p in sources},
              "protected_sha256": protected,
              "integrated_in_main_top": False, "bitstream_generated": False,
              "timing_signed_off": False, "hardware_tested": False,
              "road_model_deployed": False,
              "limits": "Standalone same-clock preprocessing/buffer only. Resource mapping without PNR or interface timing constraints is not integration signoff."}
    (EXPERIMENT / "tests/verification.json").write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
