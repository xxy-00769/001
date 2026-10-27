"""Audit arithmetic, source hashes, mapped resources and explicit throughput bounds."""
import hashlib
import json
import math
from pathlib import Path
import re
import sys

import numpy as np

HERE = Path(__file__).resolve().parents[1]
BASE = HERE.parent / "road_integer_ops_20261017"
sys.path.insert(0, str(BASE))
import reference as ref


def read_json(path):
    return json.loads(Path(path).read_text(encoding="utf-8-sig"))


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def core_cycles(desc):
    dw, ci, co, k, _, _, _, _, ow, oh = desc
    groups = (co+15)//16
    terms = (1 if dw else ci)*k*k
    return 28*groups + ow*oh*(groups*(terms+8)+co)


def serial_cycles(desc):
    dw, ci, co, k, _, _, _, _, ow, oh = desc
    return 28*co + co*ow*oh*(5*(1 if dw else ci)*k*k+4)


def check_banking():
    # Exhaust every supported dimension/channel combination, not just model shapes.
    shapes = {(k, s, d, (ow-1)*s+(k-1)*d+1, (oh-1)*s+(k-1)*d+1)
              for k in range(1, 4) for s in (1, 2) for d in range(1, 9)
              for ow in range(1, 5) for oh in range(1, 5)}
    checked = 0
    max_input = max_weight = 0
    for k, s, d, iw, ih in shapes:
        for ci in range(1, 81):
            if ci*iw*ih > 32768:
                continue
            bank_input = math.ceil(ci/16)*iw*ih
            assert bank_input <= 4096
            max_input = max(max_input, bank_input)
            for dw in (False, True):
                term = (1 if dw else ci)*k*k
                for co in ([ci] if dw else range(1, 81)):
                    if co*term > 8192:
                        continue
                    bank_weight = math.ceil(co/16)*term
                    assert bank_weight <= 1024
                    assert math.ceil(co/16)*14 <= 128
                    max_weight = max(max_weight, bank_weight)
                    checked += 1
    return dict(valid_combinations=checked, maximum_input_bytes_per_bank=max_input,
                maximum_weight_bytes_per_bank=max_weight)


