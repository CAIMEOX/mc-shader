"""Summarize frame-stream reception, including symbol insertions and deletions."""

import json


def edit_distance(expected, received):
    previous = list(range(len(received) + 1))
    for i, bit in enumerate(expected, 1):
        current = [i]
        for j, observed in enumerate(received, 1):
            current.append(
                min(
                    current[-1] + 1,
                    previous[j] + 1,
                    previous[j - 1] + (bit != observed),
                )
            )
        previous = current
    return previous[-1]


def analyze_stream(report, directory):
    trials = []
    for trial in report.get("trials", []):
        expected, received = trial["expected_bits"], trial["bits"]
        intervals = trial["intervals"]
        start, end = trial["started_ms"], trial["ended_ms"]
        data_ms = sum(e["gap_ms"] for e in intervals if start < e["time_ms"] < end)
        trials.append(
            {
                "pattern": trial["pattern"],
                "activity": trial.get("activity", "idle"),
                "position_change_blocks": trial.get("position_change_blocks"),
                "input_audit": trial.get("input_audit"),
                "mined_blocks": trial.get("mined_blocks"),
                "status": trial["status"],
                "expected_bits": len(expected),
                "received_bits": len(received),
                "exact": trial["status"] == "complete" and expected == received,
                "edit_distance": edit_distance(expected, received),
                "substitutions": sum(a != b for a, b in zip(expected, received))
                if len(expected) == len(received)
                else None,
                "data_interval_ms": data_ms,
                "observed_symbol_rate": len(received) * 1000 / data_ms
                if data_ms
                else None,
                "session_ms": end,
                "verified_bits_per_second": len(expected) * 1000 / end
                if end and trial["status"] == "complete" and expected == received
                else None,
                "ground_polls": trial["ground_polls"],
                "upward_changes": trial["upward"],
                "observed_tps": trial["observed_tps"],
            }
        )
    summary = {
        "result": report["result"],
        "experiment": report["experiment"],
        "calibration": report.get("calibration"),
        "controls": report.get("controls"),
        "pilots": [
            {
                key: p[key]
                for key in [
                    "power",
                    "median_ms",
                    "median_ticks",
                    "min_ms",
                    "max_ms",
                    "observed_tps",
                ]
            }
            for p in report.get("pilots", [])
        ],
        "trials": trials,
        "exact_trials": sum(t["exact"] for t in trials),
    }
    (directory / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    for trial in trials:
        print(
            f"{report['experiment']} {trial['pattern']} {trial['activity']}: {trial['received_bits']}/{trial['expected_bits']} bits, exact={trial['exact']}, edit distance={trial['edit_distance']}, symbols/s={trial['observed_symbol_rate']}"
        )
