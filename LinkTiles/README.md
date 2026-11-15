# LinkTiles

A 10x10 linking puzzle written in [Oria](https://github.com/CAIMEOX/OpenOria).
Aim at tiles on a physical Minecraft table and right-click matching pairs. Clear all
100 tiles using axis-aligned paths with at most two bends. The path may run around
the outside of the board. Tiles stay in place when their neighbors disappear.

The target is Minecraft Java 26.3 / datapack format 121. The board uses vanilla
`text_display`, `block_display`, and `interaction` entities; a resource pack is optional.
Twenty-five numbered, colored tile kinds have four copies each.

## Build and play

For a local development client, run:

```bash
./scripts/play
```

This uses Fabric Loom to open a dedicated Minecraft 26.3 client and create or reopen
the `LinkTiles` flat world under `.lake/play`. It installs the current compiled pack,
prepares a small quartz platform, positions the player above the board, and starts the
first deal automatically. Later launches preserve the game. Keyboard and mouse input
use the normal client. The helper mod belongs to the development client; the exported
datapack runs in vanilla Minecraft.

The launcher reuses Gradle's runtime cache, following `datapack-playground`. Add `--online`
on a machine that needs to download dependencies. Set `LINK_TILES_JAVA_HOME` to a JDK 25
installation when needed. `--prepare-only` builds and installs without opening a window;
`--smoke` opens the client, verifies the board, saves a screenshot, and exits. The launcher
log is `.lake/play/launcher.log`. Repeated launches reuse the pack export when Lake's
executable build trace is unchanged.
The visible-client check also verifies UUID ownership and native hitbox alignment.
Its status is recorded in `.lake/play/play-status.json`, and its screenshot is
`.lake/play/screenshots/link-tiles.png`.

### Export a vanilla datapack

This standalone Lake project uses the sibling `../oria` checkout. Its pinned Lean
toolchain and Minecraft server are recorded in `lean-toolchain` and
`minecraft-26.3.lock.json`.

```bash
lake update
lake build
lake exe link-tiles output/link-tiles
```

The output directory must be absent or empty. Copy it into the world's `datapacks`
directory, then reload. In the Overworld, stand on full blocks in an open, level area:

```mcfunction
trigger link.action set 1
```

After the first server tick this command is available without operator permission.
The table appears underneath and around you. Look down and right-click a tile to
select it; right-click the same tile to cancel. A rejected second tile becomes the
new selection. A matching, connectable pair disappears and its gold connection line
remains briefly visible. Number labels and blank spaces retain a fixed cell advance.

The chat toolbar offers New, Hint, Reshuffle, Replay, and Release. The corresponding
trigger values are:

| Value | Action |
| --- | --- |
| 1 | New random deal |
| 2 | Highlight one legal pair and its actual connection |
| 3 | Re-deal the remaining tiles, preserving empty cells and the tile multiset |
| 4 | Restart the exact initial seed |
| 5 | Remove the table and release ownership |

Operators can also call `link_tiles:new`, `link_tiles:hint`, `link_tiles:reshuffle`,
`link_tiles:replay`, and `link_tiles:release` as a player.

There is one table per installed pack. Its owner is identified by UUID. Spectators
may watch, but their clicks and actions cannot change the game. The table stays at
its original anchor until released. Starting another deal or releasing it requires
returning to the table. Construction and connection animations pause while the owner
is offline or away. The pack does not modify chunk-force-loading tickets, player
attributes, or command-budget gamerules.

## Generation and rules

Generation works from the geometry first. It repeatedly removes the top tile of a
random nonempty column and the top tile of another nonempty column. These endpoints
connect through the empty top border. When just one column remains, its first two
tiles connect vertically. This produces a complete removal order. Shuffled pairs of
labels are then assigned to that order, so the generated position has a constructive
clear certificate without a whole-board search.

A new deal places two pairs of every kind. Reshuffling counts the remaining labels,
forms the corresponding pair pool, and runs the same construction on the remaining
occupied cells. It preserves all holes and multiplicities. The native random sequence
is reset with world-seed and sequence-name mixing disabled, making replay deterministic.

Players can choose other legal moves. A position with no legal move and remaining
tiles enters the stuck phase and offers reshuffling. A hint establishes one legal
next move, rather than promising a particular eventual outcome.

## Incremental index

The 10 by 10 interior is embedded in a 12 by 12 grid with an empty outer ring. Tile
labels are authoritative; nearest-obstacle rays and empty-segment histograms are
derived data. An empty cell belongs to one maximal horizontal and one maximal vertical
segment. A horizontal segment counts its left/right endpoint tiles and the nearest
up/down tiles at each column. The vertical definition is symmetric. These ports refer
to distinct tile positions: seeing the same endpoint through several empty cells
does not count it repeatedly.

Each segment has 26 directly indexed counters, an active flag, and a count of labels
appearing at least twice. Global counters track good segments and adjacent equal
pairs. Their disjunction answers move existence without scanning the board.

Deletion merges the two newly joined runs, rebuilds their ports, and replaces the one
changed visibility port on each crossed perpendicular segment. Obstacle rays at the
surviving occupied endpoints are updated too. Both deletions complete before the game
publishes a new phase. Retired segment records are excluded from hint searches.

For a generalized H by W board with K labels, the bookkeeping is O(H + W + K) per
deletion, O(1) for move existence, and O(HWK) storage. Here K is fixed at 25. These are
indexed-operation bounds; native NBT access, serialization, and macro expansion have
additional costs. Command-quota acceptance measures the generated implementation.

Explicit pair routing checks straight and one-bend paths first, followed by the 12
possible middle rows and 12 possible middle columns. It retains the actual endpoints
and bends. The renderer consumes this same route, drawing up to three reusable gold
bars, including the outer ring. Hint search recovers endpoints from a duplicate
histogram or from the adjacent-pair fallback.

## Input and rendering

Each cell has a thin native interaction box with a row tag and a column tag. One
advancement has twenty criteria and requires one row AND one column. A completed
advancement stops listening until consumed. Its two criteria therefore belong to the
same accepted native interaction, even if further packets arrive before the next tick.
Consumption reads both coordinates and revokes progress before executing game logic.
It does not invoke a reward function inside an Oria invocation.

Ten text displays render the rows. Successful turns refresh only affected rows;
explicit construction renders the whole board once. Three block displays visualize
connection segments. Their translations and scales use native numeric NBT stores.
Rendering observes the board; entity contents are not the save file.

## Source layout

| Module | Responsibility |
| --- | --- |
| `LinkTiles.State` | Typed native save document and fixed geometry |
| `LinkTiles.Geometry` | Exact pair routing and concrete bends |
| `LinkTiles.Index` | Rebuild slices, incremental deletion, and hint witnesses |
| `LinkTiles.Deal` | Seeded, certifiably clearable deals and reshuffling |
| `LinkTiles.Model` | Selection, cancellation, removal, and terminal states |
| `LinkTiles.Input` | Native event JSON and typed receipt decoding |
| `LinkTiles.View` | Native table entities, row text, controls, and connection bars |
| `LinkTiles.Game` | UUID ownership, actions, and bounded tick scheduling |
| `LinkTiles.Export` | The standard Oria compiler plus JSON resource export |

Builds use `Datapack.compile` from a native Lean executable. Every object definition
still uses `@[mcfunction]` and the ordinary Tree → Cont → Machine → DP121 pipeline.
The build adds one interaction advancement through Lean's JSON representation.

The save is `link_tiles:board game`; presentation templates are under `link_tiles:ui`.
Native global documents survive ordinary calls and matching-schema reloads. Temporary
invocation arenas and call frames are released after each turn. The game's native
documents do not use persistent object pointers or require the object-heap collector.

## Acceptance

```bash
./scripts/quality
./scripts/gametest
./scripts/gametest --stack
```

Native acceptance needs JDK 25 and the server bundle pinned in the lock file. Set
`LINK_TILES_JAVA` and `LINK_TILES_SERVER_JAR` when they are not at the default locations.
Each run retains its final pack, isolated world, log, and XML report under
`.lake/gametest.*`.

The native suite sends actual interaction packets through server player connections,
checks spectator isolation and first-click coordinate consistency, and clears all 50
certificate pairs. After every deletion it reconstructs obstacle rays, empty segments,
distinct endpoint histograms, adjacency, and move existence independently. Direction/
turn search checks emitted routes, including outside-border paths and rejected
three-bend-only connections. Replay and reshuffling check seed identity, hole
preservation, multiplicities, and constructive solvability. Native text and display
transforms are checked against the saved tiles and routes.
Ownership checks also cover distant actions, paused construction, and preserving the
complete game document across matching-schema load initialization.

The same suite runs with the default register budget and with six registers, exercising
stack spills. It reports native command quota for incremental deletion, rebuilding on
the same resulting board, the most expensive observed construction/click tick, and an
idle tick. Rebuilding is split across 24 slices; its reported total spans those slices.
Quota consumption is not elapsed time.

Real-client font alignment, readability, and aiming comfort still require visual QA
with the player's resource packs, screen resolution, and field of view.
