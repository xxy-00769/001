---
license: "agpl-3.0"
---
# yolov8n

[English](README.md) | [简体中文](README_CN.md)

## 1. Model Introduction

This repository provides RKNN deployment configurations of yolov8n for RK3588.

| Field | Value |
| --- | --- |
| Model ID | `RKNNAI/RK3588-CNN-yolov8n` |
| Display Name | `RK3588-CNN-yolov8n` |
| Source Model | `https://github.com/airockchip/ultralytics_yolov8` |
| Model Type | CNN |

### Available Models

| Configuration | Supported Chips | RKNN Runtime Version | Quantization | NPU Cores | Resolution |
| --- | --- | --- | --- | --- | --- |
| [yolov8n-640x640-w8a8-1](yolov8n-640x640-w8a8-1/README.md) | RK3588 | `v2.4.0` | w8a8 | 1 | 640x640 |

## 2. Files

| Path | Description |
| --- | --- |
| `README.md` | English documentation |
| `README_CN.md` | Chinese documentation |
| `LICENSE` | License |
| `yolov8n-640x640-w8a8-1/` | Deployment configuration |

## 3. Download

### ModelScope

Full repository:

```bash
modelscope download --model RKNNAI/RK3588-CNN-yolov8n --revision v2.4.0 --local_dir ./RK3588-CNN-yolov8n
```

Selected configuration and root documents:

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

Full repository:

```bash
hf download RKNNAI/RK3588-CNN-yolov8n --revision v2.4.0 --local-dir ./RK3588-CNN-yolov8n
```

Selected configuration and root documents:

```bash
hf download RKNNAI/RK3588-CNN-yolov8n --revision v2.4.0 --local-dir ./RK3588-CNN-yolov8n --include README.md README_CN.md LICENSE 'yolov8n-640x640-w8a8-1/**'
```

## 4. SHA-256 Verification

From the directory where you ran the download command, enter the configuration directory and verify:

```bash
cd ./RK3588-CNN-yolov8n/yolov8n-640x640-w8a8-1
sha256sum -c SHA256SUMS
```

All entries must report `OK` before deployment.

## 5. Compatibility and Limitations

- Supported chips are listed per configuration above.
- Use the matching files from the same configuration.

## 6. Copyright and License

The model is provided through [RKNN Model Zoo](https://github.com/airockchip/rknn_model_zoo/tree/main/examples/yolov8) and originates from [airockchip/ultralytics_yolov8](https://github.com/airockchip/ultralytics_yolov8). The upstream license is GNU AGPL v3; see [LICENSE](LICENSE). Original copyright and attribution notices are retained in the accompanying license file.

This distribution converts the source model to RKNN format for RK3588, using the precision specified in each configuration.
