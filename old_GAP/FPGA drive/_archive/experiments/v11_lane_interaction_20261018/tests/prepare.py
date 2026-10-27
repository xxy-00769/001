"""Freeze inputs, generate an isolated top draft, and record bounded evidence."""
import argparse
import hashlib
import json
import shutil
from datetime import datetime
from pathlib import Path

EXPERIMENT = Path(__file__).resolve().parents[1]
PROJECT = EXPERIMENT.parents[1]
TESTS = ("buttons", "control", "cdc", "rule_source", "overlay", "local_ui")


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def inputs():
    protected = [p for p in (PROJECT / "source").rglob("*") if p.is_file()]
    protected += [p for p in (PROJECT / "bitstreams").rglob("*") if p.is_file()]
    protected += [PROJECT / p for p in ("flow.tcl", "hdmi_ddr_ov5640_top.fdc",
                                       "HDMI_DDR3_OV5640.pds")]
    own = list((EXPERIMENT / "source").glob("*.v"))
    own += list((EXPERIMENT / "tests").glob("*.*"))
    return {str(p.relative_to(PROJECT)).replace("\\", "/"):
            {"sha256": digest(p), "size": p.stat().st_size}
            for p in sorted(protected + own)}


def replace_once(text, old, new):
    if text.count(old) != 1:
        raise ValueError(f"Top anchor must occur once: {old!r}")
    return text.replace(old, new, 1)


def generate(run, rule_test=0, physical_keys_confirmed=False):
    raw = (PROJECT / "source/rtl/hdmi_ddr_ov5640_top.v").read_bytes()
    try:
        top = raw.decode("utf-8-sig")
        encoding = "utf-8"
    except UnicodeDecodeError:
        top = raw.decode("gb18030")
        encoding = "gb18030"
    top = top.replace("\r\n", "\n")
    top = replace_once(top, "parameter SELF_TEST           = 0",
                       f"parameter SELF_TEST           = 0,\n    parameter LOCAL_RULE_TEST     = {int(rule_test)}")
    top = replace_once(top, "\tinput                                sys_clk",
                       "    input [3:0] local_key_n,\n\tinput                                sys_clk")
    top = replace_once(top, "    wire [15:0] proc_rgb;",
                       "    wire [15:0] proc_rgb;\n"
                       "    wire local_adas_valid;\n    wire [255:0] local_adas_snapshot;\n"
                       "    wire de_o, vs_o, hs_o;")
    top = replace_once(top, ".vs_out  (  proc_vs       )",
                       ".vs_out  (  proc_vs       ),\n"
                       "        .adas_valid(local_adas_valid),\n"
                       "        .adas_snapshot(local_adas_snapshot)")
    anchor = "     always@(posedge pix_clk) begin"
    ui = """    // Draft only: local_key_n has NO verified physical pin mapping.
    wire [15:0] local_rgb565;
    lane_local_ui #(.RULE_TEST(LOCAL_RULE_TEST)) u_lane_local_ui (
        .reset_n(rstn_out && ddr_init_done),
        .src_clk(pclk_in_test), .src_valid(local_adas_valid),
        .src_snapshot(local_adas_snapshot), .pix_clk(pix_clk),
        .de(de_o), .vs(vs_o), .rgb_in(o_rgb565), .key_n(local_key_n),
        .rgb_out(local_rgb565),
        .requested_direction(), .effective_direction(), .decision(),
        .fresh(), .alarm(), .source_frame(),
        .dropped_snapshots(), .rejected_results()
    );

"""
    if physical_keys_confirmed:
        ui = ui.replace("// Draft only: local_key_n has NO verified physical pin mapping.",
                        "// MES50HP KEY1..4: K18/L15/J17/K16, active-low; user confirmed board model.")
    top = replace_once(top, anchor, ui + anchor)
    for sl in ("15:11", "10:5", "4:0"):
        top = replace_once(top, f"o_rgb565[{sl}]", f"local_rgb565[{sl}]")
    generated = run / "generated"
    generated.mkdir()
    (generated / "hdmi_ddr_ov5640_top.v").write_text(top, encoding="utf-8")
    (generated / "integration.json").write_text(json.dumps({
        "status": "top_ready_for_isolated_build" if physical_keys_confirmed
        else "draft_blocked_by_unconfirmed_key_pins",
        "input_top_encoding": encoding,
        "input_top_sha256": hashlib.sha256(raw).hexdigest(),
        "output_top_sha256": digest(generated / "hdmi_ddr_ov5640_top.v"),
        "key_order": ["left", "right", "force", "cancel"],
        "rule_test": int(rule_test),
        "physical_board_model_user_confirmed": physical_keys_confirmed,
        "active_level_assumption": "active-low; verify schematic before physical build",
        "new_constraints_generated": False, "bitstream_build_enabled": False,
        "vendor_elaboration": False, "timing_signoff": False,
    }, indent=2) + "\n", encoding="utf-8")


