"""Prepare/check one isolated RULE TEST build. Never operates a board."""
import argparse
import hashlib
import importlib.util
import json
import re
import shutil
from datetime import datetime
from pathlib import Path

EXPERIMENT = Path(__file__).resolve().parent
PROJECT = EXPERIMENT.parents[1]
TOP = "hdmi_ddr_ov5640_top"
NAME = "11_lane_interaction_rule_test_cmos1"
PASS_RUN = EXPERIMENT / "runs/20261018_104949_462"


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def dump(path, data):
    path.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def read(path):
    return json.loads(path.read_text(encoding="utf-8"))


def fatal_log_lines(log):
    return [line for line in log.splitlines()
            if re.search(r"(^|\s)(?:ERROR:|Error:|FATAL:|Fatal:)", line)
            or re.match(r"^\s*E:(?:\s|$)", line)]


def get_generator():
    spec = importlib.util.spec_from_file_location("v11_prepare", EXPERIMENT / "tests/prepare.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def protected():
    paths = [p for p in (PROJECT / "source").rglob("*") if p.is_file()]
    paths += [p for p in (PROJECT / "bitstreams").rglob("*") if p.is_file()]
    paths += [PROJECT / p for p in ("flow.tcl", f"{TOP}.fdc", "HDMI_DDR3_OV5640.pds")]
    return {p.relative_to(PROJECT).as_posix(): sha(p) for p in sorted(paths)}


def prepare(run):
    confirmation = read(EXPERIMENT / "hardware_review/user_confirmation_20261018.json")
    if not (confirmation["board_correspondence_user_confirmed"] and
            confirmation["board_model"] == "MES50HP" and confirmation["user_button_count"] == 8):
        raise RuntimeError("Hardware model not confirmed")
    old_inputs = read(PASS_RUN / "inputs.json")
    # Reuse only the exact hardware logic and testbench versions actually simulated.
    relevant = {p: v for p, v in old_inputs.items()
                if "/v11_lane_interaction_" in p and p.endswith((".v", ".sv"))}
    for relative, info in relevant.items():
        if sha(PROJECT / relative) != info["sha256"]:
            raise RuntimeError(f"Changed RTL/testbench needs focused regression: {relative}")
    for name in ("buttons", "control", "cdc", "rule_source", "overlay", "local_ui"):
        log = (PASS_RUN / f"{name}.simulation.log").read_text(encoding="utf-8", errors="replace")
        if f"PASS {name}:" not in log or "** Error:" in log or "** Fatal:" in log:
            raise RuntimeError("Missing clean simulation evidence")
    run.mkdir(parents=True, exist_ok=False)
    dump(run / "protected_inputs.json", protected())
    get_generator().generate(run, rule_test=1, physical_keys_confirmed=True)
    shutil.copytree(PROJECT / "source", run / "source")
    shutil.copy2(run / "generated" / f"{TOP}.v", run / "source/rtl" / f"{TOP}.v")
    for path in (EXPERIMENT / "source").glob("*.v"):
        shutil.copy2(path, run / "source/rtl" / path.name)
    original = (PROJECT / f"{TOP}.fdc").read_text(encoding="utf-8-sig")
    key_fdc = (EXPERIMENT / "hardware_review/keys_reference.fdc").read_text(encoding="ascii")
    key_fdc = key_fdc.replace(
        "# REFERENCE DRAFT: supplied MES50HP manual, physical PCB match pending.",
        "# MES50HP model/8 user keys confirmed by user; manual table 3-8.")
    pins = re.findall(r"\{PAP_IO_LOC\}\s+\{([^}]+)\}", original + "\n" + key_fdc)
    if len(pins) != len(set(pins)):
        raise RuntimeError("Duplicate physical pin assignments")
    (run / f"{TOP}.fdc").write_text(original.rstrip() + "\n\n" + key_fdc, encoding="utf-8")
    flow = """# Isolated v11 RULE TEST on CMOS1; no programmer or Flash commands.
foreach source [glob source/rtl/*.v] {
    add_design $source
}
add_design "source/rtl/pll/pll.idf"
add_design "source/rtl/wr_fram_buf/wr_fram_buf.idf"
add_design "source/rtl/rd_fram_buf/rd_fram_buf.idf"
add_design "source/rtl/DDR3_50H/DDR3_50H.idf"
add_constraint "hdmi_ddr_ov5640_top.fdc"
set_arch -family Logos -device PGL50H -speedgrade -6 -package FBG484
compile -top_module hdmi_ddr_ov5640_top
synthesize -ads -selected_syn_tool_opt 2
dev_map
pnr -optimize_multi_corner_timing -fix_hold_violation -fix_hold_violation_iterations 16 -fix_hold_violation_threshold 200 -fix_hold_violation_in_route TRUE -fix_hold_violation_threshold_for_clk_tree 200
report_timing
gen_bit_stream
"""
    (run / "flow.tcl").write_text(flow, encoding="ascii")
    shutil.copy2(run / "flow.tcl", run / "impl.tcl")
    files = [p for p in (run / "source").rglob("*") if p.is_file()]
    files += [run / f"{TOP}.fdc", run / "flow.tcl"]
    dump(run / "build_inputs.json", {p.relative_to(run).as_posix(): sha(p) for p in sorted(files)})
    dump(run / "recipe.json", {
        "recorded_at": datetime.now().astimezone().isoformat(),
        "variant": "RULE TEST", "self_test": 0, "local_rule_test": 1,
        "video": "real CMOS1 -> existing img_proc -> DDR -> HDMI; unchanged",
        "rule_source": "synthetic four-scene lane kinds; NOT camera recognition",
        "board_confirmation": confirmation,
        "previous_simulation_logs_reused_from": str(PASS_RUN),
        "simulations_rerun": 0,
        "new_camera_mailbox": "not instantiated in RULE TEST bitstream",
        "constraints": "original constraints preserved, only four key input attributes appended",
        "clock_note": "PLL requests 37.125MHz; inherited timing target pix_clk=67.5MHz retained",
        "programmed": False, "flash_written": False, "stage_exit_met": False,
    })
    print(run)


def upstream_manifest(run):
    return {p.relative_to(run).as_posix(): {
                "sha256": sha(p), "mtime_ns": p.stat().st_mtime_ns}
            for directory in ("compile", "synthesize", "device_map")
            for p in sorted((run / directory).rglob("*")) if p.is_file()}


def resume(run, previous):
    if read(previous / "protected_inputs.json") != protected():
        raise RuntimeError("Protected main-design files changed since mapping")
    for relative, expected in read(previous / "build_inputs.json").items():
        if sha(previous / relative) != expected:
            raise RuntimeError(f"Mapped build input changed: {relative}")
    status = read(previous / "verification.json")["artifacts_present"]
    if not all(status[key] for key in ("compile", "synthesis", "mapping")):
        raise RuntimeError("Incomplete upstream checkpoint")
    previous_artifacts = upstream_manifest(previous)
    run.mkdir(parents=True, exist_ok=False)
    for directory in ("source", "generated", "compile", "synthesize",
                      "device_map", "constraint_check"):
        shutil.copytree(previous / directory, run / directory)
    for name in ("impl.pds", "flow.tcl", f"{TOP}.fdc", "protected_inputs.json",
                 "build_inputs.json", "recipe.json"):
        shutil.copy2(previous / name, run / name)
    if upstream_manifest(run) != previous_artifacts:
        raise RuntimeError("Checkpoint copy did not preserve hashes/timestamps")
    dump(run / "upstream_reuse.json", {
        "previous_build": str(previous),
        "recorded_at": datetime.now().astimezone().isoformat(),
        "artifacts": previous_artifacts,
        "copy_verified": True,
        "allowed_actions": ["pnr", "report_timing", "gen_bit_stream"],
        "compile_rerun_allowed": False,
        "synthesis_rerun_allowed": False,
        "mapping_rerun_allowed": False,
        "programming_allowed": False,
    })
    recipe = read(run / "recipe.json")
    recipe.update({
        "recorded_at": datetime.now().astimezone().isoformat(),
        "resumed_from": str(previous),
        "resume_reason": "user released host memory; preserve completed upstream work",
        "resume_cli": "direct mapped-DB actions; never use -project/-run dependency dispatch",
    })
    dump(run / "recipe.json", recipe)
    print(run)


def collect_pnr(run):
    for name in (f"{TOP}.prr", f"{TOP}_pnr.adf"):
        path = run / name
        if not path.exists() or not path.stat().st_size:
            raise RuntimeError(f"Direct PNR output missing: {name}")
    destination = run / "place_route"
    destination.mkdir(exist_ok=True)
    for pattern in ("*.prr", "*_pnr.adf", "*_plc.adf", "*_timing*.txt",
                    "clock_utilization.txt", "layers.txt", "prr.db"):
        for path in run.glob(pattern):
            shutil.copy2(path, destination / path.name)
    shutil.copy2(run / "place_route.log", destination / "run.log")
    for action, filename in (("report_timing", "timing_only"),
                             ("gen_bit_stream", "bitstream_only")):
        options = " -create_mask_file TRUE" if action == "gen_bit_stream" else ""
        script = (
            "# Explicit routed DB; no source registration or upstream flow commands.\n"
            "set_arch -family Logos -device PGL50H -speedgrade -6 -package FBG484\n"
            f'{action} -input_db_file "place_route/{TOP}_pnr.adf"'
            f" -force_to_run{options}\n"
        )
        (run / f"{filename}.tcl").write_text(script, encoding="ascii")
    print("Direct PNR outputs collected; explicit-DB timing/bitstream scripts prepared")


def check(run, tool_exit):
    errors = []
    protected_ok = read(run / "protected_inputs.json") == protected()
    if not protected_ok:
        errors.append("protected main-design files changed")
    for relative, expected in read(run / "build_inputs.json").items():
        if sha(run / relative) != expected:
            errors.append(f"build input changed: {relative}")
    required = {
        "compile": run / "compile" / f"{TOP}.cmr",
        "synthesis": run / "synthesize" / f"{TOP}.snr",
        "mapping": run / "device_map" / f"{TOP}.dmr",
        "place_route": run / "place_route" / f"{TOP}.prr",
        "timing": run / "report_timing" / f"{TOP}.rtr",
        "bitstream": run / "generate_bitstream" / f"{TOP}.sbit",
        "mask": run / "generate_bitstream" / f"{TOP}.smsk",
    }
    stages = {name: path.exists() and path.stat().st_size > 0 for name, path in required.items()}
    if not all(stages.values()):
        errors.append("missing nonempty full-flow artifacts")
    log = (run / "build.log").read_text(encoding="utf-8", errors="replace")
    fatal_lines = fatal_log_lines(log)
    if tool_exit != 0 or fatal_lines:
        errors.append("tool failure reported")
    reused_upstream = None
    if (run / "upstream_reuse.json").exists():
        reused_upstream = (read(run / "upstream_reuse.json")["artifacts"]
                           == upstream_manifest(run))
        if not reused_upstream:
            errors.append("reused compile/synthesis/mapping artifacts changed")
        if re.search(r'Process "(?:Compile|Synthesize|Synthesis|Device Map)" started', log):
            errors.append("unexpected upstream action invoked during resume")
    report = required["timing"].read_text(errors="replace") if stages["timing"] else ""
    timing_ok = "Design Summary : All Constraints Met." in report if stages["timing"] else None
    if timing_ok is None:
        errors.append("timing report unavailable; timing not evaluated")
    elif not timing_ok:
        errors.append("existing constrained timing not met")
    result = {
        "recorded_at": datetime.now().astimezone().isoformat(),
        "tool_exit_code": tool_exit, "artifacts_present": stages,
        "constrained_timing_met": timing_ok,
        "all_io_timing_signed_off": False,
        "protected_main_files_unchanged": protected_ok,
        "reused_upstream_artifacts_and_timestamps_unchanged": reused_upstream,
        "errors": errors, "fatal_log_lines": fatal_lines,
        "programmed": False, "flash_written": False, "board_verified": False,
        "stage_exit_met": False, "real_road_recognition_completed": False,
        "ready_for_authorized_rule_test_trial": not errors,
        "bitstream_path": None,
    }
    if not errors:
        delivery = run / "bitstreams"
        delivery.mkdir()
        for suffix, key in ((".sbit", "bitstream"), (".smsk", "mask")):
            shutil.copy2(required[key], delivery / f"{NAME}{suffix}")
        result["bitstream_path"] = str(delivery / f"{NAME}.sbit")
        result["bitstream_sha256"] = sha(delivery / f"{NAME}.sbit")
        result["mask_sha256"] = sha(delivery / f"{NAME}.smsk")
    dump(run / "verification.json", result)
    print(json.dumps(result, indent=2))
    if errors:
        raise SystemExit(1)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("action", choices=("prepare", "resume", "collect-pnr", "check"))
    parser.add_argument("--run", type=Path, required=True)
    parser.add_argument("--from-run", type=Path)
    parser.add_argument("--tool-exit", type=int, default=0)
    args = parser.parse_args()
    if args.action == "prepare":
        prepare(args.run.resolve())
    elif args.action == "resume":
        if args.from_run is None:
            parser.error("--from-run is required for resume")
        resume(args.run.resolve(), args.from_run.resolve())
    elif args.action == "collect-pnr":
        collect_pnr(args.run.resolve())
    else:
        check(args.run.resolve(), args.tool_exit)
