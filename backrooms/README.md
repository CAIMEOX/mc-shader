# Backrooms in Minecraft

A procedural Level 0 dimension for Minecraft Java Edition **26.3**, with independently generated floors at **Y=52, 64, and 76**. Yellow rooms, corridors, and furnished spaces connect through ladder rooms, switchback stairs, square spiral stairs, deep shafts, and split-level atriums.

Haskell compiles the world-generation rules and structure assets. Minecraft evaluates the room layouts from the world seed as chunks generate. The data pack and material resource pack run in vanilla Minecraft; the Fabric harness supplies development controls and automated verification.

## Requirements

- **GHC 9.12.2** and **Cabal** for the resource compiler.
- **Python 3.11+** for build, verification, and launch scripts. These scripts use the standard library.
- **Java 25** for Minecraft and the Fabric harness.
- A desktop session capable of running Minecraft Java Edition **26.3**.

The supplied launcher is tested on Apple Silicon macOS. It uses POSIX file locks and defaults to Homebrew Java at `/opt/homebrew/opt/openjdk@25`. Set `BACKROOMS_JAVA_HOME` or `JAVA_HOME` to use another Java 25 installation. Haskell dependencies are pinned in `cabal.project.freeze`.

## Build and run

Run commands from the Backrooms project root (`cd backrooms` in the playground repository).

Prepare Haskell dependencies and the Minecraft development environment once, with network access:

```sh
cabal update
cabal build all --enable-tests

export JAVA_HOME=/opt/homebrew/opt/openjdk@25
"$JAVA_HOME/bin/java" -cp harness/gradle/wrapper/gradle-wrapper.jar \
  org.gradle.wrapper.GradleWrapperMain -p harness \
  configureClientLaunch compileGametestJava compilePlayJava
```

The Python build and launch scripts use the cached dependencies in offline mode. Run the visible Minecraft verification, then open the playground:

```sh
python3 scripts/verify/run_tests.py
python3 scripts/run/play.py
```

Verification creates the initial world used by the playground. After setup, launch with one command:

```sh
python3 scripts/run/play.py
```

To rebuild the packs after editing sources:

```sh
python3 scripts/build/build.py
```

The build reads vanilla resources from `~/.gradle/caches/fabric-loom/26.3/minecraft-client.jar`. Set `BACKROOMS_CLIENT_JAR` to use another local **26.3** client JAR. `BACKROOMS_PACKAGE_DB` can select an existing Cabal package database when the build creates `cabal.project.local`.

## Playground controls

The launcher installs the data pack and material pack into `playground/`, enables commands, and enters `backrooms:interior` at **Y=64**, the middle floor.

| Control | Action |
|---|---|
| **WASD**, mouse, **Space** | Walk, look, and jump |
| **F7** | Return to the entrance on the middle floor |
| **X** | Restore the dimension, position, orientation, and game mode saved on entry |
| Walk toward a ladder | Climb and step onto its top landing |
| Sneak on a ladder | Hold position; move sideways to enter an intermediate floor |

The interactive save is `playground/saves/Backrooms Level 0`. When a rebuilt data pack changes the generated world, the launcher moves the existing save into `playground/backups/` and installs a world from the matching native verification. It checks the save's session lock before installing packs.

To prepare the playground without opening Minecraft:

```sh
python3 scripts/run/play.py --prepare-only
```

## Install the packs in a world

The build produces three archives:

| File | Purpose |
|---|---|
| `build/datapack.zip` | World generation, structures, session controls, and ambient audio |
| `build/materialpack.zip` | Wallpaper, carpet, ceiling, and fluorescent-light textures |
| `build/resourcepack.zip` | Optional resource pack for the spatial shader lab |

Install `datapack.zip` in the world's `datapacks/` directory and enable `materialpack.zip` in the client's Resource Packs menu. Install the data pack before creating or loading the world, and keep structure generation enabled. Use Minecraft **26.3** and enable commands:

```mcfunction
/function backrooms:enter
/function backrooms:home
/function backrooms:exit
```

Players can also use `/trigger backrooms.action set 3` to return to the entrance and `set 2` to leave. The playground's F7 and X controls use these same entry points.

Existing chunks retain their saved geometry. Updated generation rules apply to newly generated chunks; the managed playground uses a verified save for the current build.

## How it works

1. **Floor planning.** Three floors share a 12-block vertical pitch. Each floor samples a distinct noise plane and has a separately scoped planning graph, allowing Minecraft to cache room decisions in XZ. Walls and room choices stay consistent across chunk boundaries.
2. **Room layout.** Each floor uses 48 × 48 planning regions. Seeded rules choose subdivision, circulation, doors, room proportions, ceilings, and furniture. Dense regions subdivide up to eight times along a query path; other room groups use up to six divisions.
3. **Vertical circulation.** Ladder rooms, switchback stairs, and square spiral stairs reserve their footprints before surrounding rooms are divided. Their position, orientation, landings, and openings are shared across all three floors. Explicit air and block-state rules form stair openings, platforms, and ladder backing.
4. **Materials and lighting.** Density masks select full block states through native material rules, including stair and ladder properties. Nine furnishing families supply alcoves, columns, archives, meeting areas, galleries, maintenance rooms, screens, lounges, and carrels. Lighting follows room geometry and reserved corridors.
5. **Landmarks.** Shafts, Pitfalls, and split-level atriums compile to compact NBT structures placed by Jigsaw. Collars and ladders connect them to the three-floor network. Landmark candidates and vertical cores occupy disjoint areas of a 192 × 192 planning period.

