# Experiment design and reproduction

Run these commands from the **Signal project root**, after the dependency setup
in the [README](../README.md). Keep the Minecraft window visible during sampling.
The launchers use native client/server scheduling, install both packs, record
pack hashes, restore 20 TPS, and close when verification finishes.

## Message reception

```sh
python3 scripts/verify/run_tests.py
python3 scripts/verify/run_tests.py --message 'hello'
python3 scripts/run/play.py --smoke
```

The message verifier starts one session and polls its data-pack state until EOF.
It checks decoded bits and bytes, character output, CRC, the final message, and
effect cleanup. The play smoke test exercises OP commands and the R/X bindings.
The frame layout and recovery rules are described in the [protocol](protocol.md).

## Rotation frame stream

```sh
python3 scripts/bench/run.py --rotate-stream --payload-start 54000
python3 scripts/bench/run.py --rotate-stream --payload-start 57000 --rotate-activities
```

At 200 TPS, the data pack rearms an equivalent whole-turn yaw marker after each
reply. It records reply intervals, merges short bursts, and classifies each
complete interval into a bit. The shader advances independently; the runner sends
one stream request and polls the resulting command storage.

The workload scan selects levels near 60 and 100 ms. Four 64-bit streams exercise
zeroes, ones, alternating bits, and digest bits computed by the shader.
`--payload-start` chooses the digest seed. The reference bits are used to score
completed reception. Packet/frame timestamp observers are disabled, and GPU
readback occurs outside sampling.

`--rotate-activities` repeats the digest stream while walking, turning, jumping,
and mining. Checks cover position, angle tracking, jump height, actual block
removal, live scoreboard output, and compensation of whole turns. Setup places
the player on a dry platform at Y=64 before sampling.

For an isolated input check with the probe off and on:

```sh
python3 scripts/bench/run.py --rotate-stream --stream-stage controls
```

The mining fixture brings the visible game window forward and captures its mouse
before holding attack. The control check starts with the mouse released, then
verifies capture recovery and actual block destruction.

## Free-fall frame stream

```sh
python3 scripts/bench/run.py --fall --payload-start 52000
python3 scripts/bench/run.py --fall --payload-start 53000
```

This uses the same frame sender and decoder, with Y-position changes as the
observable. An Adventure-mode player falls from Y=1024. Teleports and GPU setup
checks occur before sampling; checks require downward updates and airborne
movement throughout the window.

The data pack polls each server tick, merges short bursts, detects delimiters,
and writes its decisions to `signal:fall bits` and `signal.rx`. `/stopwatch`
supplies diagnostics and timeouts; bit classification uses tick counts. Fresh
seeds and the four source patterns test timing separation and stream alignment.

## Windowed rotation

```sh
python3 scripts/bench/run.py --rotate --rates 200 \
  --rotate-powers 4 --rotate-activities --rotate-fps --payload-start 48000
```

This receiver averages complete rotation-response delays over 500 ms. Known
light/heavy calibration windows train a threshold; shader-computed payloads test
the live `signal.rx` decision. Averaging permits lighter workloads while requiring
more time per bit.

`--rotate-activities` compares ordinary inputs with probing enabled and disabled.
`--rotate-fps` measures the game's FPS counter at steady workloads. Use
`--rotate-stage probe` for a shorter heading and calibration check, or scan powers
and rates with `--rates 20 200 --rotate-powers 4 8 32`.

## Water position receiver

```sh
python3 scripts/bench/run.py --water --rates 20 200 --payload-start 16000
python3 scripts/bench/run.py --water-speed --rates 200 --payload-start 28000
python3 scripts/bench/run.py --water-four --rates 200 \
  --levels 0 20 32 48 --payload-start 32000
```

Flowing water moves an Adventure-mode player through a shallow trough. The data
pack samples X position and decodes update intervals. The runner arranges resets
and calibration, then compares the live scoreboard with the shader reference.

`--water` uses 1.5-second windows. `--water-speed` compares 500, 400, and 300 ms
windows and workload levels. `--water-four` maps two-bit symbols to four calibrated
workloads in Gray order. Stable trials reset each symbol; continuous trials reset
at block boundaries. Select a case with `--speed-cases`, `--window-ms`,
`--guard-ms`, and `--skip-scan`.

## Packet timing and server clock

```sh
python3 scripts/bench/run.py --rates 200 500 1000 2000 --payload-start 1000
python3 scripts/bench/run.py --rates 500 4000 8000 \
  --payload-start 5000 --stopwatch-only --power 32
```

The shader hashes a request sequence and selects its workload from the digest's
low bit. Calibration trains timing decoders; balanced payloads evaluate them.
The instrumented mode timestamps client frames, tick-end sends, packet arrivals,
server handling, and server ticks. The data pack independently measures intervals
between its own ticks with `/stopwatch`.

`--stopwatch-only` disables timestamp observers and fixes the workload with
`--power`. Decoder inputs use observations; request sequences and expected bits
are reserved for scoring. GPU truth checks occur outside each sampling window.

## Reading reports

| Output | Contents |
|---|---|
| `reports/native.json` | Observations, receiver state, configuration, and pack hashes |
| `reports/summary.json` | Accuracy, alignment errors, calibration, and throughput |
| `reports/samples.csv` | Per-window metrics for applicable experiments |
| `reports/play.json` | Interactive control checks |
| `reports/screenshots/` | Visible captures |
| `reports/runs/` | Archived evidence and matching packs |

Recollect the current installed experiment with
`python3 scripts/bench/run.py --collect`. Each report identifies the loaded packs.
A `passed` execution status means behavioral checks completed; inspect per-trial
accuracy and observed TPS separately.

Frame-stream reports distinguish data intervals from receiver time including
warmup and delimiters. Measurement-window capacity and total wall throughput are
separate quantities. Repeat with fresh seeds and inspect substitutions,
insertions, deletions, and unresolved decisions. The supplied setup uses a local
integrated-server connection; other hardware and remote connections require their
own calibration and measurements.
