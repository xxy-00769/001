"""Read-only build evidence audit and named delivery copy; no board commands."""
import argparse
import re
import shutil
from pathlib import Path

import prepare as prep

build = prep.build
TOP = "hdmi_ddr_ov5640_top"


def audit(run):
    errors = []
    for path, expected in build.read(run / "inputs.json").items():
        if build.sha(Path(path)) != expected:
            errors.append(f"input changed: {path}")
    if prep.protected() != build.read(run / "protected_inputs.json"):
        errors.append("protected v4/v8/v11 or main-design files changed")
    files = {
        "compile": run / "compile" / f"{TOP}.cmr",
        "synthesis": run / "synthesize" / f"{TOP}.snr",
        "mapping": run / "device_map" / f"{TOP}.dmr",
        "place_route": run / "place_route" / f"{TOP}.prr",
        "timing": run / "report_timing" / f"{TOP}.rtr",
        "bitstream": run / "generate_bitstream" / f"{TOP}.sbit",
        "mask": run / "generate_bitstream" / f"{TOP}.smsk",
    }
    present = {key: path.is_file() and path.stat().st_size > 0
               for key, path in files.items()}
    for key, exists in present.items():
        if not exists:
            errors.append(f"missing {key}")
    for name in ("map", "place_route", "timing_only", "bitstream_only"):
        path = run / f"{name}.log"
        if not path.exists():
            errors.append(f"missing {name} log")
        elif build.fatal_log_lines(path.read_text(errors="replace")):
            errors.append(f"fatal errors in {name} log")
    report = files["timing"].read_text(errors="replace") if present["timing"] else ""
    timing_ok = "Design Summary : All Constraints Met." in report
    if not timing_ok:
        errors.append("routed timing not accepted")
    # Require measured exception paths, not just the echoed constraint command.
    bundle_paths = [
        block for block in re.split(r"(?=Startpoint\s*:)", report)
        if re.match(r"Startpoint\s*:\s*u_lane_local_ui[^\n]*held", block)
        and re.search(r"Endpoint\s*:\s*u_lane_local_ui[^\n]*dst_snapshot", block)
        and re.search(r"slack\s*\(MET\)", block, flags=re.IGNORECASE)
    ]
    if not bundle_paths:
        errors.append("mailbox bundled-data max-delay not demonstrated in timing report")
    simulation = build.read(run / "simulation_verification.json")
    if not all(t["passed"] for t in simulation["tests"].values()):
        errors.append("simulation not accepted")
    result = {
        "artifacts_present": present, "errors": errors,
        "constrained_timing_met": timing_ok,
        "cdc_bundle_paths_reported": len(bundle_paths),
        "all_io_timing_signed_off": False, "physical_cdc_signoff": False,
        "programmed": False, "flash_written": False, "board_verified": False,
        "stage_exit_met": False, "real_road_recognition_completed": False,
        "bitstream_path": None, "ready_for_authorized_candidate_trial": not errors,
    }
    if not errors:
        delivery = run / "bitstreams"
        delivery.mkdir(exist_ok=True)
        for extension, key in ((".sbit", "bitstream"), (".smsk", "mask")):
            target = delivery / (prep.NAME + extension)
            if target.exists() and build.sha(target) != build.sha(files[key]):
                raise RuntimeError("Do not overwrite a different delivery artifact")
            shutil.copy2(files[key], target)
        result["bitstream_path"] = str(delivery / (prep.NAME + ".sbit"))
        result["bitstream_sha256"] = build.sha(Path(result["bitstream_path"]))
        result["mask_sha256"] = build.sha(delivery / (prep.NAME + ".smsk"))
    build.dump(run / "verification.json", result)
    print(result)
    if errors:
        raise SystemExit(1)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--run", required=True, type=Path)
    args = parser.parse_args()
    audit(args.run.resolve())
