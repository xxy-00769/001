"""Reject an accidentally always-false feasibility implementation."""
import unittest

import numpy as np

from evaluate import geometry


class GeometryTests(unittest.TestCase):
    def test_empty(self):
        result = geometry(np.zeros((720, 1280), dtype=bool))
        self.assertFalse(result["pair"])
        self.assertFalse(result["perspective"])

    def test_outward_pair(self):
        mask = np.zeros((720, 1280), dtype=bool)
        for y in range(405, 712):
            for x in (600 - (y - 405), 680 + (y - 405)):
                mask[y, x:x+8] = True
        result = geometry(mask)
        self.assertTrue(result["pair"])
        self.assertTrue(result["perspective"])

    def test_parallel_pair(self):
        mask = np.zeros((720, 1280), dtype=bool)
        mask[405:712, 320:328] = True
        mask[405:712, 960:968] = True
        result = geometry(mask)
        self.assertTrue(result["pair"])
        self.assertFalse(result["perspective"])


if __name__ == "__main__":
    unittest.main()
