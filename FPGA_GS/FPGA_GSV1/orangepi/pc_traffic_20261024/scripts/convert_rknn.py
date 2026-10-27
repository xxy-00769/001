"""Run only in an isolated Linux RKNN-Toolkit2 environment. No deployment."""
import argparse
import hashlib
import json
from pathlib import Path


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('onnx', type=Path)
    parser.add_argument('output', type=Path)
    parser.add_argument('--calibration', type=Path, help='Training groups only; enables INT8')
    args = parser.parse_args()
    if args.output.exists():
        raise SystemExit('Refusing to overwrite an existing model')
    from rknn.api import RKNN
    model = RKNN(verbose=True)
    try:
        assert model.config(mean_values=[[0, 0, 0]], std_values=[[255, 255, 255]],
                            target_platform='rk3588', optimization_level=3) == 0
        assert model.load_onnx(model=str(args.onnx)) == 0
        options = {'do_quantization': args.calibration is not None}
        if args.calibration:
            options['dataset'] = str(args.calibration)
        assert model.build(**options) == 0
        assert model.export_rknn(str(args.output)) == 0
        args.output.with_suffix('.manifest.json').write_text(json.dumps({
            'onnx_sha256': hashlib.sha256(args.onnx.read_bytes()).hexdigest(),
            'rknn_sha256': hashlib.sha256(args.output.read_bytes()).hexdigest(),
            'quantized': args.calibration is not None,
            'target': 'rk3588', 'deployment_performed': False,
        }, indent=2), encoding='utf-8')
    finally:
        model.release()


if __name__ == '__main__':
    main()
