"""Decode shader symbols using packet timing or data-pack stopwatch observations."""

import csv
import json
import math
from itertools import combinations
from statistics import mean, median

STOPWATCH_FEATURES = (
    "stopwatch",
    "stopwatch_mean",
    "stopwatch_mae",
    "stopwatch_zero",
    "stopwatch_late",
    "stopwatch_p99",
)


def quantile(values, fraction):
    values = sorted(values)
    if not values:
        raise ValueError("Timing stream has no intervals")
    position = (len(values) - 1) * fraction
    low = math.floor(position)
    high = math.ceil(position)
    return values[low] + (values[high] - values[low]) * (position - low)


def gaps(timestamps):
    return [b - a for a, b in zip(timestamps, timestamps[1:])]


def feature(sample, receiver):
    if receiver in STOPWATCH_FEATURES:
        nominal = 1000 / sample["tick_rate"]
        intervals = sample["stopwatch_intervals_ms"][1:]
        deviations = [abs(value - nominal) for value in intervals]
        if receiver == "stopwatch_mean":
            return mean(intervals)
        if receiver == "stopwatch_mae":
            return mean(deviations)
        if receiver == "stopwatch_zero":
            return mean(value == 0 for value in intervals)
        if receiver == "stopwatch_late":
            return mean(value > math.ceil(nominal) + 1 for value in intervals)
        return quantile(deviations, 0.99 if receiver == "stopwatch_p99" else 0.9)
    return quantile(gaps(sample[receiver]), 0.9)


def fit(observations):
    centers = [
        median(value for value, label in observations if label == bit) for bit in [0, 1]
    ]
    return {
        "threshold": mean(centers),
        "heavy_is_larger": centers[1] > centers[0],
        "centers": centers,
        "separated": not math.isclose(
            centers[0], centers[1], rel_tol=1e-9, abs_tol=1e-12
        ),
    }


def classify(value, model):
    if not model["separated"]:
        return None
    above = value > model["threshold"]
    return int(above == model["heavy_is_larger"])


def train(samples, receiver):
    if receiver == "stopwatch_selected":
        candidates = []
        for candidate in STOPWATCH_FEATURES:
            observations = [
                (feature(sample, candidate), sample["bit"]) for sample in samples
            ]
            correct = sum(
                classify(value, fit(observations[:i] + observations[i + 1 :])) == label
                for i, (value, label) in enumerate(observations)
            )
            candidates.append((correct, candidate, fit(observations)))
        correct, selected, model = max(candidates, key=lambda item: item[0])
        return {
            **model,
            "feature": selected,
            "validation_correct": correct,
            "validation_total": len(samples),
            "selection_scores": {
                candidate: score for score, candidate, _ in candidates
            },
        }
    return fit([(feature(sample, receiver), sample["bit"]) for sample in samples])


def decode(sample, receiver, model):
    return classify(feature(sample, model.get("feature", receiver)), model)


def wilson(correct, total):
    z = 1.96
    proportion = correct / total
    denominator = 1 + z * z / total
    center = (proportion + z * z / (2 * total)) / denominator
    radius = (
        z
        * math.sqrt(proportion * (1 - proportion) / total + z * z / (4 * total * total))
        / denominator
    )
    return [max(0, center - radius), min(1, center + radius)]


