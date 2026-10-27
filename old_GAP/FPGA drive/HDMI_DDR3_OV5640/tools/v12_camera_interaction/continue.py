"""Continue v12 after archive relocation; no programmer or Flash commands."""
import argparse
import hashlib
import json
import re
import shutil
from datetime import datetime
from pathlib import Path

PROJECT = Path(__file__).resolve().parents[2]
WORKSPACE = PROJECT.parent
ARCHIVE = WORKSPACE / "_archive/experiments"
PREVIOUS = ARCHIVE / "v12_camera_interaction_20261018/runs/20261018_143119_235"
V11 = ARCHIVE / "v11_lane_interaction_20261018"
TOP = "hdmi_ddr_ov5640_top"
NAME = "12_lane_interaction_camera_candidate_cmos1"


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def dump(path, value):
    path.write_text(json.dumps(value, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def read(path):
    return json.loads(path.read_text(encoding="utf-8"))


def protected():
    paths = [p for p in (PROJECT / "source").rglob("*") if p.is_file()]
    paths += list((PROJECT / "bitstreams").rglob("*"))
    paths += [PROJECT / name for name in ("flow.tcl", TOP + ".fdc", "HDMI_DDR3_OV5640.pds")]
    paths += [p for p in V11.rglob("*") if p.is_file() and "__pycache__" not in p.parts]
    return {str(p): sha(p) for p in paths if p.is_file()}


def replace_once(text, old, new):
    if text.count(old) != 1:
        raise RuntimeError(f"Expected exactly one constraint: {old}")
    return text.replace(old, new, 1)


def prepare(run):
    previous_hashes = read(PREVIOUS / "inputs.json")
    old_prefix = f"/runs/{PREVIOUS.name}/"
    copied = {}
    for old, expected in previous_hashes.items():
        normalized = old.replace("\\", "/")
        if old_prefix in normalized:
            relative = normalized.split(old_prefix, 1)[1]
            actual = PREVIOUS / relative
        elif normalized.endswith("/tests/camera_pipeline_tb.sv"):
            actual = PREVIOUS.parents[1] / "tests/camera_pipeline_tb.sv"
            relative = "camera_pipeline_tb.sv"
        else:
            raise RuntimeError(f"Unresolved historical input: {old}")
        if sha(actual) != expected:
            raise RuntimeError(f"Historical input changed: {actual}")
        copied[relative] = expected
    # The repository was reorganized while a read-only timing report ran.
    # Verify current protected design against the original manifest, not README.
    old_protected = read(PREVIOUS / "protected_inputs.json")
    for relative, expected in old_protected.items():
        if relative.startswith(("source/", "bitstreams/")) or "/" not in relative:
            if sha(PROJECT / relative) != expected:
                raise RuntimeError(f"Main design changed since first build: {relative}")
    sim = read(PREVIOUS / "simulation_verification.json")
    for name, evidence in sim["tests"].items():
        path = PREVIOUS / f"{name}.simulation.log"
        text = path.read_text(errors="replace")
        if sha(path) != evidence["log_sha256"] or f"PASS {name}:" not in text:
            raise RuntimeError("Simulation evidence no longer matches")
    run.mkdir(parents=True, exist_ok=False)
    dump(run / "protected_inputs.json", protected())
    shutil.copytree(PREVIOUS / "source", run / "source")
    shutil.copy2(PREVIOUS / "map.tcl", run / "map.tcl")
    fdc = (PREVIOUS / (TOP + ".fdc")).read_text(encoding="utf-8")
    for clock in ("cmos1_pclk_16bit", "pix_clk"):
        line = f"set_clock_groups -name {clock} -asynchronous -group [get_clocks {{{clock}}}]"
        fdc = replace_once(fdc, line, "# v12: replaced blanket group by endpoint-specific mailbox exceptions: " + clock)
    fdc += """
# Only the first synchronizer stages are asynchronous observation points.
set_false_path -to [get_cells -hierarchical {*u_lane_local_ui*g_camera*mailbox*req_meta*}]
set_false_path -to [get_cells -hierarchical {*u_lane_local_ui*g_camera*mailbox*ack_meta*}]
# Bundled data is held until acknowledgement. Keep its max-delay checked;
# asynchronous hold is not a meaningful inter-clock edge relationship.
set_false_path -hold -from [get_cells -hierarchical {*u_lane_local_ui*g_camera*mailbox*held*}] -to [get_cells -hierarchical {*u_lane_local_ui*g_camera*mailbox*dst_snapshot*}]
"""
    (run / (TOP + ".fdc")).write_text(fdc, encoding="utf-8")
    dump(run / "simulation_reuse.json", {
        "previous": str(PREVIOUS), "source_hashes_identical": True,
        "changed": "constraints only; removed two blanket clock groups, added first-stage/hold exceptions",
        "simulations_rerun": 0, "tests": sim["tests"],
        "historical_inputs_verified": len(copied),
        "not_a_new_physical_test": True,
    })
    for name in sim["tests"]:
        shutil.copy2(PREVIOUS / f"{name}.simulation.log", run / f"{name}.simulation.log")
    dump(run / "simulation_verification.json", sim)
    paths = [p for p in (run / "source").rglob("*") if p.is_file()]
    paths += [run / "map.tcl", run / (TOP + ".fdc")]
    dump(run / "inputs.json", {p.relative_to(run).as_posix(): sha(p) for p in paths})
    dump(run / "recipe.json", {
        "created_at": datetime.now().astimezone().isoformat(),
        "previous_build": str(PREVIOUS),
        "constraint_attempt": 2,
        "previous_attempt": "routed successfully, but targeted report had no bundled-data paths; not released",
        "variant": "real CMOS1, LOCAL CANDIDATE; same source as tested first build",
        "local_rule_test": 0, "self_test": 0,
        "archive_relocation": "external cleanup commit 6f68d09 preserved; archived logs not rewritten",
        "code_change": False, "detector_threshold_change": False,
        "programmed": False, "flash_written": False,
    })
    print(run)


def collect(run):
    destination = run / "place_route"
    destination.mkdir(exist_ok=True)
    for name in (TOP + ".prr", TOP + "_pnr.adf"):
        if not any((directory / name).is_file() for directory in (run, destination)):
            raise RuntimeError("Missing PNR output in run root or place_route")
    for pattern in ("*.prr", "*_pnr.adf", "*_plc.adf", "*_timing*.txt",
                    "clock_utilization.txt", "layers.txt", "prr.db"):
        for path in run.glob(pattern):
            shutil.copy2(path, destination / path.name)
    for action, stem, options in (
        ("report_timing", "timing_only", " -report_exception TRUE -max_path 128"),
        ("gen_bit_stream", "bitstream_only", " -create_mask_file TRUE"),
    ):
        (run / (stem + ".tcl")).write_text(
            "set_arch -family Logos -device PGL50H -speedgrade -6 -package FBG484\n"
            f'{action} -input_db_file "place_route/{TOP}_pnr.adf" -force_to_run{options}\n',
            encoding="ascii")


def hold_command(run=Path(".")):
    return (
        f'pnr -input_db_file "{(run / "device_map" / (TOP + "_map.adf")).as_posix()}" '
        f'-input_place_db_file "{(run / "checkpoints" / (TOP + "_plc.adf")).as_posix()}" -force_to_run '
        '-optimize_multi_corner_timing -fix_hold_violation '
        '-fix_hold_violation_threshold 50 -fix_hold_violation_in_route TRUE '
        '-fix_hold_violation_threshold_for_clock_path_cross_srb 50 '
        '-fix_hold_violation_threshold_for_clk_tree 50\n'
    )


def prepare_hold(run, previous):
    """One routing-only attempt, preserving both previous builds and constraints."""
    audit = read(previous / "timing_audit.json")
    if audit["errors"] != ["routed timing not met"]:
        raise RuntimeError("Expected only the documented routed timing failure")
    if protected() != read(previous / "protected_inputs.json"):
        raise RuntimeError("Protected files changed since the previous build")
    for relative, expected in read(previous / "inputs.json").items():
        if sha(previous / relative) != expected:
            raise RuntimeError(f"Previous build input changed: {relative}")
    run.mkdir(parents=True, exist_ok=False)
    shutil.copytree(previous / "source", run / "source")
    for name in ("map.tcl", TOP + ".fdc", "map.log", "simulation_reuse.json",
                 "simulation_verification.json", "camera_pipeline.simulation.log",
                 "cdc.simulation.log", "protected_inputs.json"):
        shutil.copy2(previous / name, run / name)
    (run / "device_map").mkdir()
    (run / "checkpoints").mkdir()
    checkpoints = {}
    for old, new in (
        (previous / "device_map" / (TOP + "_map.adf"),
         run / "device_map" / (TOP + "_map.adf")),
        (previous / (TOP + "_plc.adf"), run / "checkpoints" / (TOP + "_plc.adf")),
    ):
        shutil.copy2(old, new)
        checkpoints[str(old)] = sha(new)
    (run / "resume_hold.tcl").write_text(
        "set_arch -family Logos -device PGL50H -speedgrade -6 -package FBG484\n"
        + hold_command(run), encoding="ascii")
    paths = [p for p in (run / "source").rglob("*") if p.is_file()]
    paths += [run / "map.tcl", run / (TOP + ".fdc"), run / "resume_hold.tcl"]
    paths += list((run / "device_map").glob("*.adf"))
    paths += list((run / "checkpoints").glob("*.adf"))
    dump(run / "inputs.json", {p.relative_to(run).as_posix(): sha(p) for p in paths})
    dump(run / "recipe.json", {
        "created_at": datetime.now().astimezone().isoformat(),
        "previous_build": str(previous), "constraint_attempt": 2,
        "hold_repair_attempt": 1, "hold_repair_threshold_ps": 50,
        "hypothesis": "A positive repair margin with explicit multi-corner optimization "
                      "can remove the residual fast-corner -5ps same-clock hold failure.",
        "checkpoint_hashes": checkpoints,
        "source_constraints_unchanged": True,
        "synthesis_rerun": False, "mapping_rerun": False,
        "map_log_reused_from": str(previous / "map.log"),
        "programmed": False, "flash_written": False,
        "automatic_retry_on_failure": False,
    })
    print(run)


def check(run, release=False):
    errors = []
    if protected() != read(run / "protected_inputs.json"):
        errors.append("protected design or archived v11 changed")
    for relative, expected in read(run / "inputs.json").items():
        if sha(run / relative) != expected:
            errors.append(f"build input changed: {relative}")
    for name in ("map", "place_route", "timing_only"):
        log = (run / (name + ".log")).read_text(errors="replace")
        if re.search(r"(?m)^\s*E:\s|(?:ERROR:|Error:|FATAL:|Fatal:)", log):
            errors.append(f"tool errors in {name}")
        if name != "map" and re.search(r'Process "(?:Compile|Synthesize|Device Map)" started', log):
            errors.append(f"unexpected upstream rebuild in {name}")
    report = (run / "report_timing" / (TOP + ".rtr")).read_text(errors="replace")
    if "Design Summary : All Constraints Met." not in report:
        errors.append("routed timing not met")
    blocks = re.split(r"(?=Startpoint\s*:)", report)
    bundle = [b for b in blocks if
              re.match(r"Startpoint\s*:\s*u_lane_local_ui[^\n]*held", b) and
              re.search(r"Endpoint\s*:\s*u_lane_local_ui[^\n]*dst_snapshot", b)]
    if not bundle:
        errors.append("no measured mailbox bundle paths")
    elif any(not re.search(r"Slack\s*\(MET\)", b, re.IGNORECASE) for b in bundle):
        errors.append("mailbox bundle slack not met")
    if bundle and not any("14.000" in b for b in bundle):
        errors.append("14ns bundle requirement not visible")
    result = {
        "recorded_at": datetime.now().astimezone().isoformat(),
        "variant": "LOCAL CANDIDATE; real CMOS1 heuristic",
        "errors": errors, "bundle_paths_reported": len(bundle),
        "constrained_timing_met": "Design Summary : All Constraints Met." in report,
        "all_io_timing_signed_off": False, "physical_cdc_signoff": False,
        "simulation_reused_by_matching_hash": True,
        "protected_files_checked": len(read(run / "protected_inputs.json")),
        "programmed": False, "flash_written": False, "board_verified": False,
        "stage_exit_met": False, "real_road_recognition_completed": False,
        "bitstream_generated": False, "bitstream_path": None,
        "ready_for_authorized_candidate_trial": False,
    }
    if release and not errors:
        bitdir = run / "generate_bitstream"
        for extension in (".sbit", ".smsk"):
            if not (bitdir / (TOP + extension)).is_file():
                errors.append("missing generated " + extension)
        log = (run / "bitstream_only.log").read_text(errors="replace")
        if re.search(r"(?m)^\s*E:\s|(?:ERROR:|Error:|FATAL:|Fatal:)", log):
            errors.append("bitstream generation errors")
        if not errors:
            out = run / "bitstreams"
            out.mkdir(exist_ok=True)
            for ext in (".sbit", ".smsk"):
                target = out / (NAME + ext)
                if target.exists() and sha(target) != sha(bitdir / (TOP + ext)):
                    raise RuntimeError("Do not overwrite delivery")
                shutil.copy2(bitdir / (TOP + ext), target)
            result.update({
                "bitstream_generated": True,
                "bitstream_path": str(out / (NAME + ".sbit")),
                "bitstream_sha256": sha(out / (NAME + ".sbit")),
                "mask_sha256": sha(out / (NAME + ".smsk")),
                "ready_for_authorized_candidate_trial": True,
            })
    dump(run / ("verification.json" if release else "timing_audit.json"), result)
    print(json.dumps(result, indent=2))
    if errors:
        raise SystemExit(1)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("action", choices=("prepare", "prepare-hold", "collect", "check", "release"))
    parser.add_argument("--run", type=Path, required=True)
    parser.add_argument("--previous", type=Path)
    args = parser.parse_args()
    actions = {"prepare": prepare, "collect": collect,
               "check": check, "release": lambda run: check(run, release=True)}
    if args.action == "prepare-hold":
        if args.previous is None:
            parser.error("--previous is required for prepare-hold")
        prepare_hold(args.run.resolve(), args.previous.resolve())
    else:
        actions[args.action](args.run.resolve())
