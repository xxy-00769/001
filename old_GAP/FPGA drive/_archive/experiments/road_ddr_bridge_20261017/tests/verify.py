"""Audit native-interface evidence; never equate simulation with board acceptance."""
import json
from pathlib import Path
import re

import prepare

HERE, OUT, PREVIOUS = prepare.HERE, prepare.OUT, prepare.PREVIOUS


def clean(path, marker):
    text = path.read_text(encoding="utf-8", errors="replace")
    assert marker in text and not re.search(r"Fatal:|\$fatal|ERROR:", text), path
    return text


def main():
    assert prepare.read_json(OUT / "protected_before.json") == prepare.protected()
    for name, value in prepare.read_json(OUT / "previous_inputs.json").items():
        assert prepare.digest(HERE.parent / name) == value
    pin = prepare.read_json(PREVIOUS / "verification.json")
    for table in ("source_sha256", "evidence_sha256"):
        for name, value in pin[table].items():
            assert prepare.digest(PREVIOUS / name) == value, f"Previous evidence changed: {name}"
    for kind in ("bridge", "layer", "partition"):
        for name, value in prepare.read_json(OUT / f"{kind}_inputs.json").items():
            assert prepare.digest(HERE / "tests" / name).upper() == value
    for name, value in prepare.read_json(OUT / "synthesis_inputs.json").items():
        assert prepare.digest(HERE / name).upper() == value
    bridge_log = clean(HERE / "tests/bridge.log", "PASS: native bridge")
    clean(HERE / "tests/partition.log", "PASS: native partition 5")
    layer_log = clean(HERE / "tests/layer.log", "PASS: native layer 29")
    unit = list(map(int, (OUT / "bridge_counts.txt").read_text().split()))
    layer = list(map(int, (OUT / "layer_counts.txt").read_text().split()))
    assert unit[1:7] == [256, 5, 5, 11, 408, 408], unit
    assert layer[:5] == [29, 518967, 74451, 49923, 74027], layer
    assert layer[5:7] == [962, 962], layer
    assert len(re.findall("NATIVE_LAYER_PASS job=", layer_log)) == 29
    assert prepare.digest(OUT / "native_layer_outputs.txt") == prepare.digest(
        PREVIOUS / "tests/layer/output/rtl_outputs.txt"), "Output reports not byte-identical"
    cycle_rows = [list(map(int, row.split())) for row in (OUT / "native_layer_cycles.txt").read_text().splitlines()]
    chain_cycles = sum(row[1] for row in cycle_rows[-3:])
    snr = (HERE / "synthesize/ddr_layer_probe.snr").read_text(encoding="utf-8", errors="replace")
    dmr = (HERE / "device_map/ddr_layer_probe.dmr").read_text(encoding="utf-8", errors="replace")
    syn = (HERE / "synthesis.log").read_text(encoding="utf-8", errors="replace")
    assert "Executing : dev_map successfully." in syn and not re.search(r"(?m)^E:\s", syn)
    assert "Device mapping done." in dmr
    clock = re.search(r"compute_clk\s+100\.0000 MHz\s+[\d.]+ MHz\s+10\.0000\s+([\d.]+)\s+([\d.-]+)", snr)
    assert clock
    resources = {key: float(re.search(r"\|\s+"+key+r"\s+\|\s+([\d.]+)\s+\|", dmr)[1])
                 for key in ("LUT", "FF", "DRM", "APM", "IO")}
    resources.update(synthesis_only_period_ns=float(clock[1]), synthesis_only_slack_ns=float(clock[2]),
                     routed=False, external_io_constrained=False,
                     scope="Stage-1 core + whole-layer DMA + native bridge + test-only multiplexed shell")
    vendor_dir = HERE / "tests/vendor_run"
    vendor_log = (vendor_dir / "console.log").read_text(encoding="utf-8", errors="replace")
    compile_log = (vendor_dir / "compile.log").read_text(encoding="utf-8", errors="replace")
    vendor_pass = "PASS: vendor DDR" in vendor_log and not re.search(r"\*\* (Error|Fatal):| ERROR:", vendor_log)
    vendor = dict(compiled="Errors: 0" in compile_log, simulation_passed=vendor_pass,
                  full_controller_phy_and_two_x16_memory_models=True,
                  optimized_primitive_model_run_passed=False,
                  simulator="ModelSim SE-64 10.7, -novopt; no PLL/PHY replacement")
    evidence = [OUT / name for name in ("previous_inputs.json", "protected_before.json",
        "bridge_inputs.json", "layer_inputs.json", "partition_inputs.json", "synthesis_inputs.json",
        "bridge_counts.txt", "layer_counts.txt", "native_layer_outputs.txt", "native_layer_cycles.txt")]
    evidence += [HERE / path for path in ("tests/bridge.log", "tests/layer.log", "tests/partition.log",
        "synthesis.log", "synthesize/ddr_layer_probe.snr", "device_map/ddr_layer_probe.dmr",
        "tests/vendor_run/console.log", "tests/vendor_run/compile.log")]
    if (vendor_dir / "previous_attempt.log").exists():
        evidence.append(vendor_dir / "previous_attempt.log")
    if vendor_pass:
        startup, operation = vendor_log.split("VENDOR_INITIALIZED", 1)
        assert not re.search(r"WARNING:.*violation", operation), "Timing warning after initialization"
        counts = list(map(int, (OUT / "vendor_counts.txt").read_text().split()))
        assert counts[0] == 256 and counts[1:3] == [136, 272], counts
        for name, value in prepare.read_json(OUT / "vendor_inputs.json").items():
            assert prepare.digest(name).upper() == value, f"Vendor input changed: {name}"
        vendor.update(tagged_transactions=counts[0], video_read_beats=counts[1], video_write_beats=counts[2],
                      native_commands=counts[3], simulated_ui_cycles=counts[4],
                      startup_memory_timing_warnings=len(re.findall(r"WARNING:.*violation", startup)),
                      post_initialization_memory_timing_warnings=0)
        evidence += [OUT / "vendor_counts.txt", OUT / "vendor_inputs.json"]
    else:
        vendor["limitation"] = "No clean vendor simulation pass; do not accept the native DDR integration."
    result = dict(stage=2, stage_name="Native DDR adapter and video-priority arbitration",
                  stage_acceptance_passed=False, implementation_and_bfm_regression_passed=True,
                  vendor=vendor, resources=resources,
                  tagged_layer_transactions=layer[2]+layer[3], exact_layer_output_bytes=layer[1],
                  layer_jobs=layer[0], protected_memory_words_verified=layer[4],
                  layer_write_reports_byte_identical=True,
                  unit_response_checks=unit[0], byte_mask_write_patterns=unit[1],
                  invalid_request_addresses=unit[2], soft_reset_cancellation_cases=unit[3],
                  native_fault_cases=unit[4], invalid_partition_cases=5,
                  unit_video_read_beats=unit[5], unit_video_write_beats=unit[6],
                  layer_video_read_beats=layer[5], layer_video_write_beats=layer[6],
                  native_bfm_layer_commands=layer[7],
                  real_feature_three_layer_simulated_cycles=chain_cycles,
                  protected_main_files_unchanged=len(prepare.protected()),
                  integrated_with_actual_camera_hdmi_fifos=False,
                  video_bandwidth_and_latency_accepted=False, board_programmed=False,
                  new_bitstream=False, complete_model=False, deployment_approved=False,
                  accuracy_change="None claimed or evaluated",
                  next_gate="Actual framebuffer/FIFO integration and contention/latency verification; remain in stage 2")
    sources = list((HERE / "source").glob("*.v"))
    sources += [HERE / name for name in ("flow.tcl", "compute.fdc", "build.ps1",
        "tests/run.ps1", "tests/run_vendor.ps1", "tests/vendor.do",
        "tests/prepare.py", "tests/verify.py", "tests/harness.vh", "tests/native_bfm.v",
        "tests/bridge_tb.v", "tests/layer_tb.v", "tests/partition_tb.v", "tests/vendor_tb.v")]
    result["source_sha256"] = {str(path.relative_to(HERE)): prepare.digest(path) for path in sources}
    result["evidence_sha256"] = {str(path.relative_to(HERE)): prepare.digest(path) for path in evidence}
    prepare.write_json(HERE / "verification.json", result)
    print(json.dumps({key: value for key, value in result.items() if not key.endswith("sha256")}, indent=2))


if __name__ == "__main__":
    main()
