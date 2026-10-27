from pathlib import Path
import sys
import unittest

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import reference as ref


class FirstLayerReferenceTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.params, cls.cut = ref.extract()

    def test_all_tile_transfer_plans_reconstruct_frame_regions(self):
        rng = np.random.default_rng(51)
        frame = rng.integers(0, 256, (ref.H, ref.W, 3), dtype=np.uint8)
        for ty in range(12):
            for tx in range(20):
                plan = ref.transfer_plan(tx, ty, base=0x100000, frame_id=8)
                self.assertEqual(plan["payload_bytes"] + plan["local_zero_bytes"], 867)
                self.assertEqual(plan["frame_id"], 8)
                for row in plan["rows"]:
                    for address in row["reads"]:
                        self.assertEqual(address % 32, 0)
                np.testing.assert_array_equal(ref.tile(frame, tx, ty), ref.replay_plan(frame, plan))

    def test_plan_rejects_unaligned_and_invalid_addresses(self):
        for args in ((0, 0, 1), (-1, 0, 0), (20, 0, 0), (0, 12, 0), (0, 0, -32), (0, 0, (1 << 28)-32)):
            with self.assertRaises(ValueError):
                ref.transfer_plan(*args)

    def test_zero_frame_has_zero_accumulator(self):
        acc = ref.conv_acc(np.zeros((ref.H, ref.W, 3), dtype=np.uint8), self.params)
        self.assertFalse(acc.any())

    def test_convolution_matches_independent_scalar_loop(self):
        rng = np.random.default_rng(19)
        frame = rng.integers(0, 256, (ref.H, ref.W, 3), dtype=np.uint8)
        actual = ref.conv_acc(frame, self.params)
        for y, x in ((0, 0), (95, 159), (45, 72), (0, 159)):
            for co in range(16):
                total = 0
                for ci in range(3):
                    for ky in range(3):
                        for kx in range(3):
                            sy, sx = y*2+ky-1, x*2+kx-1
                            pixel = int(self.params["input_lut"][frame[sy, sx, ci]]) if 0 <= sy < ref.H and 0 <= sx < ref.W else 0
                            total += pixel * int(self.params["weights"][co, ci, ky, kx])
                self.assertEqual(total, int(actual[co, y, x]))

    def test_rounding_and_clamps(self):
        params = {"gain": np.ones(16, dtype=np.int64) * (1 << (ref.SHIFT-1)), "offset": np.zeros(16, dtype=np.int64)}
        acc = np.broadcast_to(np.array([-1, 0, 1, 2, 509, 510, 511, 1000]), (16, 1, 8))
        np.testing.assert_array_equal(ref.requant(acc, params)[0, 0], [0, 0, 1, 1, 255, 255, 255, 255])

    def test_accumulator_bit_budget(self):
        self.assertLess(27 * 255 * 128, 1 << 23)
        for weights in self.params["weights"]:
            self.assertLess(int(np.abs(weights.astype(np.int64)).sum()) * 255, 1 << 23)

    def test_all_masked_feature_writes_reconstruct_without_neighbor_corruption(self):
        rng = np.random.default_rng(78)
        expected = rng.integers(0, 256, (16, 96, 160), dtype=np.uint8)
        guarded = np.full(expected.size + 64, 0xA5, dtype=np.uint8)
        memory = guarded[32:-32]
        # Non-raster order catches accidental reliance on zero-filled neighbors.
        order = rng.permutation(240)
        for number in order:
            ty, tx = divmod(int(number), 20)
            plan = ref.write_plan(tx, ty, frame_id=41)
            before = memory.copy()
            features = expected[:, ty*8:ty*8+8, tx*8:tx*8+8]
            ref.replay_writes(memory, features, plan)
            changed = np.zeros_like(expected, dtype=bool)
            changed[:, ty*8:ty*8+8, tx*8:tx*8+8] = True
            np.testing.assert_array_equal(memory[~changed.reshape(-1)], before[~changed.reshape(-1)])
            self.assertEqual(plan["frame_id"], 41)
            self.assertEqual(plan["bus_bytes"], 4096)
        np.testing.assert_array_equal(memory.reshape(expected.shape), expected)
        self.assertTrue((guarded[:32] == 0xA5).all() and (guarded[-32:] == 0xA5).all())

    def test_write_plan_rejects_invalid_allocation(self):
        for args in ((-1, 0, 0), (0, 12, 0), (0, 0, 4), (0, 0, -32), (0, 0, (1 << 28)-32)):
            with self.assertRaises(ValueError):
                ref.write_plan(*args)

    def test_selected_precision_matches_affine_over_entire_accumulator_domain(self):
        for channel in range(16):
            weights = self.params["weights"][channel].astype(np.int64)
            low = int(weights[weights < 0].sum()) * 255
            high = int(weights[weights > 0].sum()) * 255
            acc = np.arange(low, high+1, dtype=np.int64)
            fixed = np.clip((acc * self.params["gain"][channel] + self.params["offset"][channel] + (1 << (ref.SHIFT-1))) >> ref.SHIFT, 0, 255)
            alpha = self.params["input_step"] * self.params["weight_scales"][channel] / self.params["output_step"]
            beta = self.params["float_bias"][channel] / self.params["output_step"]
            np.testing.assert_array_equal(fixed, np.clip(np.floor(acc * alpha + beta + 0.5), 0, 255))
            self.assertLess(max(abs(low), abs(high)) * int(self.params["gain"][channel]) + abs(int(self.params["offset"][channel])) + (1 << (ref.SHIFT-1)), 1 << 55)


if __name__ == "__main__":
    unittest.main()
