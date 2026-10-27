---
license: agpl-3.0
---

<p align="center">
  <img src="https://github.com/mkturkcan/traffic-lights-of-new-york/blob/main/assets/logo.png?raw=true"  width="180" />
</p>


<h3 align="center">
  <p>Traffic Lights of New York (TLoNY): Models</p>
</h3>

A comprehensive object detection dataset for fine-grained classification of traffic lights in New York City. The dataset includes both vehicular and pedestrian traffic signals with detailed color state annotations.

## Overview

<p align="center">
  <img src="http://keremturkcan.com/projects/tlony_collage.png" />
</p>


TLoNY provides accurately labeled traffic light data suitable for training object detection models, sourced from publicly available images from Unsplash. The dataset captures various lighting conditions, weather scenarios, and urban environments of New York City.

## Metrics

| Model Name | Recall | mAP50 | mAP50-95 |
|------------|---------|--------|-----------|
| yolov8x-p2 | 0.50405 | 0.56544| 0.30823   |
| yolov8n    | 0.43263 | 0.50172| 0.27866   |

## Download
### Dataset
* [Huggingface](https://huggingface.co/datasets/mehmetkeremturkcan/traffic-lights-of-new-york/tree/main)
### Models
* [Huggingface](https://huggingface.co/mehmetkeremturkcan/traffic-lights-of-new-york)

```bash
huggingface-cli download mehmetkeremturkcan/traffic-lights-of-new-york --local-dir tlony-models
```


## Cite

```bibtex
@misc {mehmet_kerem_turkcan_2025,
	author       = { {Mehmet Kerem Turkcan} },
	title        = { traffic-lights-of-new-york (Revision 2999230) },
	year         = 2025,
	url          = { https://huggingface.co/datasets/mehmetkeremturkcan/traffic-lights-of-new-york },
	doi          = { 10.57967/hf/4331 },
	publisher    = { Hugging Face }
}
```