def verify(run):
    frozen = json.loads((run / "inputs.json").read_text(encoding="utf-8"))
    if frozen != inputs():
        raise RuntimeError("Inputs changed during run")
    results = {}
    for name in TESTS:
        p = run / f"{name}.simulation.log"
        log = p.read_text(encoding="utf-8", errors="replace")
        if f"PASS {name}:" not in log or "** Error:" in log or "** Fatal:" in log:
            raise RuntimeError(f"Missing clean PASS: {name}")
        results[name] = {"passed": True, "log_sha256": digest(p)}
    from PIL import Image
    previews = []
    for p in sorted(run.glob("overlay_*.ppm")):
        out = p.with_suffix(".png")
        with Image.open(p) as image:
            image.save(out)
        previews.append(out.name)
    evidence = {
        "recorded_at": datetime.now().astimezone().isoformat(),
        "scope": "local lane-rule interaction; synthetic inputs only",
        "tests": results, "protected_inputs_unchanged": True,
        "generated_top_syntax": True,
        "whole_design_elaboration": False, "synthesis": False,
        "place_route": False, "physical_cdc_timing_signoff": False,
        "bitstream_generated": False, "programmed": False, "flash_written": False,
        "real_camera_rule_accuracy_evaluated": False,
        "board_verified": False, "stage_exit_met": False,
        "blocker": "actual PCB/button schematic and four verified pin/level assignments",
        "previews": previews,
        "simulation_reuse": json.loads((run / "simulation_reuse.json").read_text())
        if (run / "simulation_reuse.json").exists() else None,
    }
    (run / "verification.json").write_text(
        json.dumps(evidence, indent=2) + "\n", encoding="utf-8")
    print(f"PASS evidence: {len(frozen)} unchanged inputs; syntax-only top; no bitstream")


def reuse_tests(run, previous):
    old = json.loads((previous / "inputs.json").read_text(encoding="utf-8"))
    current = inputs()
    relevant = lambda records: {
        name: info for name, info in records.items()
        if name.startswith(str(EXPERIMENT.relative_to(PROJECT)).replace("\\", "/") + "/")
        and name.endswith((".v", ".sv"))
    }
    if relevant(old) != relevant(current):
        raise RuntimeError("Cannot reuse: RTL/testbench changed")
    copied = {}
    for name in TESTS:
        path = previous / f"{name}.simulation.log"
        log = path.read_text(encoding="utf-8", errors="replace")
        if f"PASS {name}:" not in log or "** Error:" in log or "** Fatal:" in log:
            raise RuntimeError(f"Cannot reuse failed test: {name}")
        shutil.copy2(path, run / path.name)
        copied[path.name] = digest(path)
    for path in previous.glob("overlay_*.ppm"):
        shutil.copy2(path, run / path.name)
        copied[path.name] = digest(path)
    (run / "simulation_reuse.json").write_text(json.dumps({
        "from": str(previous.resolve()), "reason": "only top generator declaration fix",
        "rtl_and_testbench_hashes_identical": True,
        "rerun_simulations": 0, "copied_evidence": copied,
    }, indent=2) + "\n", encoding="utf-8")
    print("Reused six matching PASS logs; no unchanged simulations repeated")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--run", type=Path, required=True)
    parser.add_argument("--verify", action="store_true")
    parser.add_argument("--reuse-tests-from", type=Path)
    args = parser.parse_args()
    if args.verify:
        verify(args.run)
    else:
        (args.run / "inputs.json").write_text(
            json.dumps(inputs(), indent=2) + "\n", encoding="utf-8")
        generate(args.run)
        if args.reuse_tests_from:
            reuse_tests(args.run, args.reuse_tests_from)


if __name__ == "__main__":
    main()
