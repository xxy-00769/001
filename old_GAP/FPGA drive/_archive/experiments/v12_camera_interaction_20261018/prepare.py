"""Prepare an isolated camera interaction run; never access board hardware."""
import argparse
import importlib.util
import json
import shutil
from datetime import datetime
from pathlib import Path

EXPERIMENT = Path(__file__).resolve().parent
PROJECT = EXPERIMENT.parents[1]
V11 = PROJECT / "experiments/v11_lane_interaction_20261018"
NAME = "12_lane_interaction_camera_candidate_cmos1"


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


build = load("v11_build", V11 / "build.py")
generator = load("v11_generator", V11 / "tests/prepare.py")


def protected():
    result = build.protected()
    for folder in (V11 / "source", V11 / "tests",
                   V11 / "builds/20261018_130743_866_resume_pnr"):
        for path in folder.rglob("*"):
            if path.is_file() and "__pycache__" not in path.parts:
                result[path.relative_to(PROJECT).as_posix()] = build.sha(path)
    return result


def prepare(run):
    run.mkdir(parents=True, exist_ok=False)
    build.dump(run / "protected_inputs.json", protected())
    old = build.read(V11 / "runs/20261018_104949_462/inputs.json")
    for relative, info in old.items():
        if ("/v11_lane_interaction_" in relative and relative.endswith((".v", ".sv"))):
            if build.sha(PROJECT / relative) != info["sha256"]:
                raise RuntimeError(f"v11 regression input changed: {relative}")
    generator.generate(run, rule_test=0, physical_keys_confirmed=True)
    shutil.copytree(PROJECT / "source", run / "source")
    shutil.copy2(run / "generated/hdmi_ddr_ov5640_top.v",
                 run / "source/rtl/hdmi_ddr_ov5640_top.v")
    for path in (V11 / "source").glob("*.v"):
        shutil.copy2(path, run / "source/rtl" / path.name)
    # A source detector reset must also invalidate the receiver's frame epoch.
    top_path = run / "source/rtl/hdmi_ddr_ov5640_top.v"
    text = top_path.read_text(encoding="utf-8")
    text = generator.replace_once(text, ".reset_n(rstn_out && ddr_init_done)",
                                  ".reset_n(rstn_out && ddr_init_done && img_rstn)")
    top_path.write_text(text, encoding="utf-8")
    # Preserve the handshake and bundled-data registers for mapped CDC inspection.
    cdc_path = run / "source/rtl/lane_snapshot_cdc.v"
    text = cdc_path.read_text(encoding="ascii")
    text = generator.replace_once(
        text, "reg req, ack, ack_meta, ack_sync, req_meta, req_sync;",
        "reg req, ack, ack_meta, ack_sync, req_meta, req_sync /* synthesis syn_preserve = 1 */;")
    text = generator.replace_once(text, "reg [255:0] held;",
                                  "reg [255:0] held /* synthesis syn_preserve = 1 */;")
    cdc_path.write_text(text, encoding="ascii")
    original = (PROJECT / "hdmi_ddr_ov5640_top.fdc").read_text(encoding="utf-8-sig")
    keys = (V11 / "hardware_review/keys_reference.fdc").read_text(encoding="ascii")
    # Keep all inherited clocks/exceptions; the build is not accepted until the
    # new max-delay paths are actually reported (clock-group masking is a risk).
    cdc = """
# v12 mailbox bundled data: less than the inherited 14.8148ns display period.
# Request is synchronized for two destination edges before payload capture.
set_max_delay -datapath_only -from [get_cells -hierarchical {*u_lane_local_ui*g_camera*mailbox*held*}] -to [get_cells -hierarchical {*u_lane_local_ui*g_camera*mailbox*dst_snapshot*}] 14.0
"""
    (run / "hdmi_ddr_ov5640_top.fdc").write_text(original + "\n" + keys + cdc,
                                                encoding="utf-8")
    flow = """# Isolated v12 camera candidate, no board or Flash commands.
foreach source [glob source/rtl/*.v] { add_design $source }
add_design "source/rtl/pll/pll.idf"
add_design "source/rtl/wr_fram_buf/wr_fram_buf.idf"
add_design "source/rtl/rd_fram_buf/rd_fram_buf.idf"
add_design "source/rtl/DDR3_50H/DDR3_50H.idf"
add_constraint "hdmi_ddr_ov5640_top.fdc"
set_arch -family Logos -device PGL50H -speedgrade -6 -package FBG484
compile -top_module hdmi_ddr_ov5640_top
synthesize -ads -selected_syn_tool_opt 2
dev_map
"""
    (run / "map.tcl").write_text(flow, encoding="ascii")
    (run / "pnr.tcl").write_text(
        'set_arch -family Logos -device PGL50H -speedgrade -6 -package FBG484\n'
        'pnr -input_db_file "device_map/hdmi_ddr_ov5640_top_map.adf" -force_to_run '
        '-optimize_multi_corner_timing -fix_hold_violation '
        '-fix_hold_violation_iterations 16 -fix_hold_violation_threshold 200 '
        '-fix_hold_violation_in_route TRUE -fix_hold_violation_threshold_for_clk_tree 200\n',
        encoding="ascii")
    (run / "fixtures").mkdir()
    for name in ("frame_00.hex", "frame_05.hex", "frame_07.hex", "snapshots.hex"):
        shutil.copy2(PROJECT / "tests/output/adas" / name, run / "fixtures" / name)
    build.dump(run / "recipe.json", {
        "recorded_at": datetime.now().astimezone().isoformat(),
        "variant": "LOCAL CANDIDATE", "self_test": 0, "local_rule_test": 0,
        "video": "real CMOS1 -> unchanged img_proc/DDR -> HDMI",
        "rule_source": "existing v8 image-space heuristic; not semantic recognition",
        "reset_change": "img_rstn also resets mailbox and receiver epoch",
        "cdc_change": "preserve handshake/held registers; require reported bundle max-delay",
        "new_build_required": "camera mailbox was optimized out of v11 RULE TEST mapping",
        "programmed": False, "flash_written": False,
    })
    paths = list((run / "source").rglob("*")) + list((run / "fixtures").glob("*"))
    paths += [run / "hdmi_ddr_ov5640_top.fdc", run / "map.tcl", run / "pnr.tcl",
              EXPERIMENT / "tests/camera_pipeline_tb.sv"]
    build.dump(run / "inputs.json", {str(p.resolve()): build.sha(p)
                                    for p in paths if p.is_file()})
    print(run)


