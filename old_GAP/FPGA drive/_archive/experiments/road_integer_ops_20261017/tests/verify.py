"""Verify RTL evidence, reconstruct full tensors and record measured build limits."""
import json
import math
from pathlib import Path
import re
import sys

import numpy as np

HERE = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(HERE))
import reference as ref


def read_json(path):
    return json.loads(Path(path).read_text(encoding="utf-8-sig"))


def mapped_resource(folder, name):
    log = (folder / "synthesis.log").read_text(encoding="utf-8", errors="replace")
    assert "Executing : dev_map successfully." in log and not re.search(r"(?m)^E:\s", log)
    snr = (folder / "synthesize" / f"{name}.snr").read_text(encoding="utf-8", errors="replace")
    dmr = (folder / "device_map" / f"{name}.dmr").read_text(encoding="utf-8", errors="replace")
    assert "Device mapping done." in dmr
    assert "Design Summary : All Constraints Met." in snr
    timing = re.search(r"compute_clk\s+100\.0000 MHz\s+([\d.]+) MHz\s+10\.0000\s+([\d.]+)\s+([\d.-]+)", snr)
    assert timing and float(timing[3]) >= 0
    result = {k: float(re.search(r"\|\s+"+k+r"\s+\|\s+([\d.]+)\s+\|", dmr)[1]) for k in ("LUT","FF","DRM","APM")}
    result.update(synthesis_only_target_ns=10, synthesis_only_estimated_period_ns=float(timing[2]),
                  synthesis_only_slack_ns=float(timing[3]), routed=False, external_interface_timing_constrained=False)
    return result


