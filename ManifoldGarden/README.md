# Manifold in Minecraft

A gravity puzzle playground for Minecraft Java Edition **26.3**, inspired by the repeating architecture of Manifold Garden. Walk on walls, fall through periodic space, and use directional cubes to create landing surfaces and connect circuits.

The playable data pack and resource pack run in vanilla Minecraft. Real blocks provide nearby collision and interaction; shaders shade the architecture and extend it into an infinite view. A Haskell compiler generates both representations from shared level definitions. The Fabric harness supplies automated verification and GPU observations during development.

## Requirements

- **GHC 9.12.2** and **Cabal** for the resource compiler.
- **Python 3.11+** for build, verification, and launch scripts; only the standard library is required.
- **Java 25** for Minecraft and the Fabric harness.
- A desktop session capable of running Minecraft Java Edition **26.3**.

The supplied vanilla launcher is tested on Apple Silicon macOS and uses the macOS libraries in the Gradle runtime cache. Set `MANIFOLD_JAVA_HOME` to your Java 25 installation; its default is `/opt/homebrew/opt/openjdk@25`. The Gradle helper also accepts `JAVA_HOME`.

## Build and run

Run commands from the directory containing this README (`cd Manifold` in the playground repository).

Prepare Minecraft, Fabric, and the development launch configuration once, with network access:

```sh
export MANIFOLD_JAVA_HOME=/opt/homebrew/opt/openjdk@25
"$MANIFOLD_JAVA_HOME/bin/java" -cp harness/gradle/wrapper/gradle-wrapper.jar \
  org.gradle.wrapper.GradleWrapperMain -p harness \
  configureClientLaunch compileGametestJava
```

The verification scripts use Gradle's offline mode after this setup. Build the packs, verify them in Minecraft, and launch Three Rings:

```sh
python3 scripts/verify/run_tests.py
python3 scripts/run/vanilla.py --level three-rings
```

Verification creates the seed world used when the launcher creates a new playground save. Once that save exists, launch it directly with the second command. Rebuild after source changes with:

```sh
python3 scripts/build/build.py
```

The build reads vanilla shaders from `~/.gradle/caches/fabric-loom/26.3/minecraft-client.jar`. Set `MANIFOLD_CLIENT_JAR` to use another local **26.3** client JAR. Build outputs include playable packs, a diagnostic resource pack, and artifact hashes.

## Scenes and controls

Atrium is an open lattice for exploring six-axis gravity. Three Rings uses directional cubes and circuits. Joinery Court is a six-member timber assembly with gravity-directed sliding joints.

| Level | Launcher option | In-world entry | Guide |
| --- | --- | --- | --- |
| Joinery Court | `--level joinery` | `/function manifold:joinery/start` | [Timber interlocks and periodic slides](docs/levels/joinery.md) |
| Three Rings | `--level three-rings` | `/function manifold:three_rings/start` | [Cube relays and periodic delivery](docs/levels/three-rings.md) |
| Atrium | `--level atrium` (default) | `/function manifold:start` | [Explore the repeating lattice](docs/levels/atrium.md) |

| Control | Action |
| --- | --- |
| WASD and mouse | Move and look around |
| Right mouse button | Pick up/place cubes in Three Rings; use the held Joinery Tool on any visible timber in Joinery Court |
| Sprint key, Ctrl by default | While grounded with a clear body pose, turn gravity toward your view; place carried cubes first |
| Space | Jump using native movement |
| `/function manifold:help` | Show controls and guidance for the active level |
| `/function manifold:reset` | Restart the current puzzle |
| `/function manifold:stop` | Return to the saved entry position and game mode |

Game text follows the client's language setting, with **English** and **Simplified Chinese** catalogs. Chapter names appear briefly on entry, blocked actions receive short feedback, and victory retains its title and subtitle. Help resolves the player's configured key bindings.

The default render quality is `balanced`. Select a preset with `/function manifold:quality/low`, `/function manifold:quality/balanced`, `/function manifold:quality/high`, or `/function manifold:quality/native`.

Three Rings saves checkpoints at puzzle milestones. Use `/function manifold:three_rings/checkpoint/restore` to restore the player, cubes, and circuits together. Its save is `vanilla-playground/saves/Three Rings/`; Atrium uses `vanilla-playground/saves/Manifold/`.

