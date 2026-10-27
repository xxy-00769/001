# yolov8n-640x640-w8a8-1

[English](README.md) | [简体中文](README_CN.md) · [Model Overview](../README.md)

## Configuration

| Field | Value |
| --- | --- |
| Model ID | `RKNNAI/RK3588-CNN-yolov8n` |
| Display Name | `RK3588-CNN-yolov8n` |
| Configuration Path | `yolov8n-640x640-w8a8-1` |
| RKNN Runtime Version | `v2.4.0` |
| Source Model | `https://github.com/airockchip/ultralytics_yolov8` |
| Source Revision | - |
| Chip Label | RK3588 |
| Supported Chips | RK3588 |
| Model Type | CNN |
| Quantization | w8a8 |
| Algorithm | normal |
| NPU Cores | 1 |
| Resolution | 640x640 |
| Validation Date | - |

## Files

| Path | Description |
| --- | --- |
| `README.md` | English documentation |
| `README_CN.md` | Chinese documentation |
| `SHA256SUMS` | SHA-256 checksums |
| `config.json` | Model configuration and file list |
| `yolov8n.rknn` | RKNN model |

## Download

### ModelScope

```python
from modelscope import snapshot_download

snapshot_download(
    "RKNNAI/RK3588-CNN-yolov8n",
    revision="v2.4.0",
    allow_patterns=["README.md", "README_CN.md", "LICENSE", "yolov8n-640x640-w8a8-1/**"],
    local_dir="./RK3588-CNN-yolov8n",
)
```

### Hugging Face

```bash
hf download RKNNAI/RK3588-CNN-yolov8n --revision v2.4.0 --local-dir ./RK3588-CNN-yolov8n --include README.md README_CN.md LICENSE 'yolov8n-640x640-w8a8-1/**'
```

## Verification

From the directory where you ran the download command, enter the configuration directory and verify:

```bash
cd ./RK3588-CNN-yolov8n/yolov8n-640x640-w8a8-1
sha256sum -c SHA256SUMS
```

All entries must report `OK` before deployment.

## Limitations

- Supported chips: RK3588
- Use the matching files from this configuration.

## Copyright and License

See [Copyright and License](../README.md#6-copyright-and-license).
