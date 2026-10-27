import unittest

import numpy as np
from PIL import Image

from evaluate import gate, ov_inventory, softmax, thumbnail


class ModelExperimentTest(unittest.TestCase):
    def test_rgb565_box_mean_matches_explicit_integer_reference(self):
        from road_marking_model import rgb565
        rng = np.random.default_rng(44)
        pixels = rgb565(Image.fromarray(rng.integers(0, 256, (32, 64, 3), dtype=np.uint8))).astype(np.uint8)
        actual = thumbnail(pixels, 8)
        expected = np.zeros((4, 8, 3), dtype=np.uint8)
        for y in range(4):
            for x in range(8):
                expected[y, x] = pixels[y*8:y*8+8, x*8:x*8+8].astype(np.uint32).sum(axis=(0, 1)) // 64
        expected = rgb565(Image.fromarray(expected)).astype(np.uint8)
        np.testing.assert_array_equal(actual, expected)

    def test_flat_saturated_colors_preserved(self):
        for color in ((0, 0, 0), (255, 255, 255), (255, 0, 0), (0, 255, 0), (0, 0, 255)):
            pixels = np.broadcast_to(np.array(color, dtype=np.uint8), (16, 24, 3))
            np.testing.assert_array_equal(thumbnail(pixels, 8), np.broadcast_to(color, (2, 3, 3)))

    def test_invalid_dimensions(self):
        with self.assertRaises(ValueError):
            thumbnail(np.zeros((13, 16, 3), dtype=np.uint8), 8)

    def test_road_and_mark_group_preserves_marks(self):
        p = np.zeros((4, 90, 160), dtype=np.float32)
        p[1], p[3], p[0] = 0.4, 0.4, 0.2
        mask, _, valid = gate(p, [1, 3])
        self.assertTrue(valid)
        self.assertTrue(mask[45, 80])
        self.assertFalse(mask[0].any())

    def test_background_and_uncertainty_rejected(self):
        for road in (0.0, 0.69):
            p = np.zeros((4, 90, 160), dtype=np.float32)
            p[1], p[0] = road, 1-road
            mask, _, valid = gate(p, [1, 3])
            self.assertFalse(valid)
            self.assertFalse(mask.any())

    def test_isolated_components_removed(self):
        p = np.zeros((4, 90, 160), dtype=np.float32)
        p[0] = 1
        p[0, 20:25, 20:25] = 0
        p[1, 20:25, 20:25] = 1
        self.assertFalse(gate(p, [1, 3])[2])

    def test_invalid_output_rejected(self):
        for value in (float("nan"), -1, 2, 0):
            with self.assertRaises(ValueError):
                gate(np.full((4, 3, 3), value, dtype=np.float32), [1, 3])

    def test_stable_softmax(self):
        p = softmax(np.array([[[1000]], [[1001]]], dtype=np.float32))
        self.assertAlmostEqual(float(p.sum()), 1)
        self.assertGreater(p[1, 0, 0], p[0, 0, 0])

    def test_convolution_budget(self):
        import openvino as ov
        from openvino import opset13 as ops
        data = ops.parameter([1, 3, 8, 8], np.float32)
        weights = ops.constant(np.ones((4, 3, 3, 3), dtype=np.float32))
        conv = ops.convolution(data, weights, [1, 1], [1, 1], [1, 1], [1, 1])
        inventory = ov_inventory(ov.Model([conv], [data]))
        self.assertEqual(inventory["convolution_weight_elements"], 108)
        self.assertEqual(inventory["convolution_macs_per_frame"], 4 * 8 * 8 * 27)

    def test_depthwise_budget(self):
        import openvino as ov
        from openvino import opset13 as ops
        data = ops.parameter([1, 3, 8, 8], np.float32)
        weights = ops.constant(np.ones((3, 1, 1, 3, 3), dtype=np.float32))
        conv = ops.group_convolution(data, weights, [1, 1], [1, 1], [1, 1], [1, 1])
        inventory = ov_inventory(ov.Model([conv], [data]))
        self.assertEqual(inventory["convolution_weight_elements"], 27)
        self.assertEqual(inventory["convolution_macs_per_frame"], 3 * 8 * 8 * 9)


if __name__ == "__main__":
    unittest.main()