def analyze(report, directory):
    if report.get("experiment") in {"fall", "rotate_stream"}:
        from scripts.bench.stream_analysis import analyze_stream

        return analyze_stream(report, directory)
    if report.get("experiment") == "pingpong":
        from scripts.verify.ping_analysis import analyze_ping

        return analyze_ping(report, directory)
    if report.get("experiment") == "rotate":
        from scripts.bench.rotate_analysis import analyze_rotate

        return analyze_rotate(report, directory)
    if report.get("experiment") in {"water_speed", "water_four"}:
        return analyze_water_speed(report, directory)
    if report.get("experiment") == "water":
        return analyze_water(report, directory)
    samples = report["samples"]
    if not samples:
        return
    rows = []
    for sample in samples:
        row = {
            key: sample[key]
            for key in ["phase", "tick_rate", "sequence", "bit", "power"]
        }
        row["fps"] = (
            1000 / median(gaps(sample["frame"])) if len(sample["frame"]) > 1 else None
        )
        for stream in ["sent", "arrived", "handled", "server_tick"]:
            row[stream + "_hz"] = (
                len(sample[stream]) * 1000 / sample["duration_ms"]
                if sample[stream]
                else None
            )
            row[stream + "_gap_p90_ms"] = (
                quantile(gaps(sample[stream]), 0.9) if len(sample[stream]) > 1 else None
            )
        row["server_tick_hz"] = sample.get("observed_tps", row["server_tick_hz"])
        row["stopwatch_jitter_p90_ms"] = feature(sample, "stopwatch")
        row["stopwatch_mean_ms"] = mean(sample["stopwatch_intervals_ms"])
        for receiver in STOPWATCH_FEATURES:
            row[receiver] = feature(sample, receiver)
        rows.append(row)
    with (directory / "samples.csv").open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)
    results = []
    for rate in sorted({sample["tick_rate"] for sample in samples}):
        training = [
            s for s in samples if s["tick_rate"] == rate and s["phase"] == "training"
        ]
        payload = [
            s for s in samples if s["tick_rate"] == rate and s["phase"] == "payload"
        ]
        if len(training) < 8 or not payload:
            continue
        for receiver in [
            "sent",
            "arrived",
            "handled",
            *STOPWATCH_FEATURES,
            "stopwatch_selected",
        ]:
            if (
                receiver in {"sent", "arrived", "handled"}
                and report.get("observation_mode") == "stopwatch_only"
            ):
                continue
            model = train(training, receiver)
            # Decoding receives only timing observations; truth is used for scoring.
            predictions = [
                decode(
                    {
                        k: v
                        for k, v in s.items()
                        if k
                        not in {"bit", "gpu_digest", "control_word", "sequence", "mode"}
                    },
                    receiver,
                    model,
                )
                for s in payload
            ]
            truth = [s["bit"] for s in payload]
            correct = sum(a == b for a, b in zip(predictions, truth))
            results.append(
                {
                    "tick_rate": rate,
                    "receiver": receiver,
                    "model": model,
                    "decoded": predictions,
                    "truth": truth,
                    "correct": correct,
                    "total": len(truth),
                    "accuracy": correct / len(truth),
                    "abstentions": sum(value is None for value in predictions),
                    "wilson_95": wilson(correct, len(truth)),
                    "majority_baseline": max(sum(truth), len(truth) - sum(truth))
                    / len(truth),
                }
            )
    rates = []
    for rate in sorted(
        {sample["tick_rate"] for sample in samples if sample["phase"] == "payload"}
    ):
        subset = [
            row
            for row in rows
            if row["tick_rate"] == rate and row["phase"] == "payload"
        ]
        rates.append(
            {
                "target": rate,
                "actual_min": min(row["server_tick_hz"] for row in subset),
                "actual_median": median(row["server_tick_hz"] for row in subset),
                "actual_max": max(row["server_tick_hz"] for row in subset),
                "tracking_fraction": mean(
                    abs(row["server_tick_hz"] / rate - 1) <= 0.1 for row in subset
                ),
            }
        )
    summary = {
        "result": report["result"],
        "transport": report["transport"],
        "observation_mode": report.get("observation_mode", "full"),
        "selected_power": report.get("selected_power"),
        "native_scheduling": report.get("native_scheduling"),
        "calibration_target_reached": report.get("calibration_target_reached"),
        "work_iterations": report.get("iterations_per_heavy_fragment"),
        "sample_count": len(samples),
        "rates": rates,
        "configuration": report.get("configuration"),
        "receivers": results,
        "scope": "Single-machine exploratory trial. Packet timestamps require harness instrumentation; stopwatch observations are produced by the data pack.",
    }
    (directory / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    for result in results:
        if result["receiver"] not in {"arrived", "stopwatch", "stopwatch_selected"}:
            continue
        print(
            f"{result['tick_rate']} TPS · {result['receiver']}: {result['correct']}/{result['total']} bits, {result['abstentions']} unresolved"
        )


def analyze_water(report, directory):
    rows = []
    for sample in report["samples"]:
        water = sample["water"]
        events = sample["events"]
        dx = [event["dx_microblocks"] / 1e6 for event in events]
        intervals = [event["gap_ms"] for event in events[1:]]
        rows.append(
            {
                "phase": sample["phase"],
                "tick_rate": sample["tick_rate"],
                "sequence": sample["sequence"],
                "bit": sample["bit"],
                "observed_tps": sample["observed_tps"],
                "events": len(events),
                "event_rate_hz": len(events) * 1000 / sample["duration_ms"],
                "mean_gap_ms": water["value"] / 1000,
                "gap_p90_ms": quantile(intervals, 0.9),
                "median_step_blocks": median(dx),
                "moving_fraction": water["moving_polls"] / water["polls"],
                "decoded": sample.get("decoded"),
                "scoreboard_received": sample.get("scoreboard_received"),
            }
        )
    if rows:
        with (directory / "samples.csv").open("w", newline="") as handle:
            writer = csv.DictWriter(handle, fieldnames=list(rows[0]))
            writer.writeheader()
            writer.writerows(rows)
    receivers = []
    for model in report["models"]:
        payload = [
            sample
            for sample in report["samples"]
            if sample["phase"] == "payload"
            and sample["tick_rate"] == model["tick_rate"]
            and "decoded" in sample
        ]
        if not payload:
            continue
        truth = [sample["bit"] for sample in payload]
        decoded = [sample["scoreboard_received"] for sample in payload]
        correct = sum(bit == result for bit, result in zip(truth, decoded))
        receivers.append(
            {
                "tick_rate": model["tick_rate"],
                "receiver": "data_pack_position",
                "threshold_ms": model["threshold"] / 1000,
                "centers_ms": [model["center0"] / 1000, model["center1"] / 1000],
                "ready": model["ready"] == 1,
                "correct": correct,
                "total": len(payload),
                "accuracy": correct / len(payload),
                "decoded": decoded,
                "truth": truth,
                "abstentions": decoded.count(-1),
                "wilson_95": wilson(correct, len(payload)),
                "actual_tps_median": median(
                    sample["observed_tps"] for sample in payload
                ),
            }
        )
    summary = {
        "result": report["result"],
        "experiment": "water",
        "native_scheduling": report["native_scheduling"],
        "observation_mode": report["observation_mode"],
        "autonomous_window": report.get("autonomous_window", False),
        "configuration": report["configuration"],
        "sample_count": len(rows),
        "work_iterations": report["iterations_per_heavy_fragment"],
        "receivers": receivers,
        "scope": "Live data-pack decoding into signal.rx. Harness controls windows and verifies GPU truth outside measurement.",
    }
    (directory / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    for receiver in receivers:
        print(
            f"{receiver['tick_rate']} TPS · live position receiver: {receiver['correct']}/{receiver['total']}, {receiver['abstentions']} unresolved"
        )


def scan_levels(samples):
    levels = []
    for power in sorted({sample["power"] for sample in samples}):
        subset = [s for s in samples if s["power"] == power]
        values = [s["water"]["value"] / 1000 for s in subset if s["water"]["valid"]]
        if not values:
            continue
        levels.append(
            {
                "power": power,
                "count": len(subset),
                "valid": len(values),
                "min_ms": min(values),
                "median_ms": median(values),
                "max_ms": max(values),
                "values_ms": values,
            }
        )
    ordered = sorted(
        (s for s in levels if s["valid"] == s["count"]), key=lambda s: s["median_ms"]
    )
    candidates = []
    for selected in combinations(ordered, 4):
        margin = min(b["min_ms"] - a["max_ms"] for a, b in zip(selected, selected[1:]))
        if margin > 0:
            candidates.append(
                {
                    "powers": [s["power"] for s in selected],
                    "centers_ms": [s["median_ms"] for s in selected],
                    "minimum_observed_margin_ms": margin,
                }
            )
    return {
        "levels": levels,
        "four_level_candidate": max(
            candidates, key=lambda s: s["minimum_observed_margin_ms"]
        )
        if candidates
        else None,
    }


def analyze_water_speed(report, directory):
    samples = report["samples"]
    receivers = []
    for series in report["series"]:
        subset = [s for s in samples if s.get("series") == series["id"]]
        if not subset:
            continue
        truth = [s.get("symbol", s.get("bit")) for s in subset]
        received = [s["scoreboard_received"] for s in subset]
        correct = sum(a == b for a, b in zip(truth, received))
        window_seconds = sum(s["duration_ms"] for s in subset) / 1000
        wall_seconds = (
            series.get("wall_ms", sum(s["trial_wall_ms"] for s in subset)) / 1000
        )
        bits_per_symbol = series.get("bits_per_symbol", 1)
        receivers.append(
            {
                **series,
                "receiver": "data_pack_position",
                "correct": correct,
                "total": len(subset),
                "bits_per_symbol": bits_per_symbol,
                "total_bits": len(subset) * bits_per_symbol,
                "bit_errors": sum(
                    (value ^ symbol).bit_count()
                    for value, symbol in zip(received, truth)
                    if value >= 0
                ),
                "abstained_bits": received.count(-1) * bits_per_symbol,
                "errors": sum(
                    value >= 0 and value != bit for value, bit in zip(received, truth)
                ),
                "abstentions": received.count(-1),
                "decoded": received,
                "truth": truth,
                "accuracy": correct / len(subset),
                "wilson_95": wilson(correct, len(subset)),
                "nominal_bits_per_second": bits_per_symbol * 1000 / series["window_ms"],
                "window_bits_per_second": len(subset)
                * bits_per_symbol
                / window_seconds,
                "wall_bits_per_second": len(subset) * bits_per_symbol / wall_seconds,
                "correct_bits_per_wall_second": correct
                * bits_per_symbol
                / wall_seconds,
                "actual_tps_median": median(s["observed_tps"] for s in subset),
                "gpu_verified_symbols": sum(s["gpu_verified"] for s in subset),
            }
        )
    scans = [
        {
            "tick_rate": rate,
            **scan_levels(
                [s for s in samples if s["phase"] == "scan" and s["tick_rate"] == rate]
            ),
        }
        for rate in sorted({s["tick_rate"] for s in samples if s["phase"] == "scan"})
    ]
    rows = []
    for sample in samples:
        water = sample["water"]
        rows.append(
            {
                **{
                    k: sample.get(k)
                    for k in [
                        "phase",
                        "series",
                        "tick_rate",
                        "sequence",
                        "bit",
                        "symbol",
                        "power",
                        "window_ms",
                        "block",
                        "symbol_in_block",
                        "gpu_verified",
                        "trial_wall_ms",
                        "observed_tps",
                        "scoreboard_received",
                    ]
                },
                "feature_ms": water["value"] / 1000 if water["valid"] else None,
                "events": water["events"],
                "groups": water["groups"],
                "valid": water["valid"],
            }
        )
    if rows:
        with (directory / "samples.csv").open("w", newline="") as handle:
            writer = csv.DictWriter(handle, fieldnames=list(rows[0]))
            writer.writeheader()
            writer.writerows(rows)
    summary = {
        "result": report["result"],
        "experiment": report.get("experiment", "water_speed"),
        "native_scheduling": report["native_scheduling"],
        "observation_mode": report["observation_mode"],
        "autonomous_window": report["autonomous_window"],
        "sample_count": len(samples),
        "estimator": report["estimator"],
        "models": report["models"],
        "receivers": receivers,
        "load_scans": scans,
        "scope": "Exploratory single-machine measurements. signal.rx supplies decoded symbols. Wall throughput includes request delivery, reset, settling, guard and block verification; calibration is reported separately. Load scan candidates require held-out multi-level decoding trials.",
    }
    (directory / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    for receiver in receivers:
        print(
            f"{receiver['id']} · {receiver['correct']}/{receiver['total']}, {receiver['errors']} errors, {receiver['abstentions']} unresolved; {receiver['wall_bits_per_second']:.2f} bit/s wall"
        )
    for scan in scans:
        print(
            f"{scan['tick_rate']} TPS · four-level load candidate: {scan['four_level_candidate']}"
        )