def verify(run):
    if build.read(run / "protected_inputs.json") != protected():
        raise RuntimeError("Protected source or prior build changed")
    for path, sha in build.read(run / "inputs.json").items():
        if build.sha(Path(path)) != sha:
            raise RuntimeError(f"Changed test/build input: {path}")
    logs = {}
    for name in ("camera_pipeline", "cdc"):
        path = run / f"{name}.simulation.log"
        text = path.read_text(encoding="utf-8", errors="replace")
        if f"PASS {name}:" not in text or "** Error:" in text or "** Fatal:" in text:
            raise RuntimeError(f"Missing clean simulation PASS: {name}")
        logs[name] = {"passed": True, "log_sha256": build.sha(path)}
    result = {
        "recorded_at": datetime.now().astimezone().isoformat(),
        "code_implemented": True, "tests": logs, "protected_inputs_unchanged": True,
        "test_input": "six RGB fixture frames; actual img_proc, synthetic scenes",
        "unchanged_v11_tests_reused": ["buttons", "control", "rule_source", "overlay", "local_ui"],
        "reused_evidence": str(V11 / "runs/20261018_104949_462"),
        "synthesis": False, "place_route": False, "physical_cdc_signoff": False,
        "bitstream_generated": False, "programmed": False, "flash_written": False,
        "board_verified": False, "stage_exit_met": False,
        "real_road_recognition_completed": False,
    }
    build.dump(run / "simulation_verification.json", result)
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("action", choices=("prepare", "verify"))
    parser.add_argument("--run", required=True, type=Path)
    args = parser.parse_args()
    {"prepare": prepare, "verify": verify}[args.action](args.run.resolve())
