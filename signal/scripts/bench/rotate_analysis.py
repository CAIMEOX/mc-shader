"""Summarize rotation probes using values received by data-pack functions."""

import csv
import json
from statistics import median


def analyze_rotate(report, directory):
    from scripts.bench.analyze import wilson

    samples = report["samples"]
    receivers = []
    for model in report["models"]:
        matching = [
            s
            for s in samples
            if s["phase"] == "payload"
            and s["tick_rate"] == model["tick_rate"]
            and ("power" not in model or s["power"] == model["power"])
        ]
        for activity in sorted({s.get("activity", "idle") for s in matching}):
            payload = [s for s in matching if s.get("activity", "idle") == activity]
            truth = [s["bit"] for s in payload]
            received = [s["scoreboard_received"] for s in payload]
            correct = sum(a == b for a, b in zip(truth, received))
            wall = sum(s["trial_wall_ms"] for s in payload) / 1000
            receivers.append(
                {
                    "tick_rate": model["tick_rate"],
                    "power": model.get("power"),
                    "activity": activity,
                    "total": len(payload),
                    "correct": correct,
                    "errors": sum(a >= 0 and a != b for a, b in zip(received, truth)),
                    "abstentions": received.count(-1),
                    "decoded": received,
                    "truth": truth,
                    "ready": model["ready"] == 1,
                    "centers_ms": [model["center0"] / 1000, model["center1"] / 1000],
                    "threshold_ms": model["threshold"] / 1000
                    if model["ready"]
                    else None,
                    "wilson_95": wilson(correct, len(payload)),
                    "trial_bits_per_second": len(payload) / wall,
                    "actual_tps_median": median(s["observed_tps"] for s in payload),
                }
            )
    rows = []
    for sample in samples:
        state = sample["rotate"]
        audit = sample.get("input_audit", {})
        rows.append(
            {
                **{
                    key: sample.get(key)
                    for key in [
                        "phase",
                        "activity",
                        "probe_enabled",
                        "tick_rate",
                        "sequence",
                        "bit",
                        "power",
                        "initial_yaw",
                        "window_ms",
                        "observed_tps",
                        "scoreboard_received",
                        "yaw_difference_degrees",
                        "position_change_blocks",
                        "mined_blocks",
                    ]
                },
                "replies": state["events"],
                "arms": state["arms"],
                "skips": state["skips"],
                "pending_at_end": state["timeouts"],
                "feature_ms": state["value"] / 1000 if state["valid"] else None,
                "ground_fraction": state["ground_polls"] / state["polls"]
                if state["polls"]
                else None,
                "client_yaw_after": sample["client_after"]["yaw"],
                **{
                    key: audit.get(key)
                    for key in [
                        "client_ticks",
                        "max_angle_error_degrees",
                        "max_raw_yaw_degrees",
                        "vertical_range_blocks",
                    ]
                },
            }
        )
    if rows:
        with (directory / "samples.csv").open("w", newline="") as handle:
            writer = csv.DictWriter(handle, fieldnames=list(rows[0]))
            writer.writeheader()
            writer.writerows(rows)
    summary = {
        "result": report["result"],
        "experiment": "rotate",
        "stage": report["stage"],
        "sample_count": len(samples),
        "models": report["models"],
        "fps_samples": report.get("fps_samples", []),
        "receivers": receivers,
        "geometry": [row for row in rows if row["phase"] == "geometry"],
        "behavior": [row for row in rows if row["phase"] in {"control", "behavior"}],
        "scope": "Visible native client; data-pack angle observations and live scoreboard decisions. GPU truth verified outside each sampling window. Input audits measure pose and ordinary held-key actions independently of decoding. Trial throughput includes within-trial setup and readbacks; calibration and activity-fixture preparation are separate. FPS profiles hold each shader load with the receiver inactive.",
    }
    (directory / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    for model in report["models"]:
        print(
            f"Rotate {model['tick_rate']} TPS, power {model.get('power')}: centers {model['center0'] / 1000:.2f}/{model['center1'] / 1000:.2f} ms, ready={model['ready']}"
        )
    for result in receivers:
        print(
            f"Rotate {result['tick_rate']} TPS, power {result['power']}, {result['activity']}: {result['correct']}/{result['total']}, {result['errors']} errors, {result['abstentions']} unresolved"
        )
