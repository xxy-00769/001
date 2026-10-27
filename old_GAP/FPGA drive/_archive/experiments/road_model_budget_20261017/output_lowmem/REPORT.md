# Model Regression and Budget

Offline CPU only. All 14 images are reused regression inputs, not untouched holdout.
No pixel labels exist. A positive image retaining any road is not segmentation accuracy.

| Variant | Road images with candidates / 6 | Nonroad images falsely accepted / 8 | Nonroad paint pixels | CPU inference median ms |
| --- | --- | --- | --- | --- |
| segformer_full | 6 | 0 | 0 | 270.8 |
| segformer_thumb8_fullcompute | 6 | 0 | 0 | 267.8 |
| omz_fp32_full | 6 | 3 | 2105 | 42.0 |
| omz_fp32_thumb8_fullcompute | 6 | 4 | 19929 | 161.8 |
| omz_fp32_160x96 | 2 | 0 | 0 | 8.3 |
| omz_fp32_320x192 | 5 | 0 | 0 | 17.7 |
| omz_int8_full | 6 | 3 | 1713 | 120.3 |
| omz_int8_160x96 | 2 | 0 | 0 | 6.9 |
| omz_int8_320x192 | 5 | 0 | 0 | 13.7 |

Timing excludes all pre/postprocessing, I/O and display. It does not predict FPGA throughput.

## Graph Budget

| Variant | Convolution MACs/frame | Largest activation elements | Convolution weight elements |
| --- | --- | --- | --- |
| omz_fp32_full | 2,214,912,000 | 3,670,016 | 179,280 |
| omz_fp32_thumb8_fullcompute | 2,214,912,000 | 3,670,016 | 179,280 |
| omz_fp32_160x96 | 74,160,000 | 122,880 | 179,280 |
| omz_fp32_320x192 | 296,640,000 | 491,520 | 179,280 |
| omz_int8_full | 2,214,912,000 | 3,670,016 | 179,280 |
| omz_int8_160x96 | 74,160,000 | 122,880 | 179,280 |
| omz_int8_320x192 | 296,640,000 | 491,520 | 179,280 |

MAC counts exclude interpolation, pooling, residual addition, quantization, Softmax and postprocessing. Activation count is not peak liveness.
At hypothetical INT8 storage, element counts equal bytes; actual graph tensors are mixed precision. Accumulators, scales and live residuals cost extra.

## Per-Image Failures

### segformer_full

False road candidates: none in this sample.
Road images with no candidates: none in this sample.

### segformer_thumb8_fullcompute

False road candidates: none in this sample.
Road images with no candidates: none in this sample.

### omz_fp32_full

False road candidates: negative_shelf_dark, negative_boxes, negative_table_window.
Road images with no candidates: none in this sample.

### omz_fp32_thumb8_fullcompute

False road candidates: negative_shelf_dark, negative_boxes, negative_table_window, negative_table_brick.
Road images with no candidates: none in this sample.

### omz_fp32_160x96

False road candidates: none in this sample.
Road images with no candidates: legacy_road_1, road_ai_straight, road_ai_curve, road_ai_junction_overhead.

### omz_fp32_320x192

False road candidates: none in this sample.
Road images with no candidates: road_ai_junction_overhead.

### omz_int8_full

False road candidates: negative_shelf_dark, negative_boxes, negative_table_window.
Road images with no candidates: none in this sample.

### omz_int8_160x96

False road candidates: none in this sample.
Road images with no candidates: legacy_road_1, road_ai_straight, road_ai_curve, road_ai_junction_overhead.

### omz_int8_320x192

False road candidates: none in this sample.
Road images with no candidates: road_ai_junction_overhead.

