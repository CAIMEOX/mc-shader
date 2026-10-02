# Flame in Minecraft

A terrain-aware fire and smoke simulation for Minecraft Java Edition **26.3**. A data pack samples nearby blocks and supplies ignition events; GLSL shaders simulate heat transfer, fuel consumption, combustion, and buoyant smoke, then render the result into the world.

Fire spreads across combustible surfaces and leaves a visual char layer as fuel runs out. The simulation is entirely visual: world blocks remain intact and entities take no damage. The generated resource and data packs run in vanilla Minecraft. The Fabric harness provides development controls and automated verification.

## Requirements

- **GHC 9.12.2** and **Cabal** for the resource compiler.
- **Python 3.11+** for build, verification, and launch scripts.
- **Java 25** for Minecraft and the Fabric harness.
- A desktop session capable of running Minecraft Java Edition **26.3**.

The supplied launcher is tested on Apple Silicon macOS. It uses POSIX file locks and defaults to Homebrew Java at `/opt/homebrew/opt/openjdk@25`. Set `FLAME_JAVA_HOME` or `JAVA_HOME` to use another Java 25 installation. Python scripts use the standard library; the Haskell compiler uses libraries bundled with GHC.

## Build and run

Run commands from the Flame project root (`cd flame` in the playground repository).

First, prepare Minecraft, Fabric, and the development launch configuration with network access:

```sh
export JAVA_HOME=/opt/homebrew/opt/openjdk@25
"$JAVA_HOME/bin/java" -cp harness/gradle/wrapper/gradle-wrapper.jar \
  org.gradle.wrapper.GradleWrapperMain -p harness \
  configureClientLaunch compileGametestJava compilePlayJava
```

The Python launch scripts use Gradle's offline mode after this setup. Build the packs, run the visible Minecraft tests, and open the playground:

```sh
python3 scripts/verify/run_tests.py
python3 scripts/run/play.py
```

Verification also creates the initial world used by the playground. After setup, launch with one command:

```sh
python3 scripts/run/play.py
```

To rebuild the packs after editing sources:

```sh
python3 scripts/build/build.py
```

The build reads the vanilla core shaders from `~/.gradle/caches/fabric-loom/26.3/minecraft-client.jar`. Set `FLAME_CLIENT_JAR` to use another local **26.3** client JAR.

## Playground controls

The playground enables commands and starts in spectator mode. Use `/gamemode creative` to edit the scene.

| Control | Action |
|---|---|
| **R** | Ignite the targeted block, up to 16 blocks away |
| **X** | Extinguish flames and cool the region, retaining spent fuel |
| **F7** | Resample terrain and initialize fresh simulation state |
| **F6** | Rebuild the demonstration scene and start the igniter |

The demonstration occupies `(0, 64, 0)` through `(15, 71, 15)`. **F6 replaces blocks in that region.** After placing or removing blocks, press F7 to update the shader's terrain snapshot. Resampling also restores the initial fuel for the sampled materials.

The launcher keeps the interactive world in `playground/` and checks its session lock before installing packs. View Bobbing is disabled for the camera reconstruction used by this demo.

## Install the packs in a world

The build produces two release artifacts:

| File | Installation location |
|---|---|
| `build/resourcepack.zip` | The client's `resourcepacks/` directory; enable it in Resource Packs |
| `build/datapack.zip` | The world's `datapacks/` directory; load it with `/reload` |

Use Minecraft **26.3**, enable commands, and turn **View Bobbing off**. For the supplied scene, run:

```mcfunction
/function flame:demo
```

This replaces the demonstration region listed above. To use existing terrain instead, choose the lower corner of a loaded 16 × 8 × 16 block region:

```mcfunction
/execute positioned 0 64 0 run function flame:start
```

The position is aligned to the block grid and becomes the region origin. Sampling takes eight batches over about 0.4 seconds. Once it completes, ignite a block inside the region:

```mcfunction
/execute positioned 3 65 8 run function flame:ignite
```

Controls are also available through commands:

| Command | Effect |
|---|---|
| `/function flame:source/off` | Stop external heating; established combustion can continue |
| `/function flame:source/on` | Enable the igniter at its current position |
| `/function flame:quench` | Cool the region and suppress combustion until ignition resumes |
| `/function flame:rescan` | Refresh terrain and reset simulation state |
| `/function flame:reset` | Restore fuel and gas state from the current snapshot, retaining the control mode |

Players can use `/trigger flame.action set 1` for crosshair ignition, `set 2` to extinguish, and `set 3` to resample. These are the same command entry points used by the playground controls.

Igniter power is encoded in units of 1/64, with a default score of 128 and a supported score range of 0–511:

```mcfunction
/scoreboard players set #power flame 96
/function flame:send
```

The resource pack supplies `minecraft:end_of_frame` and overrides the `item`, `entity`, and `block` core shaders. Resource packs that replace these same files require pipeline integration.

## How it works

