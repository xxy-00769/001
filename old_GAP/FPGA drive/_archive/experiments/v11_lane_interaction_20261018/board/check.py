"""Audit saved JTAG logs and files only. Never connects to or writes a board."""
import argparse
import hashlib
import json
import re
from datetime import datetime
from pathlib import Path

EXPERIMENT = Path(__file__).resolve().parents[1]
PROJECT = EXPERIMENT.parents[1]
BUILD = EXPERIMENT / "builds/20261018_130743_866_resume_pnr"
GOOD_BITS = ("done_i", "done", "init_b", "init_complete", "wakeup_over", "pll_lock")
ERROR_BITS = ("over_temp", "overflow", "timeout", "rbcrc_err", "crc_err", "id_err")


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def states(log):
    blocks = log.split("The Status Register Code is :")[1:]
    return [{name: int(value) for value, name in
             re.findall(r"(?m)^Bit\s+\d+:\s+([01])\s+(\w+)\s*$", block)}
            for block in blocks]


def check(run, exits):
    errors = []
    logs = {}
    for name, marker in (("before", "V11_PROBE_COMMANDS_FINISHED"),
                         ("program_verify", "V11_PROGRAM_VERIFY_COMMANDS_FINISHED"),
                         ("after", "V11_PROBE_COMMANDS_FINISHED")):
        text = (run / f"{name}.log").read_text(encoding="utf-8-sig", errors="replace")
        logs[name] = text
        if (exits[name] != 0 or (run / f"{name}.stderr").stat().st_size
                or re.search(r"(?m)^\s*E:|(?:ERROR:|Error:|FATAL:|Fatal:)", text)
                or marker not in text):
            errors.append(f"{name}: tool failure or incomplete log")
        if ("The ID value is: 0x00521899" not in text
                or len(re.findall(r"(?m)^PGL50H\s*$", text)) != 1):
            errors.append(f"{name}: expected single PGL50H/ID not confirmed")
    program = logs["program_verify"]
    programmed = ("COMMAND[Program] execute successfully" in program
                  and "Executing : cfg_program -device_index 0 successfully." in program)
    verified = ("COMMAND[Verify] execute successfully" in program
                and "Executing : cfg_verify -device_index 0 successfully." in program)
    if not programmed:
        errors.append("no affirmative successful configuration download")
    if not verified:
        errors.append("no affirmative successful vendor readback verification")
    status = {name: states(text) for name, text in logs.items()}
    for name, expected_count in (("program_verify", 2), ("after", 1)):
        if len(status[name]) != expected_count:
            errors.append(f"{name}: missing status snapshots")
        for snapshot in status[name]:
            if (any(snapshot.get(key) != 1 for key in GOOD_BITS)
                    or any(snapshot.get(key) != 0 for key in ERROR_BITS)):
                errors.append(f"{name}: configuration status not healthy")
    build_result = json.loads((BUILD / "verification.json").read_text(encoding="utf-8"))
    artifact = Path(build_result["bitstream_path"])
    mask = artifact.with_suffix(".smsk")
    hashes_match = (sha(artifact) == build_result["bitstream_sha256"]
                    and sha(mask) == build_result["mask_sha256"])
    if not hashes_match:
        errors.append("bitstream or mask changed since accepted build")
    protected = json.loads((BUILD / "protected_inputs.json").read_text(encoding="utf-8"))
    changed = [name for name, expected in protected.items()
               if sha(PROJECT / name) != expected]
    result = {
        "completed_at": datetime.now().astimezone().isoformat(),
        "authorization": "current user requested normal programming; volatile JTAG only, no Flash",
        "artifact": str(artifact), "sha256": sha(artifact),
        "matching_mask": str(mask), "mask_sha256": sha(mask),
        "matching_build_files_unchanged": hashes_match,
        "tool_exit_codes": exits,
        "device": "PGL50H", "device_id": "0x00521899",
        "jtag_frequency": "1MHz",
        "programmed": programmed, "vendor_cfg_verify_passed": verified,
        "configuration_status_checked_in_new_session": not errors,
        "status_snapshots": status,
        "configuration_download_and_readback_checks_passed": not errors,
        "errors": errors,
        "protected_files_checked": len(protected),
        "protected_files_changed": changed,
        "flash_written": False, "efuse_or_keys_written": False,
        "camera_display_observed": False, "physical_buttons_tested": False,
        "board_function_verified": False, "stage_exit_met": False,
        "real_road_recognition_completed": False,
        "variant": "RULE TEST; real CMOS1 background path, synthetic rule source",
    }
    (run / "result.json").write_text(
        json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(result, indent=2))
    if errors:
        raise SystemExit(1)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--run", type=Path, required=True)
    parser.add_argument("--probe-exit", type=int, required=True)
    parser.add_argument("--program-exit", type=int, required=True)
    parser.add_argument("--postcheck-exit", type=int, required=True)
    args = parser.parse_args()
    check(args.run.resolve(), {
        "before": args.probe_exit,
        "program_verify": args.program_exit,
        "after": args.postcheck_exit,
    })
