"""Summarize successes AND rejected attempts without rewriting their evidence."""
import hashlib
import json
from pathlib import Path
import re

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def read(path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def main():
    runs = []
    for folder in sorted((HERE / "runs").iterdir()):
        if not folder.is_dir():
            continue
        item = {"directory": str(folder.relative_to(HERE))}
        log = folder / "simulation.log"
        text = log.read_text(errors="replace") if log.exists() else ""
        if folder.name == "20261017_215255_512_s1_candidate":
            item["outcome"] = "stopped_incomplete_for_fpga_arm_architecture_change"
        elif "VirtualAlloc" in text:
            item["outcome"] = "host_memory_failure_not_a_rtl_verdict"
        elif re.search(r"\*\* (Error|Fatal):", text):
            item["outcome"] = "simulation_rejected"
        elif (folder / "result.json").exists():
            item["result"] = read(folder / "result.json")
            item["outcome"] = ("framebuffer_workload_passed" if
                               item["result"]["framebuffer_integrity_passed"] else "video_rejected")
        elif (folder / "candidate.simulation.log").exists():
            original = (folder / "original.simulation.log").read_text(errors="replace")
            candidate = (folder / "candidate.simulation.log").read_text(errors="replace")
            item["outcome"] = ("directed_fix_passed" if
                               "REJECT: premature" in original and "PASS: final-return" in candidate
                               else "directed_fix_rejected")
        else:
            item["outcome"] = "incomplete"
        captured = read(folder / "inputs.json") if (folder / "inputs.json").exists() else {}
        item["captured_inputs_match_current"] = all(
            (ROOT / name).exists() and digest(ROOT / name) == value
            for name, value in captured.items())
        item["evidence_sha256"] = {
            p.name: digest(p) for p in folder.iterdir()
            if p.is_file() and p.suffix in (".json", ".log", ".txt")}
        runs.append(item)

    preserved = 0
    for name in ("road_config_pipe_20261017", "road_ddr_bridge_20261017"):
        base = HERE.parent / name
        pin = read(base / "verification.json")
        for table in ("source_sha256", "evidence_sha256"):
            for relative, expected in pin[table].items():
                assert digest(base / relative).lower() == expected.lower(), relative
    for relative, expected in read(
            HERE.parent / "road_ddr_bridge_20261017/tests/output/protected_before.json").items():
        assert digest(ROOT / relative).lower() == expected.lower(), relative
        preserved += 1
    result = dict(
        stage=2, stage_acceptance_passed=False,
        continuation_status="historical_research_frozen",
        current_route="FPGA plus external ARM; new stage 1 hardware/interface confirmation",
        resume_as_prerequisite=False,
        scope="Actual framebuffer + vendor dual-clock RAM primitives + native bridge + memory BFM",
        actual_camera_hardware=False, actual_hdmi_hardware=False,
        protected_main_files_unchanged=preserved,
        previous_stage_source_and_evidence_unchanged=True,
        new_bitstream=False, board_programmed=False, flash_written=False,
        complete_model=False, accuracy_evaluated=False, deployment_approved=False,
        remaining_gates=[
            "Continuous integrated encrypted DDR controller/PHY/memory run",
            "In-flight reset, accelerator cancellation and initialization-loss integration",
            "Missing native-return watchdog/recovery contract",
            "Camera/display rate mismatch, phase drift and frame ownership lifecycle",
            "Synthesis/timing of the isolated integration fixes; board acceptance is later stage 4"
        ], runs=runs)
    files = [p for p in HERE.rglob("*") if p.is_file() and "runs" not in p.relative_to(HERE).parts
             and p.name != "verification.json" and "__pycache__" not in p.parts]
    result["source_sha256"] = {str(p.relative_to(HERE)): digest(p) for p in files}
    (HERE / "verification.json").write_text(
        json.dumps(result, indent=2, ensure_ascii=True) + "\n", encoding="ascii")
    print(json.dumps({
        "stage_acceptance_passed": False,
        "protected_main_files_unchanged": preserved,
        "runs": [{"directory": r["directory"], "outcome": r["outcome"],
                  "captured_inputs_match_current": r["captured_inputs_match_current"]} for r in runs]
    }, indent=2))


if __name__ == "__main__":
    main()
