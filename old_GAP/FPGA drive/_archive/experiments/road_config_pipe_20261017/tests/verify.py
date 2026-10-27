"""Stage 1: prove pinned arithmetic/writeback equivalence and synthesis timing."""
import json
import os
from pathlib import Path
import re

import numpy as np

import prepare

HERE = prepare.HERE
OUT = HERE / "tests/output"


def clean_log(path, markers):
    text = path.read_text(encoding="utf-8", errors="replace")
    assert not re.search(r"Fatal:|\$fatal|ERROR:", text), f"Unclean simulation: {path}"
    for marker in markers:
        assert marker in text, f"Missing pass: {marker}"
    return text


def main():
    provenance = prepare.read_json(OUT / "previous_inputs.json")
    for path, value in provenance.items():
        assert prepare.digest(HERE.parent / path) == value, f"Prior input changed: {path}"
    for base in prepare.BASES.values():
        pinned = prepare.read_json(base / "verification.json")
        for table in ("source_sha256", "evidence_sha256"):
            for path, value in pinned[table].items():
                assert prepare.digest(base / path) == value
    protected = prepare.read_json(OUT / "protected_before.json")
    assert protected == prepare.ref.l0.protected_hashes()
    for manifest, root in (("tile_build_inputs.json", HERE / "tests"),
                           ("layer_build_inputs.json", HERE / "tests"), ("synthesis_inputs.json", HERE)):
        for path, value in prepare.read_json(OUT / manifest).items():
            assert prepare.digest(root / path).upper() == value, f"Build input changed: {path}"

    tile_base, layer_base = prepare.BASES["tile"], prepare.BASES["layer"]
    # Only configuration changed: RAM/MAC/quantizer/runtime FSM remain byte-identical.
    old_core = (tile_base / "source/conv_cached.v").read_text(encoding="ascii")
    new_core = (HERE / "source/conv_cached.v").read_text(encoding="ascii")
    assert old_core[old_core.index("        LOAD: begin"):] == new_core[new_core.index("        LOAD: begin"):]
    assert old_core[old_core.index("genvar lane;"):old_core.index("always @(posedge clk or negedge rst_n) begin\n    if(!rst_n) begin\n        state")] == \
        new_core[new_core.index("genvar lane;"):new_core.index("always @(posedge clk or negedge rst_n) begin\n    if(!rst_n) begin\n        state")]
    for name, base in (("conv_layer_dma.v", layer_base), ("layer_probe.v", layer_base),
                       ("conv_stream_probe.v", tile_base)):
        assert prepare.digest(HERE / "source" / name) == prepare.digest(base / "source" / name)
    assert prepare.digest(HERE / "compute.fdc") == prepare.digest(layer_base / "compute.fdc")

    tile_result = prepare.read_json(tile_base / "verification.json")
    layer_result = prepare.read_json(layer_base / "verification.json")
    # Full text identity covers every output address/index, accumulator, byte and strobe.
    for kind, names in (("tile", ("rtl_outputs.txt", "rtl_cycles.txt", "rtl_transfers.txt")),
                        ("layer", ("rtl_outputs.txt", "recovery_outputs.txt"))):
        for name in names:
            assert prepare.digest(HERE / "tests" / kind / "output" / name) == \
                prepare.digest(prepare.BASES[kind] / "tests/output" / name), f"Regression differs: {kind}/{name}"
    clean_log(HERE / "tests/tile/tile.log", [
        f"PASS: stream {tile_result['rtl_jobs']} jobs {tile_result['exact_accumulator_and_code_outputs']} exact outputs",
        "PASS: resource probe matches core cycle-for-cycle",
        "PASS: staged config 26 invalid descriptors, 4 phase resets, immutable capture and traffic exclusion"])
    cases = prepare.read_json(HERE / "tests/layer/output/cases.json")
    layer_log = clean_log(HERE / "tests/layer/layer.log", [
        f"PASS: layer_dma {len(cases)} layers {layer_result['memory_words_including_guards_verified']} memory words 18 fault cases 2 reset cases; recovery passed"])
    timings = np.loadtxt(HERE / "tests/layer/output/rtl_cycles.txt", dtype=np.int64)
    assert timings.shape == (len(cases), 9)
    for job, case in enumerate(cases):
        assert list(timings[job, [0, 2, 3, 4, 5, 6]]) == [job, case["read_words"],
            case["write_words"], case["tiles"], case["tiles"]-1, case["zero_padding_vectors"]]
        assert timings[job, 1] > 0 and timings[job, 7] > 0 and timings[job, 8] >= 50
    assert len(re.findall(r"LAYER_PASS job=", layer_log)) == len(cases)
    syn = (HERE / "synthesis.log").read_text(encoding="utf-8", errors="replace")
    snr = (HERE / "synthesize/layer_probe.snr").read_text(encoding="utf-8", errors="replace")
    dmr = (HERE / "device_map/layer_probe.dmr").read_text(encoding="utf-8", errors="replace")
    assert "Executing : dev_map successfully." in syn and not re.search(r"(?m)^E:\s", syn)
    assert "Device mapping done." in dmr and "Design Summary : All Constraints Met." in snr
    clock = re.search(r"compute_clk\s+100\.0000 MHz\s+[\d.]+ MHz\s+10\.0000\s+([\d.]+)\s+([\d.-]+)", snr)
    assert clock and float(clock[2]) >= 0
    resources = {key: float(re.search(r"\|\s+"+key+r"\s+\|\s+([\d.]+)\s+\|", dmr)[1])
                 for key in ("LUT", "FF", "DRM", "APM", "IO")}
    resources.update(synthesis_only_period_ns=float(clock[1]), synthesis_only_slack_ns=float(clock[2]),
                     routed=False, external_io_constrained=False, integrated_with_video=False,
                     scope="Staged-config core + unchanged whole-layer DMA and test-only multiplexed probe")
    chain_cycles = int(timings[-3:, 1].sum())
    result = dict(stage=1, stage_name="Configuration-path synthesis timing repair",
                  stage_acceptance_passed=True, functional_regression_passed=True, synthesis_target_10ns_passed=True,
                  previous_period_ns=layer_result["resources"]["synthesis_only_period_ns"],
                  previous_slack_ns=layer_result["resources"]["synthesis_only_slack_ns"],
                  resources=resources, tile_jobs=tile_result["rtl_jobs"],
                  exact_tile_accumulator_and_code_outputs=tile_result["exact_accumulator_and_code_outputs"],
                  tile_post_start_cycles_unchanged=True, tile_report_files_byte_identical=True,
                  layer_jobs=len(cases), exact_layer_output_bytes=layer_result["exact_output_bytes"],
                  layer_writeback_and_recovery_byte_identical=True, memory_transactions=layer_result["memory_transactions"],
                  invalid_descriptor_cases=26, configuration_phase_resets=4, immutable_capture_test=True,
                  speculative_traffic_exclusion_test=True, layer_fault_cases=18, layer_inflight_resets=2,
                  configuration_added_cycles_per_valid_tile=4,
                  real_feature_three_layer_simulated_cycles=chain_cycles,
                  real_feature_three_layer_cycle_delta=chain_cycles-layer_result["real_feature_chain"]["simulated_cycles"],
                  protected_main_files_unchanged=len(protected),
                  stages_2_to_4_started_this_round=False, board_programmed=False, new_bitstream=False,
                  deployment_approved=False, accuracy_change="None claimed or evaluated",
                  next_stage="Real vendor DDR adapter and video-priority memory arbitration",
                  limitation="Stage 1 closes only the prior synthesis violation. No routed/integrated board timing or complete road model.")
    sources = [HERE / name for name in ("source/conv_cached.v", "source/conv_stream_probe.v",
        "source/conv_layer_dma.v", "source/layer_probe.v", "tests/tile/stream_tb.v", "tests/layer/layer_tb.v",
        "tests/prepare.py", "tests/verify.py", "tests/run.ps1", "build.ps1", "flow.tcl", "compute.fdc")]
    evidence = [OUT / name for name in ("previous_inputs.json", "protected_before.json", "tile_build_inputs.json",
        "layer_build_inputs.json", "synthesis_inputs.json")]
    evidence += [HERE / path for path in ("tests/tile/tile.log", "tests/layer/layer.log", "synthesis.log",
        "synthesize/layer_probe.snr", "device_map/layer_probe.dmr",
        "tests/tile/output/rtl_outputs.txt", "tests/tile/output/rtl_cycles.txt", "tests/tile/output/rtl_transfers.txt",
        "tests/layer/output/rtl_outputs.txt", "tests/layer/output/recovery_outputs.txt", "tests/layer/output/rtl_cycles.txt")]
    result["source_sha256"] = {os.path.relpath(path, HERE): prepare.digest(path) for path in sources}
    result["evidence_sha256"] = {os.path.relpath(path, HERE): prepare.digest(path) for path in evidence}
    prepare.ref.write_json(HERE / "verification.json", result)
    print(json.dumps({key: value for key, value in result.items() if not key.endswith("sha256")}, indent=2))


if __name__ == "__main__":
    main()
