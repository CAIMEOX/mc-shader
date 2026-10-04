"""Checks for timing-stream alignment metrics."""

import unittest

from scripts.bench.stream_analysis import edit_distance


class StreamAnalysisTest(unittest.TestCase):
    def test_counts_substitution_insertion_and_deletion(self):
        bits = [0, 1, 1, 0, 1]
        self.assertEqual(edit_distance(bits, bits), 0)
        self.assertEqual(edit_distance(bits, [0, 0, 1, 0, 1]), 1)
        self.assertEqual(edit_distance(bits, [0, 1, 0, 1]), 1)
        self.assertEqual(edit_distance(bits, [0, 1, 1, 1, 0, 1]), 1)
        self.assertEqual(edit_distance(bits, []), len(bits))
