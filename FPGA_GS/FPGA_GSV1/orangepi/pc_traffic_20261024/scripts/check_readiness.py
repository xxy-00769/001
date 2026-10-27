"""Fail closed; this script never starts training or accepts pseudo labels."""
import csv
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def main():
    path = ROOT / 'data/candidates.csv'
    rows = list(csv.DictReader(path.open(encoding='utf-8-sig'))) if path.exists() else []
    approved = [r for r in rows if r.get('review_status') == 'approved'
                and r.get('reviewer_1') and r.get('reviewer_2')
                and r['reviewer_1'] != r['reviewer_2']
                and r.get('annotation_file') and r.get('license_status') == 'verified'
                and r.get('clean_original') == 'verified'
                and r.get('group_status') == 'verified'
                and r.get('split') in ('train', 'val', 'holdout')]
    groups, hashes = {}, {}
    for row in approved:
        groups.setdefault(row['group_id'], set()).add(row['split'])
        hashes.setdefault(row['sha256'], set()).add(row['split'])
    split_check = ROOT / 'reports/split_audit.json'
    audit = json.loads(split_check.read_text(encoding='utf-8')) if split_check.exists() else {}
    conversion = ROOT / 'reports/rknn_preflight.json'
    rknn = json.loads(conversion.read_text(encoding='utf-8')) if conversion.exists() else {}
    onnx = ROOT / 'reports/deployment_preflight.json'
    preflight = json.loads(onnx.read_text(encoding='utf-8')) if onnx.exists() else {}
    checks = {
        'qualified_batch_at_least_300': len(approved) >= 300,
        'all_candidates_reviewed_or_explicitly_excluded': bool(rows) and all(
            r in approved or r.get('review_status') == 'excluded' for r in rows),
        'approved_group_and_hash_exclusive': bool(approved) and all(
            len(x) == 1 for x in list(groups.values()) + list(hashes.values())),
        'train_and_val_present': {'train', 'val'} <= {r['split'] for r in approved},
        'manual_site_and_near_duplicate_audit': audit.get('passed') is True,
        'onnx_preflight_passed': preflight.get('passed') is True,
        'rknn_fp16_build_passed_for_same_onnx': rknn.get('passed') is True
            and bool(rknn.get('onnx_sha256'))
            and rknn.get('onnx_sha256') == preflight.get('onnx_sha256'),
        'pytorch_gpu_training_smoke_passed': (
            json.loads((ROOT / 'reports/pytorch_cuda_smoke.json').read_text(encoding='utf-8')).get('passed') is True
            if (ROOT / 'reports/pytorch_cuda_smoke.json').exists() else False),
    }
    result = {'ready_to_train': all(checks.values()), 'candidate_images': len(rows),
              'qualified_images': len(approved), 'checks': checks,
              'warning': 'Counts are workflow gates, not a reliability guarantee.'}
    (ROOT / 'reports/readiness.json').write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding='utf-8')
    print(json.dumps(result, ensure_ascii=False, indent=2))
    raise SystemExit(0 if result['ready_to_train'] else 2)


if __name__ == '__main__':
    main()