Joinery Court saves after each slide. `/function manifold:joinery/undo` restores the previous assembly and safe standing position; `/function manifold:joinery/checkpoint/restore` returns to its checkpoint.

For free-flight exploration, use `/function manifold:flight`. Movement keys fly, Space and Shift rise and descend, Ctrl selects gravity, and Space + Shift toggles flight. `/function manifold:help` lists the active bindings.

## Install in a world

| Artifact | Destination |
| --- | --- |
| `build/resourcepack.zip` | The client's `resourcepacks/` directory; enable it in Resource Packs |
| `build/datapack.zip` | The world's `datapacks/` directory |

Use Minecraft **26.3**, enable commands, and reopen the world after first installation to register the `manifold:stage` dimension. Enter a level with one of the commands above. After updating both packs, run `/reload` and press **F3+T**.

The session selects Adventure mode and applies player-specific fall protection. Survival mode also supports native movement. Three Rings and Joinery Court restore their checkpoints after death; Atrium restarts at its entrance. The supplied playground additionally disables fall damage in its own world and prepares an overworld entrance platform.

The resource pack supplies `minecraft:end_of_frame` and patches the `item`, `entity`, and `block` core shaders. Other packs replacing these files require pipeline integration.

## How it works

1. **Shared scene definitions** produce collision commands, native room geometry, object state, and shader geometry.
2. **Two physical room caches** give the player native movement and interaction in the current orientation. Relative teleports rebase periodic windows while preserving falling momentum.
3. **A logical controller** handles gravity turns and airborne collision until native movement resumes on landing.
4. **Pixel transport** sends camera, controller, and object state from data-pack entities to the resource pack.
5. **Rendering** reconstructs the native camera, validates nearby surfaces, and traces the periodic architecture. Three Rings uses exact ray/box intersections through a compiled hierarchy.

See [architecture](docs/architecture.md) for the runtime states, transport format, and extension points.

## Verification

```sh
cabal test semantics --test-show-details=direct
python3 scripts/verify/run_tests.py
python3 scripts/verify/run_tests.py --suite ui
```

Semantic checks cover physics, periodic occupancy, object transitions, circuits, protocol encoding, and render-pass feedback. Native checks exercise gameplay through keyboard and mouse input, inspect server state and GPU output, and measure command workload and elapsed time.

Reports are generated in `reports/`, including `native.json`, `tick.json`, and `performance.json`. They record the hashes of the loaded packs. [Development and verification](docs/development.md) describes the focused suites, evidence, formatting, and cleanup commands.

## Source layout

| Directory | Contents |
| --- | --- |
| `codegen/src/Manifold/` | Domain models, data-pack generators, language catalogs, and render compiler |
| `codegen/app/` | Resource compiler entry point |
| `codegen/test/` | Semantic tests |
| `shaders/core/` | Pixel-carrier patches for vanilla shaders |
| `shaders/include/` | Camera, transport, materials, and geometry routines |
| `shaders/post/` | Packet reception, frame state, rendering, and compositing |
| `scripts/build/` | Cabal compilation and pack assembly |
| `scripts/run/` | Vanilla playground launcher |
| `scripts/verify/` | Native verification and report collection |
| `scripts/dev/` | Formatting and generated-file cleanup |
| `harness/` | Fabric test fixtures and observations |
| `docs/` | Architecture, development, and level guides |
| `build/` | Generated resources, release ZIPs, and manifests |
| `reports/` | Local verification evidence |
| `vanilla-playground/` | Local playable saves, installed packs, and runtime files |

Generated files and local worlds are excluded from version control. Preview reproducible intermediates with `python3 scripts/dev/clean.py`, then use `--apply` to remove them. Release ZIPs, manifests, reports, and playable saves are retained.

## Scope

One player controls the active session. Gravity has six axial directions and 24 orientation frames. Three Rings and Joinery Court have a 64-block logical period; Atrium uses 32 blocks. The architecture repeats visually while the data pack maintains one authoritative puzzle state.

Use first-person view. Selecting Creative or Spectator manually exits an active room session. The supplied launcher and native graphics verification target macOS; the packs' behavior on other graphics backends should be verified on that hardware.
