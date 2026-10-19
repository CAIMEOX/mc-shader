# Development and verification

Use the [README setup sequence](../README.md#build-and-run) to prepare Minecraft and Java dependencies. All commands below run from the project root.

## Build outputs

```sh
python3 scripts/build/build.py
```

| Output | Purpose |
| --- | --- |
| `build/resourcepack.zip` | Playable resource pack |
| `build/resourcepack-test.zip` | Resource pack with the GPU observation pass |
| `build/datapack.zip` | Gameplay data pack |
| `build/artifacts.json` | Minecraft version and artifact hashes |
| `build/manifold-build.json` | Protocol and geometry metadata for native tests |
| `build/launcher.zip` | Entry pack prepared by the verification runner |

The Haskell compiler lives in `codegen/`. Cabal dependencies are pinned by `cabal.project.freeze`. Python coordinates compilation and archive assembly using the standard library. The Gradle wrapper JAR is versioned so a fresh checkout can prepare the harness.

## Semantic checks

```sh
cabal test semantics --test-show-details=direct
```

These checks exercise domain interfaces: frame inverses, swept collision, periodic occupancy, cube transitions, support dependencies, circuit completion, wire-format round trips, and render-pass feedback.

Tests should compare structured state and behavior. Generated JSON, SNBT, and function formatting can change without changing semantics. Minecraft command validity is checked by loading the generated resources into the native client/server harness.

Maintenance checks verify cleanup boundaries, open-world protection, and creation of the launcher pack from the release archive:

```sh
python3 -m unittest discover -s scripts/tests
```

## Native suites

```sh
python3 scripts/verify/run_tests.py
python3 scripts/verify/run_tests.py --suite rings
```

Each run checks pure semantics, rebuilds the packs, and opens a visible Minecraft test client. `all` is the default. `MANIFOLD_TEST_SUITE` also selects a suite.

| Suite | Coverage |
| --- | --- |
| `hybrid` | Lattice exploration, native jumping, camera depth, gravity handoff, and session exit |
| `flight` | Six contact faces, swept collision, periodic boundaries, mouse input, and free-flight controls |
| `entry` | Launcher entry, Survival landings, respawn, exit, and the next world load |
| `shader` | Camera alignment, near-surface shading, carrier visibility gaps, expiry, transport, and playable-pack comparison |
| `joinery` | Joinery semantics, six-direction tool operations, periodic approach, HUD, wood-tone contrast, animation, undo, and assembly |
| `joinery-render` | Joinery materials, light-field variation, retained presentation, performance and six gravity views |
| `rings` | The complete Three Rings route, cube materials, held orientation, object activity, circuit relays, checkpoints, reload, and respawn |
| `continuity` | Platform-edge falling, momentum across windows, GPU camera motion, and all six gravity directions |
| `rendering` | GPU ray hits against independent periodic geometry, diagonal motion, room generation, and frame/tick timings |
| `ui` | English and Simplified Chinese messages, configured key bindings, quiet landings, help, and victory layout |

The test harness uses Fabric for observations and input automation. The release packs use vanilla commands and resource-pack shaders.

## Evidence and performance

`reports/native.json` records the selected suite, results, loaded artifact hashes, and screenshots. `--collect` collects an existing harness run and checks its hashes against the current build. Reports are local generated evidence and are excluded from Git.

| Report | Measurement |
| --- | --- |
| `reports/tick.json` | Executed command entries and function calls |
| `reports/tick-traces/` | Minecraft's native function traces |
| `reports/performance.json` | Server ticks, synchronous room builds, CPU render submission, and complete frame intervals |
| `reports/screenshots/` | Images from the latest native run |

Command counts and elapsed time answer different questions. A large `fill` can visit many block positions in one command. Frame intervals include presentation and the harness's 60 FPS cap. Compare measurements on the same host and workload, using the report's artifact hashes and framebuffer dimensions.

Three Rings compares local work with 3, 30, and 300 registered sleeping objects. Runtime work is separated from the incremental encoder because sequence-word changes can alter encoding cost.

If `reports/runtime-baseline.json` is present, the trace summary includes a comparison with that local baseline. Keep evidence needed for an active investigation or a performance comparison.

## Formatting

```sh
python3 scripts/dev/format.py
python3 scripts/dev/format.py --check
```

Install Ruff, Ormolu, and clang-format on `PATH`, or set `MANIFOLD_RUFF`, `MANIFOLD_ORMOLU`, and `MANIFOLD_CLANG_FORMAT` to their executables. Python formatting is configured in `pyproject.toml`; Java and GLSL use `.clang-format`.

## Cleaning generated files

Stop builds and native test clients, then preview the cleanup:

```sh
python3 scripts/dev/clean.py
python3 scripts/dev/clean.py --apply
```

The cleaner removes unpacked generated resources, Cabal output, project-local Gradle output and caches, formatter caches, and Python bytecode. It retains release ZIPs, build manifests, verification reports, and `vanilla-playground/`, including its installed packs and playable saves.

Existing saves can be launched using the retained ZIPs. Cleaning removes the native test fixture world; run verification again before creating another playground save. Build and test commands regenerate their intermediates. The global dependency cache under `~/.gradle/` is managed separately.

## Configuration

| Variable | Use |
| --- | --- |
| `MANIFOLD_JAVA_HOME` | Java 25 for the harness and vanilla launcher |
| `JAVA_HOME` | Fallback used by the Gradle helper |
| `MANIFOLD_CLIENT_JAR` | Local Minecraft 26.3 client JAR used by the pack builder |
| `MANIFOLD_TEST_SUITE` | Default native test suite |
| `MANIFOLD_RUFF` | Ruff executable |
| `MANIFOLD_ORMOLU` | Ormolu executable |
| `MANIFOLD_CLANG_FORMAT` | clang-format executable |

The supplied vanilla launcher reads the macOS runtime from `~/.gradle/caches/` and uses POSIX world locks. Its `--prepare-only` option installs the selected level's packs and writes launcher configuration without starting the client.

## Making changes

Keep level definitions, runtime state, rendering, and verification in their existing modules. Add domain properties for physics or state changes, then use the smallest native suite that exercises command or rendering behavior. Run the complete suite for changes shared across levels or the transport/render pipeline.

Keep commits focused on a coherent model, runtime, observation, or documentation change. Review the staged paths and leave generated resources and local worlds untracked.