| Region layout | Organization |
|---|---|
| Dense | Small rooms, short turns, and low ceilings; minimum subdivision span of five blocks |
| Suites | Mixed room proportions and occasional shared spaces; minimum span of six blocks |
| Spine | A three-block-wide corridor with offset branches and subdivided side rooms |
| Ring | A three-block-wide loop around a central space, with rooms outside the loop |
| Vertical core | A reserved stair or ladder room, a surrounding corridor, and subdivided side rooms |

Ordinary regions use noise-quantile selection slots weighted **3:2:2:1** for Dense, Suites, Spine, and Ring. Vertical-core regions are assigned by the circulation plan. Actual proportions depend on the world seed and sample area.

| Structure | Geometry |
|---|---|
| Ladder room | 9 × 9 footprint; a backed ladder and landings on all three floors |
| Switchback stairs | 17 × 17 footprint; two-block-wide flights with intermediate platforms |
| Square spiral stairs | 11 × 11 footprint; four flights per storey around a central column |
| Deep shaft | 42 × 38 body with a 24 × 24 opening, galleries, return stairs, and a catch pool about 48 blocks below the main floor |
| Pitfalls | 38 × 34 body with twelve pits, a narrow bridge, lower passages, and return stairs |
| Split-level atrium | 40 × 36 body with platforms at Y=56, 60, 64, and 68, raised openings, and ladders |

Landmark candidates are 192 blocks apart. Each of the three landmark types has selection weight 1; the empty choice has weight 4. Ordinary room layouts, furnishings, and vertical cores are evaluated during world generation.

## Verification

```sh
cabal test --offline semantics --test-show-details=direct
python3 scripts/verify/run_tests.py
python3 scripts/run/play.py --smoke
```

The Haskell suite checks density references, scoped evaluation, floor identities, room bounds, seeded layout variation, circulation reservations, furniture clearance, block-state semantics, connected stair paths, ladder backing, texture pixels, and NBT round trips.

Native verification opens a visible Minecraft window, loads the generated packs, and compares actual terrain and block states with the loaded rules. It checks distinct floor layouts, room distributions, three-dimensional connectivity, both core orientations, landmark placement, reversed chunk-loading order, and cold-chunk request times. A player walks up and down complete stair routes, uses ladder exits, falls into catch pools, and exercises session controls.

Results are written to `reports/native.json` and `reports/play.json`, with loaded-pack hashes and screenshots in `reports/screenshots/`. `runtime-floors.png` compares all three floor plans; `runtime-layouts.png` shows the region families. Timings describe the sampled requests on the machine running the tests.

To collect an existing native run's evidence:

```sh
python3 scripts/verify/run_tests.py --collect
```

## Source layout

| Directory | Contents |
|---|---|
| `codegen/src/Backrooms/WorldGen/` | Floor, layout, partition, furnishing, lighting, circulation, navigation, and landmark models |
| `codegen/src/Backrooms/WorldGen.hs` | World-generation registries, material rules, metadata, and structure serialization |
| `codegen/src/Backrooms/Structure/` | NBT encoding and decoding |
| `codegen/src/Backrooms/` | Pack assembly, data-pack functions, and spatial shader-lab models |
| `codegen/app/` | Resource compiler entry point |
| `codegen/test/` | Semantic checks |
| `shaders/core/` | Shader-lab patches for vanilla core shaders |
| `shaders/include/` | Shared encoding, camera, geometry, and material routines |
| `shaders/post/` | Spatial shader-lab rendering passes |
| `scripts/build/` | Cabal compilation and reproducible pack assembly |
| `scripts/run/` | Interactive playground launcher |
| `scripts/verify/` | Native verification and report collection |
| `scripts/common/` | Shared project paths and Java launcher configuration |
| `scripts/dev/` | Source formatting |
| `harness/` | Gradle wrapper, Fabric playground, and Minecraft integration tests |
| `build/` | Generated resources, metadata, and release ZIPs |
| `playground/` | Interactive save, backups, and launcher logs |
| `reports/` | Generated verification evidence |

Start with `WorldGen/Runtime.hs` for scene assembly, `Floors.hs` for floor configuration, `Layout.hs` and `Partition.hs` for room planning, and `Vertical.hs` for cross-floor structures. `Furniture.hs` owns furnishing shapes and finishes; `Landmark.hs` owns the Jigsaw structures.

Generated density rules are under `build/datapack/data/backrooms/worldgen/`; structure templates are under `build/datapack/data/backrooms/structure/interior/`. `build/worldgen.json` describes floors, materials, layouts, core traversal paths, and landmark verification points.

Source formatting follows Ruff, Ormolu, and clang-format:

```sh
python3 scripts/dev/format.py
python3 scripts/dev/format.py --check
```

Install these tools on `PATH`, or set `BACKROOMS_RUFF`, `BACKROOMS_ORMOLU`, and `BACKROOMS_CLANG_FORMAT`. Generated packs, caches, reports, and local worlds are excluded from version control.

## Spatial shader lab

The project also contains a shader-based spatial experiment with portal transforms, a display-pixel transport protocol, and a ray-marched scene. Its entry point is `/function backrooms:lab/enter`, used with `build/resourcepack.zip`. The relevant Haskell modules are `Domain`, `Protocol`, `Pipeline`, and `Program`; rendering sources are in `shaders/`.

## Scope

World generation targets Minecraft Java Edition **26.3** and currently supplies three ordinary floors. Landmarks can extend below that range. The session controls and managed playground are designed for single-player worlds.

The material pack replaces the vanilla textures for `end_stone`, `brown_wool`, `white_concrete`, and `sea_lantern`; these textures also apply to those blocks in other dimensions. The shader lab supplies a separate post-processing pipeline and core-shader patches.
