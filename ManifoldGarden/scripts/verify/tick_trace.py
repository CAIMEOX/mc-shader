"""Summarize Minecraft function traces into command-entry performance metrics."""

from collections import Counter
import json
import re


def parse_trace(path):
    stack = {}
    calls = Counter()
    commands = Counter()
    diagnostics = []
    for line in path.read_text().splitlines():
        event = re.match(r"^(\s*)\[([FC])\] (.*)", line)
        if event:
            indent = len(event[1])
            stack = {depth: name for depth, name in stack.items() if depth < indent}
            if event[2] == "F":
                function = event[3].split()[0]
                stack[indent] = function
                calls[function] += 1
            else:
                commands[stack[max(stack)]] += 1
        elif "[E]" in line:
            diagnostics.append(line.strip())
    encoder = sum(
        count
        for name, count in commands.items()
        if name == "manifold:send" or name.startswith("manifold:transport/")
    )
    return {
        "command_entries": sum(commands.values()),
        "encoder_commands": encoder,
        "runtime_commands": sum(commands.values()) - encoder,
        "calls": dict(calls),
        "commands_by_function": dict(commands),
        "trace": "tick-traces/" + path.name,
        "diagnostics": sorted(set(diagnostics)),
    }


def summarize(traces, reports, build_info):
    result = {
        "minecraft": "26.3",
        "build": build_info,
        "measurement": "Minecraft debug function trace, one invocation per phase. "
        "Command entries include conditional checks; these counts are not timings.",
        "phases": {
            path.stem.removeprefix("manifold-tick-"): parse_trace(path)
            for path in traces
        },
    }
    baseline_path = reports / "runtime-baseline.json"
    if baseline_path.exists():
        baseline = json.loads(baseline_path.read_text())
        result["comparison"] = {
            name: {
                "baseline_commands": baseline["phases"][name]["command_entries"],
                "current_commands": phase["command_entries"],
                "reduction_percent": round(
                    100
                    * (
                        1
                        - phase["command_entries"]
                        / baseline["phases"][name]["command_entries"]
                    ),
                    2,
                ),
            }
            for name, phase in result["phases"].items()
            if name in baseline["phases"]
        }
    (reports / "tick.json").write_text(
        json.dumps(result, ensure_ascii=False, indent=2) + "\n"
    )
    return result