def main():
    out = HERE / "tests/output"
    metadata, cases, network = [read_json(out / name) for name in ("reference.json","cases.json","network_check.json")]
    before = read_json(out / "protected_before.json")
    assert before == ref.l0.protected_hashes(), "Protected main project/bitstream changed"
    for path, digest in read_json(out / "rtl_build_inputs.json").items():
        assert ref.l0.hash_file(HERE / "tests" / path).upper() == digest
    for path, digest in read_json(out / "synthesis_inputs.json").items():
        assert ref.l0.hash_file(HERE / path).upper() == digest
    ref.l0.verify_models()
    assert metadata["cases"]==len(cases)==3214 and metadata["outputs"]==604920
    with (out / "expected.hex").open(encoding="ascii") as stream:
        expected = np.fromiter((int(line,16) for line in stream), dtype=np.uint64)
    actual_codes = np.empty(len(expected), dtype=np.uint8)
    count = 0
    with (out / "rtl_outputs.txt").open(encoding="ascii") as stream:
        for case in cases:
            for n in range(case["lengths"][3]):
                fields = stream.readline().split()
                assert len(fields)==4 and int(fields[0])==case["id"] and int(fields[1])==n
                packed=(int(fields[2],16)<<8)|int(fields[3],16)
                assert packed==int(expected[count]), (case["id"],n)
                actual_codes[count]=packed & 255
                count+=1
        assert not stream.read().strip()
    assert count==metadata["outputs"]
    log = (HERE / "tests/conv.log").read_text(encoding="utf-8", errors="replace")
    assert f"PASS: conv {len(cases)} jobs {count} exact outputs" in log and not re.search(r"Fatal:|\$fatal|ERROR:",log)
    residual_log = (HERE / "tests/residual.log").read_text(encoding="utf-8", errors="replace")
    assert "PASS: residual 65536 exhaustive pairs, 2 reconfiguration outputs" in residual_log
    assert not re.search(r"Fatal:|\$fatal|ERROR:",residual_log)
    cycles = np.loadtxt(out / "rtl_cycles.txt", dtype=np.int64)
    assert cycles.shape==(len(cases),4)
    for case,row in zip(cases,cycles):
        dw,ci,co,k,s,d,iw,ih,ow,oh=case["descriptor"]
        assert row[0]==case["id"] and row[2]==co*ow*oh
        assert row[1]==28*co + row[2]*(5*(k*k if dw else ci*k*k)+4)+row[3]

    model=ref.load_model()
    rebuilt=[]
    with np.load(out / "legacy_road_3_block.npz") as saved:
        features=saved["input_codes"].copy()
    for layer in (2,4,6):
        p=ref.extract_conv(model,f"L{layer:04d}_Conv2d_BN/WithoutBiases")
        tensor=np.zeros(p["output_shape"],np.uint8)
        seen=set()
        for case in cases:
            if case["name"]!=p["name"] or not case["label"].startswith("legacy_road_3:"):
                continue
            _,x,y=case["label"].split(":")
            x,y=int(x),int(y)
            assert (x,y) not in seen
            seen.add((x,y))
            start=case["offsets"][3]
            tile=actual_codes[start:start+case["lengths"][3]].reshape(p["co"],4,4)
            tensor[:,y:y+4,x:x+4]=tile
        assert len(seen)==960
        np.testing.assert_array_equal(tensor,ref.requant(ref.convolve(features,p),p))
        features=tensor
        rebuilt.append({"layer":p["name"],"tiles":len(seen),"features":tensor.size})
    with np.load(out / "legacy_road_3_block.npz") as saved:
        np.testing.assert_array_equal(features,saved["branch_codes"])
        np.testing.assert_array_equal(ref.residual(features,saved["input_codes"],ref.residual_params(model)),saved["block_codes"])

    inventory=read_json(HERE / "operator_inventory.json")
    arithmetic_cycles=macs=0
    for entry in inventory["supported"]:
        p=ref.extract_conv(model,entry["name"])
        co,oh,ow=p["output_shape"]
        terms=p["kernel"]**2*(1 if p["depthwise"] else p["ci"])
        tile_count=math.ceil(oh/4)*math.ceil(ow/4)
        macs+=co*oh*ow*terms
        arithmetic_cycles+=co*oh*ow*(5*terms+4)+28*co*tile_count
    precision=read_json(HERE / "precision_audit.json")
    assert precision["affine_mismatches"]==precision["residual_mismatches"]==0
    assert len(network["records"])==14
    summary={"convolution_contracts":len(inventory["supported"]),"unsupported_convolutions":inventory["unsupported"],
        "rtl_jobs":len(cases),"rtl_exact_convolution_outputs":count,"rtl_exhaustive_residual_pairs":65536,
        "rtl_residual_reconfiguration_outputs":2,"reconstructed_tensors":rebuilt,
        "convolution_stall_cycles":int(cycles[:,3].sum()),
        "isolated_native_feature_checks":sum(r["features"] for r in metadata["isolated_native_checks"]),
        "isolated_native_differing_codes":sum(r["native_differing_codes"] for r in metadata["isolated_native_checks"]),
        "first_block_vs_native_feature_differences":sum(r["full_native_block_differing_codes"] for r in metadata["records"]),
        "first_block_vs_native_feature_checks":sum(r["block_features"] for r in metadata["records"]),
        "precision_audit":{k:v for k,v in precision.items() if k!="channels"},
        "cpu_tail_same_image_decisions":network["same_image_decisions"],"cpu_tail_same_masks":network["same_accepted_masks"],
        "cpu_tail_nonroad_accepted":network["integer_nonroad_accepted"],"cpu_tail_road_accepted":network["integer_road_accepted"],
        "convolution_resources":mapped_resource(HERE,"conv_tile"),
        "residual_resources":mapped_resource(HERE / "residual_build","residual_requant"),
        "serial_136_conv_macs":macs,"serial_136_conv_core_cycles_without_transfer_or_stalls":arithmetic_cycles,
        "hypothetical_core_seconds_at_100mhz":arithmetic_cycles/100000000,
        "throughput_warning":"Serial correctness baseline is not real-time. Counts exclude loads, DDR, missing operators and classification. Frequency is not routed/measured.",
        "main_files_unchanged":len(before),"board_programmed_this_step":False,"deployment_approved":False,
        "scope":"Reusable arithmetic and host-fed tile verification, not an on-chip layer scheduler, full network, DDR integration or new bitstream."}
    sources=[HERE / p for p in ("reference.py","source/conv_tile.v","source/residual_requant.v","tests/generate.py",
        "tests/test_reference.py","tests/conv_tb.v","tests/residual_tb.v","tests/network_check.py",
        "tests/precision_audit.py","tests/verify.py","tests/run.ps1","build.ps1","flow.tcl","residual_build/flow.tcl","compute.fdc")]
    evidence=[out / p for p in ("reference.json","network_check.json","cases.json","rtl_outputs.txt","rtl_cycles.txt",
        "rtl_build_inputs.json","synthesis_inputs.json")]+[HERE / p for p in ("operator_inventory.json","precision_audit.json",
        "synthesize/conv_tile.snr","device_map/conv_tile.dmr","synthesis.log","tests/conv.log","tests/residual.log",
        "residual_build/synthesize/residual_requant.snr","residual_build/device_map/residual_requant.dmr","residual_build/synthesis.log")]
    summary["source_sha256"]={str(p.relative_to(HERE)):ref.l0.hash_file(p) for p in sources}
    summary["evidence_sha256"]={str(p.relative_to(HERE)):ref.l0.hash_file(p) for p in evidence}
    ref.write_json(HERE / "verification.json",summary)
    print(json.dumps({k:v for k,v in summary.items() if not k.endswith("sha256")},indent=2))


if __name__=="__main__": main()
