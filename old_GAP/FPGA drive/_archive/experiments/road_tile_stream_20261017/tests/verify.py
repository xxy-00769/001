"""Verify stream/cache behavior and budget only the implemented arithmetic path."""
import hashlib
import json
from pathlib import Path
import re
import sys

import numpy as np

HERE = Path(__file__).resolve().parents[1]
BASE = HERE.parent / "road_parallel_conv_20261017"
OPS = HERE.parent / "road_integer_ops_20261017"
sys.path.insert(0, str(OPS))
import reference as ref


def read_json(path):
    return json.loads(Path(path).read_text(encoding="utf-8-sig"))


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def core_cycles(d):
    dw, ci, co, k, _, _, _, _, ow, oh = d
    return 28*((co+15)//16) + ow*oh*(((co+15)//16)*((1 if dw else ci)*k*k+8)+co)


def check_vectors(out, cases, rows):
    arrays = [np.loadtxt(out / name, dtype=np.uint8, converters=lambda v: int(v, 16))
              for name in ("inputs.hex", "weights.hex", "coefficients.hex")]
    words = [int(line, 16) for line in (out / "vectors.hex").read_text(encoding="ascii").splitlines()]
    keys, previous_key, consumed = {}, None, 0
    for case, row in zip(cases, rows):
        dw, ci, co, k, *_ = case["descriptor"]
        data = [a[start:start+length] for a, start, length in zip(arrays, case["offsets"], case["lengths"])]
        key = hashlib.sha256(bytes([dw, ci, co, k])+data[1].tobytes()+data[2].tobytes()).hexdigest()
        assert row["id"] == case["id"] and row["cache_key"] == key and row["reuse"] == int(key==previous_key)
        assert keys.setdefault(row["tag"], key) == key
        previous_key = key
        for bank, channels in enumerate((ci, co, co)):
            plane = len(data[bank])//channels
            assert row["offsets"][bank] == consumed
            assert row["lengths"][bank] == ((channels+15)//16)*plane
            for address in range(row["lengths"][bank]):
                word = words[consumed]; consumed += 1
                group, pos = divmod(address, plane)
                count = min(16, channels-group*16)
                assert word >> 128 == (1 << count)-1
                for lane in range(count):
                    assert ((word >> (lane*8)) & 255) == int(data[bank][(group*16+lane)*plane+pos])
    assert consumed == len(words)
    return consumed


def model_budget():
    ref.l0.verify_models()
    model = ref.load_model()
    inventory = read_json(OPS / "operator_inventory.json")
    layers = []
    for row in inventory["supported"]:
        p = ref.extract_conv(model, row["name"])
        co, oh, ow = p["output_shape"]
        ci, k, stride, dilation = p["ci"], p["kernel"], p["stride"], p["dilation"]
        weight_bytes = int(p["weights"].size)+14*co
        weight_beats = ((co+15)//16)*((1 if p["depthwise"] else ci)*k*k+14)
        core = feature_bytes = feature_beats = tiles = 0
        for y in range(0, oh, 4):
            for x in range(0, ow, 4):
                tw, th = min(4, ow-x), min(4, oh-y)
                iw, ih = (tw-1)*stride+(k-1)*dilation+1, (th-1)*stride+(k-1)*dilation+1
                desc = [p["depthwise"], ci, co, k, stride, dilation, iw, ih, tw, th]
                core += core_cycles(desc)
                feature_bytes += ci*iw*ih
                feature_beats += ((ci+15)//16)*iw*ih
                tiles += 1
        layers.append(dict(name=p["name"], tiles=tiles, core_cycles=core, input_bytes=feature_bytes,
                           input_vector_beats=feature_beats, one_layer_weight_coefficient_bytes=weight_bytes,
                           one_layer_weight_coefficient_beats=weight_beats,
                           byte_fresh_load_cycles=feature_bytes+tiles*weight_bytes,
                           byte_cached_load_cycles=feature_bytes+weight_bytes,
                           vector_fresh_load_cycles=feature_beats+tiles*weight_beats,
                           vector_cached_load_cycles=feature_beats+weight_beats))
    ref.write_json(HERE / "layer_budget.json", layers)
    sums = {key: sum(row[key] for row in layers) for key in layers[0] if key!="name"}
    old = read_json(BASE / "verification.json")
    assert sums["core_cycles"] == old["parallel_core_cycles"]
    assert sums["byte_fresh_load_cycles"] == old["byte_load_cycles_without_stalls"]
    sums["configure_and_start_cycles"] = 2*sums["tiles"]
    sums["hypothetical_100mhz_seconds"] = {
        mode: (sums["core_cycles"]+sums[f"{mode}_load_cycles"]+sums["configure_and_start_cycles"])/100_000_000
        for mode in ("byte_fresh", "byte_cached", "vector_fresh", "vector_cached")}
    sums["hypothetical_vector_cached_bus_bytes"] = 16*sums["vector_cached_load_cycles"]
    sums["load_cycle_reduction"] = sums["byte_fresh_load_cycles"]/sums["vector_cached_load_cycles"]
    return sums, inventory["unsupported"]


def main():
    out = HERE / "tests/output"
    cases, rows = read_json(out / "cases.json"), read_json(out / "vector_cases.json")
    previous = read_json(BASE / "verification.json")
    for table in ("source_sha256", "evidence_sha256"):
        for path, value in previous[table].items():
            assert digest(BASE / path) == value, f"Previous evidence changed: {path}"
    assert cases[:3281] == read_json(BASE / "tests/output/cases.json")
    assert len(cases) == len(rows) == 3285
    protected = read_json(out / "protected_before.json")
    assert protected == ref.l0.protected_hashes()
    for path, value in read_json(out / "rtl_build_inputs.json").items():
        assert digest(HERE / "tests" / path).upper() == value
    for path, value in read_json(out / "synthesis_inputs.json").items():
        assert digest(HERE / path).upper() == value
    for name, value in read_json(out / "previous_inputs.json").items():
        assert digest(BASE / "tests/output" / name) == value
        if name.endswith(".hex") or name=="descriptors.txt":
            with (out / name).open("rb") as stream:
                assert hashlib.sha256(stream.read((BASE / "tests/output" / name).stat().st_size)).hexdigest() == value
    vector_words = check_vectors(out, cases, rows)
    expected = [int(line, 16) for line in (out / "expected.hex").read_text(encoding="ascii").splitlines()]
    total, jobs = 0, 3*len(cases)
    with (out / "rtl_outputs.txt").open(encoding="ascii") as stream:
        for job in range(jobs):
            case = cases[job % len(cases)]
            seen = set()
            for _ in range(case["lengths"][3]):
                fields = stream.readline().split()
                assert len(fields)==4 and int(fields[0])==job
                index = int(fields[1])
                assert 0 <= index < case["lengths"][3] and index not in seen
                seen.add(index)
                actual = (int(fields[2], 16) << 8) | int(fields[3], 16)
                assert actual == expected[case["offsets"][3]+index]
                total += 1
        assert not stream.read().strip()
    assert total == 3*len(expected)
    cycles = np.loadtxt(out / "rtl_cycles.txt", dtype=np.int64)
    transfers = np.loadtxt(out / "rtl_transfers.txt", dtype=np.int64)
    assert cycles.shape == (jobs, 4) and transfers.shape == (jobs, 6)
    for job, (timing, transfer) in enumerate(zip(cycles, transfers)):
        phase, c = divmod(job, len(cases))
        case, row = cases[c], rows[c]
        wide = int(phase==1 or (phase==2 and c%2==1))
        reuse = int(phase==2 and row["reuse"])
        byte_count = case["lengths"][0]+(0 if reuse else sum(case["lengths"][1:3]))
        beat_count = row["lengths"][0]+(0 if reuse else sum(row["lengths"][1:])) if wide else byte_count
        assert list(transfer) == [job, c, wide, reuse, beat_count, byte_count]
        assert list(timing[:1]) == [job] and timing[2] == case["lengths"][3]
        assert timing[1] == core_cycles(case["descriptor"])+timing[3]
    log = (HERE / "tests/stream.log").read_text(encoding="utf-8", errors="replace")
    assert f"PASS: stream {jobs} jobs {total} exact outputs" in log
    assert "PASS: resource probe matches core cycle-for-cycle" in log
    assert not re.search(r"Fatal:|\$fatal|ERROR:", log)
    synthesis = (HERE / "synthesis.log").read_text(encoding="utf-8", errors="replace")
    assert "Executing : dev_map successfully." in synthesis and not re.search(r"(?m)^E:\s", synthesis)
    snr = (HERE / "synthesize/conv_stream_probe.snr").read_text(encoding="utf-8", errors="replace")
    dmr = (HERE / "device_map/conv_stream_probe.dmr").read_text(encoding="utf-8", errors="replace")
    assert "Device mapping done." in dmr and "Design Summary : All Constraints Met." in snr
    timing = re.search(r"compute_clk\s+100\.0000 MHz\s+[\d.]+ MHz\s+10\.0000\s+([\d.]+)\s+([\d.-]+)", snr)
    assert timing and float(timing[2]) >= 0
    resources = {k: float(re.search(r"\|\s+"+k+r"\s+\|\s+([\d.]+)\s+\|", dmr)[1])
                 for k in ("LUT", "FF", "DRM", "APM", "IO")}
    resources.update(synthesis_only_period_ns=float(timing[1]), synthesis_only_slack_ns=float(timing[2]),
                     scope="Core plus shared-payload resource probe; not production pinout", routed=False,
                     external_io_constrained=False, integrated_with_video=False)
    budget, missing = model_budget()
    result = dict(rtl_jobs=jobs, exact_accumulator_and_code_outputs=total, fixed_cases=len(cases),
                  inherited_cases=3281, added_geometry_cases=4, verified_vector_words=vector_words,
                  cache_reuse_jobs=int(transfers[:, 3].sum()), output_stall_cycles=int(cycles[:, 3].sum()),
                  probe_cycle_equivalent=True, resources=resources, convolution_budget=budget,
                  unsupported_convolutions=missing, protected_main_files_unchanged=len(protected),
                  board_programmed=False, new_bitstream=False, deployment_approved=False,
                  scope="Host-fed operators, no layer scheduler, DDR request/arbitration, full network or camera integration",
                  excluded_from_latency="DDR and layout conversion, output writeback, missing operators/classifier, stalls, routed frequency",
                  accuracy_change="No semantic evaluation or improvements claimed")
    sources = [HERE / p for p in ("source/conv_cached.v", "source/conv_stream_probe.v", "tests/stream_tb.v", "tests/prepare.py",
                                  "tests/verify.py", "tests/run.ps1", "build.ps1", "flow.tcl", "compute.fdc")]
    evidence = [out / p for p in ("cases.json", "vector_cases.json", "expected.hex", "vectors.hex", "rtl_outputs.txt",
                                  "rtl_cycles.txt", "rtl_transfers.txt", "rtl_build_inputs.json", "synthesis_inputs.json",
                                  "protected_before.json", "previous_inputs.json")]
    evidence += [HERE / p for p in ("tests/stream.log", "synthesis.log", "synthesize/conv_stream_probe.snr",
                                     "device_map/conv_stream_probe.dmr", "layer_budget.json")]
    result["source_sha256"] = {str(p.relative_to(HERE)): digest(p) for p in sources}
    result["evidence_sha256"] = {str(p.relative_to(HERE)): digest(p) for p in evidence}
    ref.write_json(HERE / "verification.json", result)
    print(json.dumps({k: v for k, v in result.items() if not k.endswith("sha256")}, indent=2))


if __name__ == "__main__":
    main()