1. **Terrain sampling.** Context integer providers classify each block's shape and fuel material. Full blocks, upper and lower slabs, and all stair orientations map to a palette of 28 half-block collision masks. Other shapes use a full-block approximation. Waterlogged blocks receive the inert material profile.
2. **Pixel transport.** Each block uses seven bits: five for geometry and two for material. The 2,048-block region occupies 598 RGB words; the origin, epoch, igniter position, power, and mode bring the server payload to 603 colors. A single `item_display` carries these through `custom_model_data`. Core shaders add camera data and a marker, writing 608 pixels into a 32 × 19 corner region. Post-processing receives the packet and repairs the visible corner.
3. **Surface combustion.** Exposed solid cells store remaining fuel, temperature, and pyrolysis rate. Conduction, nearby hot gas, and an occlusion-aware local radiation approximation heat the material. Pyrolysis releases fuel vapor into neighboring air cells; its reaction with oxygen releases heat and produces smoke. This heat can ignite further surfaces.
4. **Air flow.** A staggered MAC velocity grid uses semi-Lagrangian advection, buoyancy, vorticity confinement, and pressure projection. Gas transport checks obstacles and excludes solid cells from interpolation. Persistent render targets store scalar values as float32 bits packed into RGBA8.
5. **Volume rendering.** Ray marching integrates flame emission and smoke extinction. A coarse occupancy grid skips empty space. Depth-aware upsampling and additional rays at occlusion edges composite the volume with the scene. Surface shading shows char and embers; procedural detail refines the visible flames.

| Simulation setting | Value |
|---|---|
| World region | 16 × 8 × 16 blocks |
| Solver grid | 32 × 16 × 32 cells, half a block per cell |
| Time step | 1/30 second, up to two steps per rendered frame |
| Pressure solver | 24 weighted Jacobi iterations per step |
| Volume render target | 640 × 360, upsampled to the game window |
| Boundaries | Closed sides and bottom; open top |

Fuel profiles use normalized demo units:

| Material | Block groups | Initial surface fuel | Pyrolysis threshold |
|---|---|---:|---:|
| Wood | Logs, planks, wooden stairs and slabs | 1.0 | 540 K |
| Foliage | Leaves | 0.3 | 470 K |
| Cloth | Wool, wool stairs and slabs | 0.8 | 570 K |
| Inert | Remaining materials and waterlogged blocks | 0 | — |

## Verification

```sh
cabal test semantics --test-show-details=direct
python3 scripts/verify/run_tests.py
python3 scripts/run/play.py --smoke
```

The Haskell suite checks collision masks, grid addressing, protocol round trips, bit fragments used by command generation, and pipeline references. Native tests load the generated packs in a visible Minecraft window and inspect GPU state from the same rendered frame.

The native suite covers terrain and material transport, ignition, pressure projection, sustained combustion, propagation, world preservation, improved transparency, extinguishing, solid barriers, inert materials, and fuel exhaustion. It also measures frame rate during active burning at a 3456 × 2234 framebuffer. The playground smoke test exercises extinguishing, crosshair ignition, and terrain updates through the normal command path.

Results are written to `reports/native.json` and `reports/play.json`, with screenshots in `reports/screenshots/`. Reports include the hashes of the loaded resource and data packs. Frame-rate measurements depend on hardware, the scene, and the frame limit recorded in the report.

## Source layout

| Directory | Contents |
|---|---|
| `codegen/src/Flame/` | Haskell domain model, protocol, data pack, and render pipeline compiler |
| `codegen/app/` | Resource compiler entry point |
| `codegen/test/` | Semantic checks |
| `shaders/core/` | Pixel-carrier patches for vanilla core shaders |
| `shaders/include/` | Shared encoding, grid, camera, and volume routines |
| `shaders/post/` | Simulation and rendering passes |
| `scripts/build/` | Cabal compilation and pack assembly |
| `scripts/run/` | Interactive playground launcher |
| `scripts/verify/` | Native verification and report collection |
| `scripts/common/` | Shared project paths and Java launcher configuration |
| `scripts/dev/` | Source formatting |
| `harness/` | Fabric playground, test fixtures, and GPU observation |
| `build/` | Generated resources and release ZIPs |
| `playground/` | Local interactive world and logs |
| `reports/` | Generated verification evidence |

Dependencies are recorded in `cabal.project` and `cabal.project.freeze`. Source formatting follows Ruff, Ormolu, and clang-format:

```sh
python3 scripts/dev/format.py
python3 scripts/dev/format.py --check
```

Install these formatters on `PATH`, or specify their executables through `FLAME_RUFF`, `FLAME_ORMOLU`, and `FLAME_CLANG_FORMAT`. Generated packs, reports, caches, and local worlds are excluded from version control.

## Scope

Flame is a real-time visual model with parameters tuned for the demonstration. Its half-block grid and first-order advection smooth small flames and vortices; chemistry, radiative heating, smoke lighting, and transparent-surface composition are approximations.

One shared region is active at a time, with each client evolving its own visual state. Terrain is a snapshot: resampling, resource reloads, and reopening the playground initialize GPU state. Simulation ends at the region boundary, and burning surfaces retain their original geometry as their fuel is consumed.

## Reference

- [GPU Gems 3, Chapter 30: Real-Time Simulation and Rendering of 3D Fluids](https://developer.nvidia.com/gpugems/gpugems3/part-v-physics-simulation/chapter-30-real-time-simulation-and-rendering-3d-fluids): background on grid-based flow and volume rendering.
