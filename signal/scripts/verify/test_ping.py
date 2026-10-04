"""Semantic checks for the received-message summary."""

import io
import json
import unittest
from contextlib import redirect_stdout
from pathlib import Path
from tempfile import TemporaryDirectory

from scripts.verify.ping_analysis import analyze_ping


class PingSummaryTest(unittest.TestCase):
    def test_ping_summary_uses_received_frame_and_completion(self):
        receiver = {
            "status": "complete",
            "message": "ok",
            "bits": [0] * 32,
            "bytes": [2, 111, 107, 9],
            "crc_expected": 9,
            "crc_received": 9,
            "elapsed_ms": 25000,
            "transfer_ms": 20000,
            "frame_retries": 0,
            "total_bit_retries": 1,
            "tick_rate": 200,
            "posteffect_active": False,
        }
        report = {
            "result": "passed",
            "receiver": receiver,
            "configuration": {"expected_message": "reference"},
            "gpu_readback": False,
        }
        with TemporaryDirectory() as temporary:
            directory = Path(temporary)
            with redirect_stdout(io.StringIO()):
                analyze_ping(report, directory)
            summary = json.loads((directory / "summary.json").read_text())
            self.assertEqual(summary["message"], "ok")
            self.assertEqual(summary["wire_bits_per_second"], 1.6)
            self.assertEqual(
                summary["payload_bits_per_second_including_calibration"], 0.64
            )
            self.assertTrue(summary["crc_verified"])
            receiver["status"] = "receiving"
            with redirect_stdout(io.StringIO()):
                analyze_ping(report, directory)
            self.assertFalse(
                json.loads((directory / "summary.json").read_text())["crc_verified"]
            )
