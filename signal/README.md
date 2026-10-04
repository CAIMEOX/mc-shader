# Impossible Signal in Minecraft

Send a message from a GLSL shader to a Minecraft data pack through client response
timing. The demo targets **Minecraft Java Edition 26.3** and prints the received
bits, characters, and CRC-checked message in chat.

The generated resource and data packs run in vanilla Minecraft. A Fabric harness
provides a visible playground, keyboard controls, and automated verification.

## Technique

The data pack sends requests through an `item_display`. Core shaders encode its
model color into two corner pixels, which the post effect reads. The shader
selects a light or heavy workload according to the bit it wants to transmit.

To observe that workload, the data pack applies an equivalent whole turn to the
player's yaw. The client replies on its main loop, and the server normalizes the
angle. Scheduled functions detect this transition and measure its timing. At
200 TPS, the server can poll roughly every 5 ms while rendering delays remain
visible in the client's replies.

The message demo calibrates a threshold, samples each requested bit, and assembles
`[length][ASCII payload][CRC-8]`. The frame-stream experiments let the shader
advance independently and decode consecutive reply intervals. A free-fall
receiver uses Y-position updates as another observable. These channels depend
on frame time and scheduling noise; calibration and error detection are part of
the design.

See the [protocol](docs/protocol.md) and [experiment guide](docs/experiments.md).

## Build and play

Requirements: **GHC 9.12.2**, **Cabal**, **Python 3.11+**, **Java 25**, and a desktop
session capable of running Minecraft. Python uses its standard library.

Run commands from this project directory (`cd signal` in the playground repo).
Prepare Minecraft and Fabric dependencies once, with network access:

```sh
export JAVA_HOME=/opt/homebrew/opt/openjdk@25
"$JAVA_HOME/bin/java" -cp harness/gradle/wrapper/gradle-wrapper.jar \
  org.gradle.wrapper.GradleWrapperMain -p harness \
  configureClientLaunch compileGametestJava compilePlayJava
```

Then open the playground:

```sh
python3 scripts/run/play.py
```

The launcher builds and installs both packs, enables OP commands, and sets
200 TPS. Press **R** to receive `hi from shader` and **X** to cancel. The client
stays open after reception, and the world is saved in `playground/`.

Use `--message 'hello'` to compile another message: 1–64 printable ASCII
characters. The launcher uses Gradle's offline mode after setup. It is tested on
Apple Silicon macOS and uses POSIX locks. Set `SIGNAL_JAVA_HOME` or `JAVA_HOME` to
select Java; the default is `/opt/homebrew/opt/openjdk@25`.

## Install the packs

```sh
python3 scripts/build/build.py
```

Install `build/resourcepack.zip` in the client's `resourcepacks/` and enable it.
Install `build/datapack.zip` in the world's `datapacks/`, then run `/reload`.
`SIGNAL_CLIENT_JAR` can select another local Minecraft 26.3 client JAR for builds.

Enable commands, disable VSync, set the frame limit to 120 FPS, and run:

```mcfunction
/tick rate 200
/function signal:ping/start
```

`/trigger signal.ping` also starts reception. Cancel with
`/function signal:ping/cancel`, and restore the usual rate with `/tick rate 20`.
One receiver is active at a time. Turn slightly away from zero yaw before starting.
The probe transiently clears the server's `OnGround` flag. Packs overriding the
`item`, `entity`, or `block` core shaders require pipeline integration.

## Development

```sh
python3 scripts/verify/run_tests.py
python3 scripts/run/play.py --smoke
python3 scripts/dev/format.py
python3 scripts/dev/format.py --check
```

Verification checks framing semantics and complete reception in a visible client.
The play smoke test checks OP commands and R/X controls. Reproduce the individual
channels with the commands in the [experiment guide](docs/experiments.md).

Formatting follows Ruff for Python and import ordering, Ormolu for Haskell, and
clang-format for Java and GLSL. JSON resources use two-space indentation. Install
the formatters on `PATH` or set `SIGNAL_RUFF`, `SIGNAL_ORMOLU`, and
`SIGNAL_CLANG_FORMAT`. Editor settings are in `.editorconfig`.

| Directory | Contents |
|---|---|
| `codegen/` | Haskell protocol and resource compiler, semantic tests |
| `shaders/` | Pixel transport, message selection, and GPU workload |
| `harness/` | Fabric playground and native verification |
| `scripts/` | Build, launch, verification, experiments, and formatting |
| `docs/` | Protocol and reproducible experiment designs |

Generated packs, worlds, and reports are local outputs. Reports contain runtime
configuration, decoded data, accuracy, timing, and loaded pack hashes.
