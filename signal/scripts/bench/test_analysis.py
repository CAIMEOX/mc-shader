"""Behavior checks for a timing-only receiver with held-out symbols."""

import io
import json
import unittest
from contextlib import redirect_stdout
from pathlib import Path
from tempfile import TemporaryDirectory

from scripts.bench.analyze import (
    analyze_water,
    analyze_water_speed,
    decode,
    feature,
    scan_levels,
    train,
)
from scripts.bench.rotate_analysis import analyze_rotate


class TimingReceiverTest(unittest.TestCase):
    def test_rotation_scores_live_results_for_each_power(self):
        samples = [
            {
                "phase": "payload",
                "activity": "idle",
                "tick_rate": 200,
                "power": power,
                "bit": bit,
                "scoreboard_received": received,
                "trial_wall_ms": 1000,
                "observed_tps": 200,
                "client_after": {"yaw": -90},
                "rotate": {
                    "events": 10,
                    "arms": 11,
                    "skips": 0,
                    "timeouts": 1,
                    "value": 10000,
                    "valid": 1,
                    "ground_polls": 0,
                    "polls": 100,
                },
            }
            for power, bit, received in [(4, 0, 0), (4, 1, 0), (8, 1, 1)]
        ]
        report = {
            "samples": samples,
            "models": [
                {
                    "tick_rate": 200,
                    "power": power,
                    "ready": 1,
                    "center0": 8000,
                    "center1": 20000,
                    "threshold": 14000,
                }
                for power in [4, 8]
            ],
            "result": "passed",
            "stage": "full",
        }
        with TemporaryDirectory() as temporary:
            directory = Path(temporary)
            with redirect_stdout(io.StringIO()):
                analyze_rotate(report, directory)
            low, high = json.loads((directory / "summary.json").read_text())[
                "receivers"
            ]
            self.assertEqual((low["correct"], low["total"]), (1, 2))
            self.assertEqual((high["correct"], high["total"]), (1, 1))

    def sample(self, bit, gap):
        return {"bit": bit, "arrived": [i * gap for i in range(20)]}

    def test_holdout_decode_uses_observations(self):
        training = [
            self.sample(0, 49),
            self.sample(0, 51),
            self.sample(1, 95),
            self.sample(1, 105),
        ]
        model = train(training, "arrived")
        truth = [1, 0, 1, 1, 0, 0]
        observed = [101, 48, 97, 110, 54, 50]
        decoded = [
            decode({"arrived": [i * gap for i in range(16)]}, "arrived", model)
            for gap in observed
        ]
        self.assertEqual(decoded, truth)

    def test_equal_calibration_centers_abstain(self):
        model = train([self.sample(0, 50), self.sample(1, 50)], "arrived")
        self.assertIsNone(decode({"arrived": [0, 50, 100, 150]}, "arrived", model))

    def test_receiver_learns_opposite_polarity(self):
        model = train([self.sample(0, 100), self.sample(1, 50)], "arrived")
        self.assertEqual(decode({"arrived": [0, 48, 96, 144]}, "arrived", model), 1)
        self.assertEqual(decode({"arrived": [0, 98, 196, 294]}, "arrived", model), 0)

    def test_millisecond_quantization_preserves_average(self):
        sample = {"tick_rate": 2000, "stopwatch_intervals_ms": [0, 0, 1, 0, 1]}
        self.assertEqual(feature(sample, "stopwatch_mean"), 0.5)
        self.assertEqual(feature(sample, "stopwatch_zero"), 0.5)

    def test_feature_selection_uses_stopwatch_only(self):
        training = [
            {
                "bit": bit,
                "tick_rate": 1000,
                "stopwatch_intervals_ms": [0] + [1 if bit == 0 else 3] * 40,
            }
            for bit in [0, 1] * 8
        ]
        model = train(training, "stopwatch_selected")
        for bit, intervals in [(0, [1, 1, 2, 1] * 10), (1, [3, 3, 2, 3] * 10)]:
            observed = {"tick_rate": 1000, "stopwatch_intervals_ms": [0] + intervals}
            self.assertEqual(decode(observed, "stopwatch_selected", model), bit)

    def test_water_summary_scores_the_received_value(self):
        samples = []
        for bit in [0, 1]:
            samples.append(
                {
                    "phase": "payload",
                    "tick_rate": 200,
                    "sequence": bit + 1,
                    "bit": bit,
                    "observed_tps": 200,
                    "duration_ms": 1500,
                    "water": {"value": 50000, "moving_polls": 300, "polls": 300},
                    "events": [{"dx_microblocks": 30000, "gap_ms": 50}] * 30,
                    "decoded": bit,
                    "scoreboard_received": 1,
                }
            )
        report = {
            "samples": samples,
            "models": [
                {
                    "tick_rate": 200,
                    "threshold": 70000,
                    "center0": 50000,
                    "center1": 90000,
                    "ready": 1,
                }
            ],
            "result": "passed",
            "native_scheduling": True,
            "observation_mode": "water",
            "configuration": {},
            "iterations_per_heavy_fragment": 32768,
        }
        with TemporaryDirectory() as temporary:
            directory = Path(temporary)
            with redirect_stdout(io.StringIO()):
                analyze_water(report, directory)
            result = json.loads((directory / "summary.json").read_text())["receivers"][
                0
            ]
            self.assertEqual(result["decoded"], [1, 1])
            self.assertEqual(result["correct"], 1)

    def test_load_scan_requires_distinct_valid_ranges(self):
        samples = [
            {"power": power, "water": {"value": (gap + offset) * 1000, "valid": 1}}
            for power, gap in [(0, 50), (8, 50), (24, 75), (40, 120), (63, 190)]
            for offset in [-2, 2]
        ]
        candidate = scan_levels(samples)["four_level_candidate"]
        self.assertEqual(candidate["centers_ms"], [50, 75, 120, 190])
        self.assertEqual(candidate["minimum_observed_margin_ms"], 21)
        self.assertIsNone(scan_levels(samples[:4])["four_level_candidate"])

    def test_speed_summary_groups_trials_and_counts_abstentions(self):
        samples = [
            {
                "phase": "payload",
                "series": series,
                "bit": bit,
                "scoreboard_received": received,
                "duration_ms": 400,
                "trial_wall_ms": 500,
                "observed_tps": 200,
                "gpu_verified": False,
                "water": {"value": 50000, "valid": 1, "events": 6, "groups": 6},
            }
            for series, bit, received in [
                ("stable", 0, 0),
                ("continuous", 1, -1),
                ("continuous", 0, 1),
            ]
        ]
        report = {
            "samples": samples,
            "series": [
                {"id": "stable", "window_ms": 400, "wall_ms": 2000},
                {"id": "continuous", "window_ms": 400, "wall_ms": 1000},
            ],
            "result": "passed",
            "native_scheduling": True,
            "observation_mode": "water",
            "autonomous_window": True,
            "estimator": "burst_median",
            "models": [],
        }
        with TemporaryDirectory() as temporary:
            directory = Path(temporary)
            with redirect_stdout(io.StringIO()):
                analyze_water_speed(report, directory)
            stable, continuous = json.loads((directory / "summary.json").read_text())[
                "receivers"
            ]
            self.assertEqual(stable["wall_bits_per_second"], 0.5)
            self.assertEqual(continuous["wall_bits_per_second"], 2)
            self.assertEqual(continuous["errors"], 1)
            self.assertEqual(continuous["abstentions"], 1)
            report["series"][0]["bits_per_symbol"] = 2
            samples[0].pop("bit")
            samples[0]["symbol"] = 3
            samples[0]["scoreboard_received"] = 2
            with redirect_stdout(io.StringIO()):
                analyze_water_speed(report, directory)
            four = json.loads((directory / "summary.json").read_text())["receivers"][0]
            self.assertEqual(four["total_bits"], 2)
            self.assertEqual(four["bit_errors"], 1)
            self.assertEqual(four["correct"], 0)
            self.assertEqual(four["wall_bits_per_second"], 1)


if __name__ == "__main__":
    unittest.main()
