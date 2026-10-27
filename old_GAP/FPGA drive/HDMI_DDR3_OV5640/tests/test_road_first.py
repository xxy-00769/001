"""Deterministic tests for the offline mask gate, without downloading a model."""
import copy
import json
from pathlib import Path
import sys
import unittest

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "host/road_first"))
from evaluate import erode, prepare, retain_components, road_mask, summarize, validate_settings


class RoadFirstTests(unittest.TestCase):
    def setUp(self):
        self.settings = json.loads((ROOT / "host/road_first/settings.json").read_text())

    def test_positive_and_boundary_erosion(self):
        logits = np.zeros((3, 20, 20), dtype=np.float32)
        logits[1] = 10
        mask, labels, scores, candidate = road_mask(logits, 1, self.settings)
        self.assertTrue(candidate)
        self.assertEqual(mask.sum(), 18 * 18)
        self.assertTrue((labels == 1).all())
        self.assertGreater(scores.min(), 0.99)
        self.assertFalse(mask[0].any())

    def test_nonroad_class_suppresses_every_pixel(self):
        logits = np.zeros((3, 20, 20), dtype=np.float32)
        logits[2] = 10
        mask, _, _, candidate = road_mask(logits, 1, self.settings)
        self.assertFalse(candidate)
        self.assertFalse(mask.any())

    def test_uncertainty_is_not_road(self):
        logits = np.zeros((3, 20, 20), dtype=np.float32)
        logits[1] = 0.1
        mask, _, _, candidate = road_mask(logits, 1, self.settings)
        self.assertFalse(candidate)
        self.assertFalse(mask.any())

    def test_winning_road_still_requires_margin(self):
        config = {**self.settings, "minimum_probability": 0.45, "minimum_margin": 0.2}
        logits = np.zeros((3, 20, 20), dtype=np.float32)
        logits[0], logits[1], logits[2] = -20, np.log(0.55), np.log(0.45)
        mask, _, _, candidate = road_mask(logits, 1, config)
        self.assertFalse(candidate)
        self.assertFalse(mask.any())

    def test_objects_are_not_filled_in(self):
        logits = np.zeros((3, 30, 30), dtype=np.float32)
        logits[1] = 10
        logits[1, 12:18, 12:18] = 0
        logits[2, 12:18, 12:18] = 10
        mask, _, _, candidate = road_mask(logits, 1, self.settings)
        self.assertTrue(candidate)
        self.assertFalse(mask[11:19, 11:19].any())
        self.assertTrue(mask[5, 5])

    def test_speckles_do_not_make_a_road(self):
        logits = np.zeros((3, 40, 40), dtype=np.float32)
        logits[2] = 10
        logits[1, ::4, ::4] = 20
        mask, _, _, candidate = road_mask(logits, 1, self.settings)
        self.assertFalse(candidate)
        self.assertFalse(mask.any())

    def test_small_total_area_is_unconfirmed(self):
        logits = np.zeros((3, 40, 40), dtype=np.float32)
        logits[2] = 10
        logits[1, 5:8, 5:8] = 20
        config = {**self.settings, "erode_cells": 0, "minimum_component_fraction": 0.001}
        mask, _, _, candidate = road_mask(logits, 1, config)
        self.assertFalse(candidate)
        self.assertFalse(mask.any())

    def test_four_connected_components(self):
        mask = np.zeros((10, 10), dtype=bool)
        mask[1:3, 1:3] = True
        mask[3:5, 3:5] = True
        self.assertFalse(retain_components(mask, 5).any())
        self.assertEqual(retain_components(mask, 4).sum(), 8)

    def test_no_fixed_bottom_roi(self):
        logits = np.zeros((3, 40, 40), dtype=np.float32)
        logits[2] = 10
        logits[1, 4:16, 5:30] = 20
        mask, _, _, candidate = road_mask(logits, 1, self.settings)
        self.assertTrue(candidate)
        self.assertTrue(mask[:20].any())
        self.assertFalse(mask[20:].any())

    def test_nonfinite_or_wrong_logits_fail_closed(self):
        for bad in (float("nan"), float("inf"), -float("inf")):
            logits = np.zeros((3, 5, 5), dtype=np.float32)
            logits[0, 0, 0] = bad
            with self.assertRaises(ValueError):
                road_mask(logits, 1, self.settings)
        with self.assertRaises(ValueError):
            road_mask(np.zeros((3, 5)), 1, self.settings)

    def test_setting_validation(self):
        validate_settings(self.settings)
        for value in (0, -1, 1.1, float("nan"), float("inf")):
            settings = {**self.settings, "minimum_probability": value}
            with self.assertRaises(ValueError):
                validate_settings(settings)

    def test_no_erosion_returns_copy(self):
        mask = np.ones((5, 5), dtype=bool)
        result = erode(mask, 0)
        result[0, 0] = False
        self.assertTrue(mask[0, 0])

    def test_preprocessing_rgb_order_and_normalization(self):
        config = {"resample": 2, "do_resize": True, "do_normalize": True,
                  "size": {"width": 8, "height": 4}, "do_rescale": True,
                  "rescale_factor": 1 / 255, "image_mean": [0.485, 0.456, 0.406],
                  "image_std": [0.229, 0.224, 0.225]}
        tensor = prepare(Image.new("RGB", (3, 6), "red"), config)
        self.assertEqual(tensor.shape, (1, 3, 4, 8))
        self.assertEqual(tensor.dtype, np.float32)
        self.assertTrue(tensor.flags.c_contiguous)
        np.testing.assert_allclose(tensor[0, :, 0, 0], [(1-.485)/.229, -.456/.224, -.406/.225], rtol=1e-6)

    def test_dataset_inventory_and_fixed_split(self):
        manifest = ROOT / "tests/fixtures/road_first/dataset.json"
        rows = json.loads(manifest.read_text())["images"]
        self.assertEqual(len(rows), 14)
        self.assertEqual(sum(r["road_present"] for r in rows), 6)
        self.assertEqual(sum(r["split"] == "holdout" for r in rows), 7)
        self.assertEqual(sum(r["source_kind"] == "ai_generated_label_visible" for r in rows), 3)
        self.assertEqual(len({r["id"] for r in rows}), len(rows))
        for row in rows:
            self.assertTrue((manifest.parent / row["file"]).is_file())

    def test_summary_separates_false_positive_and_miss(self):
        rows = [{"road_present": False, "road_candidate": True, "split": "holdout",
                 "baseline_candidate_pixels": 100, "gated_candidate_pixels": 10},
                {"road_present": True, "road_candidate": False, "split": "development",
                 "baseline_candidate_pixels": 100, "gated_candidate_pixels": 0}]
        results = summarize(rows)
        self.assertEqual(results["holdout"]["nonroad_images_with_candidate"], 1)
        self.assertEqual(results["development"]["road_images_with_candidate"], 0)
        self.assertEqual(results["all"]["nonroad_gated_paint_pixels"], 10)


if __name__ == "__main__":
    unittest.main()
