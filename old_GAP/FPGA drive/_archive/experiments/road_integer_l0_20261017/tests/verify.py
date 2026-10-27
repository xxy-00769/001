"""Check actual RTL outputs against image references and record measured PDS resources."""
import json
from pathlib import Path
import re
import sys

import numpy as np

HERE = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(HERE))
import reference as ref


def main():
    output = HERE / "tests/output"
    metadata = json.loads((output / "reference.json").read_text(encoding="utf-8"))
    network = json.loads((output / "network_check.json").read_text(encoding="utf-8"))
    assert len(network["records"]) == 14 and network["same_candidate_decisions"]
    cases = json.loads((output / "cases.json").read_text(encoding="utf-8"))
    before = json.loads((output / "protected_before.json").read_text(encoding="utf-8"))
    assert before == ref.protected_hashes(), "Main source or named bitstream changed"
    assert ref.hash_file(HERE / "source/layer0_params.v") == metadata["rom_sha256"]
    assert ref.hash_file(ref.MODEL_DIR / "model_provenance.json") == metadata["model_provenance_sha256"]
    ref.verify_models()
    images = {}
    for row in metadata["records"]:
        with np.load(output / f"{row['id']}_reference.npz") as arrays:
            images[row["id"]] = {key: arrays[key].copy() for key in arrays.files}
        arrays = images[row["id"]]
        error = np.abs(arrays["quantized"].astype(np.int16) - arrays["model_codes"].astype(np.int16))
        assert int(error.max()) == row["model_code_max_abs_error"] <= 1
        assert int(np.count_nonzero(error)) == row["model_code_differences"]
    rebuilt = {name: np.zeros((16, 96, 160), dtype=np.uint8) for name in ("legacy_road_3", "negative_shelf_dark")}
    stored = {name: np.full(16*96*160, 0xA5, dtype=np.uint8) for name in rebuilt}
    seen = {name: set() for name in rebuilt}
    jobs = [0] + list(range(len(cases)))
    count = 0
    with (output / "rtl_outputs.txt").open(encoding="ascii") as stream:
        for number in jobs:
            case = cases[number]
            tx, ty = case["tile_x"], case["tile_y"]
            arrays = images[case["image"]]
            expected_acc = arrays["accumulator"][:, ty*8:ty*8+8, tx*8:tx*8+8].reshape(-1)
            expected_q = arrays["quantized"][:, ty*8:ty*8+8, tx*8:tx*8+8].reshape(-1)
            actual_q = np.empty(1024, dtype=np.uint8)
            for i in range(1024):
                fields = stream.readline().split()
                assert len(fields) == 4
                case_id, index = map(int, fields[:2])
                acc, q = int(fields[2], 16), int(fields[3], 16)
                if acc & 0x80000000:
                    acc -= 1 << 32
                assert case_id == number and index == i
                assert acc == int(expected_acc[i]) and q == int(expected_q[i]), (number, i, acc, q)
                actual_q[i] = q
                count += 1
            np.testing.assert_array_equal(ref.replay_plan(arrays["bgr"], case["plan"]), ref.tile(arrays["bgr"], tx, ty))
            if case["image"] in rebuilt:
                assert (tx, ty) not in seen[case["image"]]
                seen[case["image"]].add((tx, ty))
                rebuilt[case["image"]][:, ty*8:ty*8+8, tx*8:tx*8+8] = actual_q.reshape(16, 8, 8)
                ref.replay_writes(stored[case["image"]], actual_q, case["write_plan"])
        assert not stream.read().strip(), "Unexpected trailing RTL outputs"
    for name in rebuilt:
        assert len(seen[name]) == 240
        np.testing.assert_array_equal(rebuilt[name], images[name]["quantized"])
        np.testing.assert_array_equal(stored[name].reshape(16, 96, 160), images[name]["quantized"])
    log = (HERE / "tests/layer0.log").read_text(encoding="utf-8", errors="replace")
    assert f"PASS: {len(jobs)} jobs, {count} bit-exact outputs" in log
    assert not re.search(r"Fatal:|\$fatal|ERROR:", log)
    cycles = np.loadtxt(output / "rtl_cycles.txt", dtype=np.int64)
    np.testing.assert_array_equal(cycles[:, 0], jobs)
    assert np.all(cycles[:, 2] == 1024) and np.all(cycles[:, 3] > 0)
    # No-stall compute is 27 synchronous reads + 27 MAC cycles + quantize + consume.
    assert np.all(cycles[:, 1] == 1024 * 56 + cycles[:, 3])
    snr = HERE / "synthesize/layer0_tile.snr"
    dmr = HERE / "device_map/layer0_tile.dmr"
    synthesis_log = HERE / "synthesis.log"
    assert snr.exists() and dmr.exists() and synthesis_log.exists(), "Run standalone PDS synthesis/device mapping"
    build_log = synthesis_log.read_text(encoding="utf-8", errors="replace")
    assert "Executing : dev_map successfully." in build_log and not re.search(r"(?m)^E:\s", build_log)
    content = snr.read_text(encoding="utf-8", errors="replace")
    resources = {}
    for name, pattern in (("LUTs", r"Total LUTs:\s+([\d.]+)"), ("registers", r"Total Registers:\s+([\d.]+)"),
                          ("DRM18K", r"Total DRM18K\s*=\s*([\d.]+)"), ("APMs", r"Total APMs\s*=\s*([\d.]+)")):
        match = re.search(pattern, content)
        assert match, name
        resources[name] = float(match.group(1))
    mapped = {}
    mapped_text = dmr.read_text(encoding="utf-8", errors="replace")
    assert "Device mapping done." in mapped_text
    for name in ("LUT", "FF", "DRM", "APM"):
        match = re.search(r"\|\s+" + name + r"\s+\|\s+([\d.]+)\s+\|", mapped_text)
        assert match, name
        mapped[name] = float(match.group(1))
    total = sum(r["first_layer_output_elements"] for r in metadata["records"])
    summary = {"reference_images_and_patterns": len(images), "reference_feature_values": total,
               "reference_vs_model_max_code_error": max(r["model_code_max_abs_error"] for r in metadata["records"]),
               "reference_vs_model_differing_codes": sum(r["model_code_differences"] for r in metadata["records"]),
               "rtl_jobs": len(jobs), "rtl_bit_exact_outputs": count,
               "full_frame_first_layer_outputs_reassembled": list(rebuilt),
               "backpressure_hold_cycles": int(cycles[:, 3].sum()),
               "compute_cycles_per_tile_no_stall": 1024 * 56,
               "compute_cycles_per_frame_no_stall": 240 * 1024 * 56,
               "frame_input_read_plan_bytes": metadata["full_frame_planned_read_bytes"],
               "frame_feature_write_bus_plan_bytes": metadata["full_frame_planned_write_bus_bytes"],
               "frame_input_payload_bytes": metadata["input_frame_bytes"],
               "frame_feature_output_bytes": metadata["output_frame_bytes"],
               "input_lut_codes_verified": 256, "ddr_plan_replayed_for_tiles": len(cases),
               "first_layer_substitution_cpu_regression_images": len(network["records"]),
               "first_layer_substitution_same_masks": network["same_accepted_masks"],
               "network_cut_control_same_masks": network["same_cut_control_masks"],
               "synthesis_resources": resources, "device_mapping_resources": mapped,
               "main_files_unchanged": len(before),
               "scope": "First convolution + bias + ReLU + requantization only. Not full model or DDR RTL, no PNR/timing or board test.",
               "source_sha256": {str(p.relative_to(HERE)): ref.hash_file(p) for p in [
                   HERE / "reference.py", HERE / "source/layer0_params.v", HERE / "source/layer0_tile.v",
                   HERE / "tests/generate.py", HERE / "tests/test_reference.py", HERE / "tests/layer0_tb.v",
                   HERE / "tests/verify.py", HERE / "tests/network_check.py", HERE / "tests/precision_audit.py", HERE / "tests/run.ps1", HERE / "flow.tcl"]},
               "evidence_sha256": {str(p.relative_to(HERE)): ref.hash_file(p) for p in [
                   HERE / "precision_audit.json", HERE / "q30_reference.json", HERE / "q30_network_check.json",
                   output / "reference.json", output / "network_check.json", output / "rtl_outputs.txt", output / "rtl_cycles.txt", snr, dmr, synthesis_log]}}
    ref.write_json(HERE / "verification.json", summary)
    print(json.dumps(summary, indent=2))


if __name__ == "__main__":
    main()
