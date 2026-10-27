"""Read-only checks of old evidence; write new records only inside this experiment."""
import argparse
import hashlib
import json
from pathlib import Path
import re

HERE = Path(__file__).resolve().parents[1]
ROOT = HERE.parents[1]


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def read(path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def write(path, value):
    path.write_text(json.dumps(value, indent=2, ensure_ascii=True) + "\n", encoding="ascii")


def snapshot():
    pins = {}
    for experiment in ("road_config_pipe_20261017", "road_ddr_bridge_20261017"):
        base = HERE.parent / experiment
        pin = read(base / "verification.json")
        for table in ("source_sha256", "evidence_sha256"):
            for name, value in pin[table].items():
                path = base / name
                assert digest(path).lower() == value.lower(), f"Pinned evidence changed: {path}"
                pins[str(path.relative_to(ROOT))] = digest(path)
        pins[str((base / "verification.json").relative_to(ROOT))] = digest(base / "verification.json")
    protected = read(HERE.parent / "road_ddr_bridge_20261017/tests/output/protected_before.json")
    for name, value in protected.items():
        path = ROOT / name
        assert digest(path).lower() == value.lower(), f"Protected source changed: {name}"
        pins[str(path.relative_to(ROOT))] = digest(path)
    assert digest(ROOT / "bitstreams/4_road_markings_filtered_cmos1.sbit") == (
        "ed53c960f810528bec0a641565a00b1a6fed9c2e6fcfaedac1af64f32d613467")
    for path in list(ROOT.glob("source/**/*")) + list(HERE.glob("source/*")) + list(HERE.glob("tests/*")):
        if path.is_file():
            pins[str(path.relative_to(ROOT))] = digest(path)
    library = Path("D:/PDS/PDS_2022.2-SP6.1/arch/vendor/pango/verilog/simulation")
    for name in ("GTP_GRS.v", "GTP_DRM18K.v"):
        path = library / name
        pins[str(path)] = digest(path)
    return pins


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--capture", type=Path)
    parser.add_argument("--verify", type=Path)
    parser.add_argument("--check-inputs", type=Path)
    args = parser.parse_args()
    if args.capture:
        write(args.capture / "inputs.json", snapshot())
        print("PASS: pinned stage-1/stage-2 evidence and protected main files")
    elif args.check_inputs:
        assert read(args.check_inputs / "inputs.json") == snapshot(), "Inputs changed during run"
        print("PASS: inputs stable; old evidence and main RTL unchanged")
    else:
        run = args.verify
        assert read(run / "inputs.json") == snapshot(), "Inputs changed during simulation"
        text = (run / "simulation.log").read_text(errors="replace")
        assert not re.search(r"\*\* (Error|Fatal):", text), "Simulator failure"
        counts = list(map(int, (run / "counts.txt").read_text().split()))
        keys = ("scenario", "pixels_checked", "pixel_errors", "write_pixels_checked",
                "write_pixel_errors", "complete_output_frames", "accelerator_responses",
                "max_video_command_wait_ui_cycles", "max_accelerator_latency_ui_cycles",
                "camera_ring_peak_pixels", "camera_ring_min_pixels", "display_ring_peak_pixels",
                "display_ring_min_pixels", "ui_cycles", "accelerator_requests_during_active_video",
                "common_reset_recovery_checks")
        result = dict(zip(keys, counts))
        result.update(stage=2, stage_acceptance_passed=False,
                      framebuffer_integrity_passed="PASS: actual framebuffer integration" in text,
                      actual_vendor_frame_ram_models=True, native_memory_bfm=True,
                      full_vendor_ddr_phy=False, board_programmed=False, new_bitstream=False,
                      complete_model=False, deployment_approved=False)
        result["evidence_sha256"] = {p.name: digest(p) for p in run.iterdir()
                                     if p.is_file() and p.name != "result.json"}
        write(run / "result.json", result)
        print(json.dumps(result, indent=2))
        assert result["framebuffer_integrity_passed"], "Video integrity acceptance failed"


if __name__ == "__main__":
    main()
