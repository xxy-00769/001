import copy
from pathlib import Path
import sys
import unittest

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import reference as ref


class ReferenceTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.model = ref.load_model()
        cls.ps = [ref.extract_conv(cls.model, f"L{i:04d}_Conv2d_BN/WithoutBiases") for i in (2, 4, 6)]

    def test_inventory(self):
        result = ref.inventory(self.model)
        self.assertEqual(len(result["supported"]), 136)
        self.assertEqual([r["name"] for r in result["unsupported"]], ["L0315_Conv2d/WithoutBiases"])
        for entry in result["supported"]:
            self.assertLessEqual(entry["input_tile_bytes"], ref.MAX_INPUT)
            self.assertLessEqual(entry["weight_bytes"], ref.MAX_WEIGHTS)
            self.assertLessEqual(max(entry["descriptor"][1:3]), ref.MAX_CHANNELS)

    def test_scalar_convolution(self):
        rng = np.random.default_rng(31)
        for p0 in self.ps:
            p = copy.deepcopy(p0)
            iw = 2 + p["kernel"] - 1
            ih = 3 + p["kernel"] - 1
            p.update(input_shape=[p["ci"], ih, iw], output_shape=[p["co"], 3, 2], pad=0)
            x = rng.integers(0, 256, p["input_shape"], dtype=np.uint8)
            expected = np.zeros(p["output_shape"], np.int64)
            for c in range(p["co"]):
                for y in range(3):
                    for z in range(2):
                        for i in range(1 if p["depthwise"] else p["ci"]):
                            for ky in range(p["kernel"]):
                                for kx in range(p["kernel"]):
                                    expected[c, y, z] += int(x[c if p["depthwise"] else i, y+ky, z+kx])*int(p["weights"][c, i, ky, kx])
            np.testing.assert_array_equal(ref.convolve(x, p), expected)

    def test_quantization_bounds_and_byte_order(self):
        for p in self.ps:
            raw = ref.coefficient_bytes(p).tobytes()
            for i in range(p["co"]):
                self.assertEqual(int.from_bytes(raw[i*14:i*14+6], "little", signed=True), int(p["gain"][i]))
                self.assertEqual(int.from_bytes(raw[i*14+6:i*14+14], "little", signed=True), int(p["offset"][i]))
                a = np.arange(p["acc_low"][i], p["acc_high"][i]+1, dtype=np.int64)
                fixed = np.clip((a*p["gain"][i]+p["offset"][i]+(1 << 35)) >> 36, 0, 255)
                ideal = np.clip(np.floor(a*p["gain_real"][i]+p["bias_real"][i]+0.5), 0, 255)
                # Differences at rounding boundaries must remain explicitly measured.
                self.assertLessEqual(int(np.max(np.abs(fixed-ideal))), 1)

    def test_tile_boundaries(self):
        p = self.ps[1]
        values = np.arange(np.prod(p["input_shape"]), dtype=np.uint8).reshape(p["input_shape"])
        desc, first = ref.tile(values, p, 0, 0)
        self.assertEqual(desc, [1, 8, 8, 3, 1, 1, 6, 6, 4, 4])
        self.assertTrue(np.all(first[:, 0, :] == 0))
        self.assertTrue(np.all(first[:, :, 0] == 0))
        _, last = ref.tile(values, p, 158, 94, 2, 2)
        self.assertTrue(np.all(last[:, -1, :] == 0))
        self.assertTrue(np.all(last[:, :, -1] == 0))
        with self.assertRaises(ValueError):
            ref.tile(values, p, 159, 94, 2, 2)

    def test_residual_all_code_pairs(self):
        p = ref.residual_params(self.model)
        a, b = np.indices((256, 256), dtype=np.uint16)
        a, b = np.broadcast_to(a.astype(np.uint8), (16, 256, 256)), np.broadcast_to(b.astype(np.uint8), (16, 256, 256))
        actual = ref.residual(a, b, p)
        ideal = ref.encode(np.maximum(ref.decode(a, p["a"])+ref.decode(b, p["b"]), 0), p["out"])
        np.testing.assert_array_equal(actual, ideal)
        self.assertTrue(np.any(actual == 0))
        self.assertTrue(np.any(actual == 255))

    def test_reject_wrong_shapes(self):
        with self.assertRaises(ValueError):
            ref.convolve(np.zeros((8, 3, 3), np.uint8), self.ps[0])
        with self.assertRaises(ValueError):
            ref.residual(np.zeros((16, 3, 3), np.uint8), np.zeros((16, 2, 3), np.uint8), ref.residual_params(self.model))


if __name__ == "__main__":
    unittest.main()