def main():
    out = HERE / "tests/output"
    old = BASE / "tests/output"
    cases = read_json(out / "cases.json")
    baseline = read_json(BASE / "verification.json")
    assert cases[:3214] == read_json(old / "cases.json")
    before = read_json(out / "protected_before.json")
    assert before == ref.l0.protected_hashes(), "Main source or named bitstreams changed"
    for table in ("source_sha256", "evidence_sha256"):
        for path, value in baseline[table].items():
            assert digest(BASE / path) == value, f"Serial evidence changed: {path}"
    for path, value in read_json(out / "rtl_build_inputs.json").items():
        assert digest(HERE / "tests" / path).upper() == value
    for path, value in read_json(out / "synthesis_inputs.json").items():
        assert digest(HERE / path).upper() == value
    for name, value in read_json(out / "baseline_inputs.json").items():
        assert digest(old / name) == value
        with (out / name).open("rb") as stream:
            assert hashlib.sha256(stream.read((old / name).stat().st_size)).hexdigest() == value
    with (out / "expected.hex").open(encoding="ascii") as stream:
        expected = [int(row, 16) for row in stream]
    total = 0
    with (out / "rtl_outputs.txt").open(encoding="ascii") as stream:
        for case in cases:
            seen = set()
            for _ in range(case["lengths"][3]):
                fields = stream.readline().split()
                assert len(fields) == 4 and int(fields[0]) == case["id"]
                index = int(fields[1])
                assert 0 <= index < case["lengths"][3] and index not in seen
                seen.add(index)
                assert (int(fields[2], 16) << 8) | int(fields[3], 16) == expected[case["offsets"][3]+index]
                total += 1
            assert len(seen) == case["lengths"][3]
        assert not stream.read().strip()
    assert total == len(expected)
    log = (HERE / "tests/parallel.log").read_text(encoding="utf-8", errors="replace")
    assert f"PASS: parallel {len(cases)} jobs {total} exact outputs" in log
    assert not re.search(r"Fatal:|\$fatal|ERROR:", log)
    cycles = np.loadtxt(out / "rtl_cycles.txt", dtype=np.int64)
    assert cycles.shape == (len(cases), 4)
    for case, row in zip(cases, cycles):
        assert row[0] == case["id"] and row[2] == case["lengths"][3]
        assert row[1] == core_cycles(case["descriptor"]) + row[3]
    synthesis = (HERE / "synthesis.log").read_text(encoding="utf-8", errors="replace")
    assert "Executing : dev_map successfully." in synthesis and not re.search(r"(?m)^E:\s", synthesis)
    snr = (HERE / "synthesize/conv_parallel.snr").read_text(encoding="utf-8", errors="replace")
    dmr = (HERE / "device_map/conv_parallel.dmr").read_text(encoding="utf-8", errors="replace")
    assert "Device mapping done." in dmr and "Design Summary : All Constraints Met." in snr
    timing = re.search(r"compute_clk\s+100\.0000 MHz\s+[\d.]+ MHz\s+10\.0000\s+([\d.]+)\s+([\d.-]+)", snr)
    assert timing and float(timing[2]) >= 0
    resources = {k: float(re.search(r"\|\s+"+k+r"\s+\|\s+([\d.]+)\s+\|", dmr)[1])
                 for k in ("LUT", "FF", "DRM", "APM")}
    assert resources["APM"] < 84, "No multiplier headroom for the existing video project"
    resources.update(synthesis_only_period_ns=float(timing[1]), synthesis_only_slack_ns=float(timing[2]),
                     routed=False, external_io_constrained=False, integrated_with_video=False)

    ref.l0.verify_models()
    model = ref.load_model()
    inventory = read_json(BASE / "operator_inventory.json")
    layers = []
    for row in inventory["supported"]:
        p = ref.extract_conv(model, row["name"])
        co, oh, ow = p["output_shape"]
        layer_core = layer_serial = layer_load = tiles = 0
        for y in range(0, oh, 4):
            for x in range(0, ow, 4):
                tw, th = min(4, ow-x), min(4, oh-y)
                iw = (tw-1)*p["stride"]+(p["kernel"]-1)*p["dilation"]+1
                ih = (th-1)*p["stride"]+(p["kernel"]-1)*p["dilation"]+1
                desc = [p["depthwise"], p["ci"], co, p["kernel"], p["stride"], p["dilation"], iw, ih, tw, th]
                layer_core += core_cycles(desc)
                layer_serial += serial_cycles(desc)
                layer_load += p["ci"]*iw*ih + p["weights"].size + 14*co
                tiles += 1
        layers.append(dict(name=p["name"], tiles=tiles, core_cycles=layer_core,
                           serial_core_cycles=layer_serial, load_bytes=int(layer_load)))
    ref.write_json(HERE / "layer_budget.json", layers)
    core = sum(row["core_cycles"] for row in layers)
    serial = sum(row["serial_core_cycles"] for row in layers)
    load = sum(row["load_bytes"] for row in layers)
    tiles = sum(row["tiles"] for row in layers)
    assert serial == baseline["serial_136_conv_core_cycles_without_transfer_or_stalls"]
    result = dict(rtl_jobs=len(cases), exact_accumulator_and_code_outputs=total,
                  inherited_cases=3214, new_lane_edge_cases=len(cases)-3214,
                  output_stall_cycles=int(cycles[:, 3].sum()), banking=check_banking(), resources=resources,
                  convolution_contracts=len(layers), missing_convolutions=inventory["unsupported"],
                  serial_core_cycles=serial, parallel_core_cycles=core,
                  core_cycle_speedup=serial/core, tile_count=tiles,
                  byte_load_cycles_without_stalls=load, configure_and_start_cycles=2*tiles,
                  hypothetical_100mhz_core_seconds=core/100_000_000,
                  hypothetical_100mhz_core_plus_load_seconds=(core+load+2*tiles)/100_000_000,
                  excluded="DDR latency/arbitration, output writes, missing operators/classifier, camera/display, stalls, routed timing",
                  accuracy_change="None evaluated; identical arithmetic is not semantic accuracy or a full on-board model",
                  protected_main_files_unchanged=len(before), board_programmed=False, new_bitstream=False,
                  deployment_approved=False)
    sources = [HERE / p for p in ("source/conv_parallel.v", "tests/parallel_tb.v", "tests/prepare.py", "tests/verify.py",
                                  "tests/run.ps1", "build.ps1", "flow.tcl", "compute.fdc")]
    evidence = [out / p for p in ("cases.json", "expected.hex", "rtl_outputs.txt", "rtl_cycles.txt",
                                  "rtl_build_inputs.json", "synthesis_inputs.json", "protected_before.json", "baseline_inputs.json")]
    evidence += [HERE / p for p in ("layer_budget.json", "tests/parallel.log", "synthesis.log",
                                     "synthesize/conv_parallel.snr", "device_map/conv_parallel.dmr")]
    result["source_sha256"] = {str(p.relative_to(HERE)): digest(p) for p in sources}
    result["evidence_sha256"] = {str(p.relative_to(HERE)): digest(p) for p in evidence}
    ref.write_json(HERE / "verification.json", result)
    print(json.dumps({k: v for k, v in result.items() if not k.endswith("sha256")}, indent=2))


if __name__ == "__main__":
    main()
