"""Verify recorded writes, memory canaries, provenance and mapped resources."""
import json
from pathlib import Path
import re
import sys

import numpy as np

HERE = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(HERE / "tests"))
import prepare


def read_json(path):
    return json.loads(Path(path).read_text(encoding="utf-8-sig"))


def hex_words(path):
    return [int(line, 16) for line in Path(path).read_text(encoding="ascii").splitlines()]


def main():
    out = HERE / "tests/output"
    cases = read_json(out / "cases.json")
    for path, digest in read_json(out / "previous_inputs.json").items():
        assert prepare.digest(HERE.parent / path) == digest, f"Prior artifact changed: {path}"
    for root, manifest in ((HERE / "tests", "rtl_build_inputs.json"), (HERE, "synthesis_inputs.json")):
        for path, digest in read_json(out / manifest).items():
            assert prepare.digest(root / path).upper() == digest, f"Build input changed: {path}"
    protected = read_json(out / "protected_before.json")
    assert protected == prepare.ref.l0.protected_hashes()
    memory = hex_words(out / "initial.hex")
    golden = hex_words(out / "golden.hex")
    transactions = hex_words(out / "transactions.hex")
    descriptors = hex_words(out / "descriptors.hex")
    assert len(cases) == len(descriptors)
    values = words = tail_words = 0
    cycles = np.loadtxt(out / "rtl_cycles.txt", dtype=np.int64)
    assert cycles.shape == (len(cases), 9)
    with (out / "rtl_outputs.txt").open(encoding="ascii") as stream:
        for job, case in enumerate(cases):
            assert prepare.pack_descriptor(case["fields"]) == descriptors[job]
            start, count = case["transaction_start"], case["transaction_count"]
            rows = transactions[start:start+count]
            assert len(rows) == count
            assert list(cycles[job, [0, 2, 3, 4, 5, 6]]) == [job, case["read_words"], case["write_words"],
                case["tiles"], case["tiles"]-1, case["zero_padding_vectors"]]
            assert cycles[job, 1] > count and cycles[job, 7] > 0 and cycles[job, 8] >= 50
            seen = set()
            for transaction in rows:
                address = (transaction >> 144) & 0xffffffff
                data = transaction & ((1 << 128)-1)
                keep = (transaction >> 128) & 65535
                if transaction >> 176:
                    fields = stream.readline().split()
                    assert len(fields) == 4 and [int(fields[0]), int(fields[1])] == [job, address]
                    actual, strobes = int(fields[2], 16), int(fields[3], 16)
                    assert strobes == keep and address not in seen
                    seen.add(address)
                    for lane in range(16):
                        if keep & (1 << lane):
                            mask = 255 << (lane*8)
                            assert (actual & mask) == (data & mask)
                            memory[address] = (memory[address] & ~mask) | (actual & mask)
                            values += 1
                    words += 1
                    tail_words += keep != 65535
                else:
                    assert keep == 0 and memory[address] == data
            assert len(seen) == case["write_words"]
        assert not stream.read().strip()
    assert memory == golden
    assert values == sum(c["output_bytes"] for c in cases)
    chained = [c for c in cases if c["name"].startswith("L")]
    assert len(chained) == 3 and [c["chained"] for c in chained] == [False, True, True]
    for previous, current in zip(chained, chained[1:]):
        assert previous["fields"]["output_base"] == current["fields"]["input_base"]
    log = (HERE / "tests/layer.log").read_text(encoding="utf-8", errors="replace")
    match = re.search(r"PASS: layer_dma (\d+) layers (\d+) memory words (\d+) fault cases (\d+) reset cases; recovery passed", log)
    assert match and not re.search(r"Fatal:|\$fatal|ERROR:", log)
    assert [int(match[1]), int(match[2])] == [len(cases), len(memory)]
    assert int(match[3]) >= 15 and int(match[4]) == 2
    synthesis = (HERE / "synthesis.log").read_text(encoding="utf-8", errors="replace")
    assert "Executing : dev_map successfully." in synthesis and not re.search(r"(?m)^E:\s", synthesis)
    snr = (HERE / "synthesize/layer_probe.snr").read_text(encoding="utf-8", errors="replace")
    dmr = (HERE / "device_map/layer_probe.dmr").read_text(encoding="utf-8", errors="replace")
    assert "Device mapping done." in dmr
    timing = re.search(r"compute_clk\s+100\.0000 MHz\s+[\d.]+ MHz\s+10\.0000\s+([\d.]+)\s+([\d.-]+)", snr)
    assert timing
    resources = {k: float(re.search(r"\|\s+"+k+r"\s+\|\s+([\d.]+)\s+\|", dmr)[1])
                 for k in ("LUT", "FF", "DRM", "APM", "IO")}
    resources.update(synthesis_only_period_ns=float(timing[1]), synthesis_only_slack_ns=float(timing[2]),
                     target_10ns_met=float(timing[2])>=0, routed=False, external_io_constrained=False,
                     scope="Cached convolution core plus layer DMA and test-only serial descriptor/response probe")
    chain_cycles = int(cycles[-3:, 1].sum())
    result = dict(functional_verification_passed=True, target_timing_passed=resources["target_10ns_met"],
                  successful_layer_jobs=len(cases), recovery_jobs=1, exact_output_bytes=values,
                  output_word_writes=words, partial_channel_word_writes=tail_words,
                  memory_words_including_guards_verified=len(memory), memory_transactions=len(transactions),
                  tiles=int(cycles[:, 4].sum()), weight_reuse_tiles=int(cycles[:, 5].sum()),
                  locally_generated_zero_vectors=int(cycles[:, 6].sum()),
                  request_backpressure_cycles=int(cycles[:, 7].sum()), response_wait_cycles=int(cycles[:, 8].sum()),
                  fault_cases=int(match[3]), mid_transaction_resets=int(match[4]),
                  delayed_final_write_ack_jobs=len(cases)+1,
                  real_feature_chain=dict(layers=[c["name"] for c in chained],
                      output_bytes=sum(c["output_bytes"] for c in chained), simulated_cycles=chain_cycles,
                      host_intermediate_reloads=0, complete_residual_block=False, complete_network=False,
                      note="Deterministic memory stalls and test-probe overhead included; not measured DDR or frame latency"),
                  resources=resources, protected_main_files_unchanged=len(protected),
                  board_programmed=False, new_bitstream=False, deployment_approved=False,
                  accuracy_change="None claimed; verifies data movement/arithmetic, not road classification",
                  remaining="Configuration-path timing closure, vendor 256-bit DDR adapter/arbitration, complete model and classifier, routing, board and semantic validation")
    sources = [HERE / p for p in ("source/conv_layer_dma.v", "source/layer_probe.v", "tests/layer_tb.v",
        "tests/prepare.py", "tests/verify.py", "tests/run.ps1", "build.ps1", "flow.tcl", "compute.fdc")]
    sources.append(prepare.PREVIOUS / "source/conv_cached.v")
    evidence = [out / p for p in ("cases.vh", "cases.json", "initial.hex", "golden.hex", "transactions.hex",
        "descriptors.hex", "jobs.txt", "previous_inputs.json", "protected_before.json", "rtl_outputs.txt",
        "recovery_outputs.txt", "rtl_cycles.txt", "rtl_build_inputs.json", "synthesis_inputs.json")]
    evidence += [HERE / p for p in ("tests/layer.log", "synthesis.log", "synthesize/layer_probe.snr", "device_map/layer_probe.dmr")]
    import os
    result["source_sha256"] = {os.path.relpath(p, HERE): prepare.digest(p) for p in sources}
    result["evidence_sha256"] = {os.path.relpath(p, HERE): prepare.digest(p) for p in evidence}
    prepare.ref.write_json(HERE / "verification.json", result)
    print(json.dumps({k: v for k, v in result.items() if not k.endswith("sha256")}, indent=2))


if __name__ == "__main__":
    main()
