# Joinery Court

A six-member timber puzzle in a 64-block periodic world. Use gravity and a Joinery Tool to translate timbers with distinct wood tones and end-cap dots into their assembled positions.

## Start

```sh
python3 scripts/run/vanilla.py --level joinery
```

In an installed world, use `/function manifold:joinery/start`. The launcher opens `vanilla-playground/saves/Joinery Court/`. Play in first person; the session supplies a **Joinery Tool / 榫尺**.

## Controls and orientation

Hold the tool in your main hand, aim at any visible part of a timber, and right-click. The nearest beam along your sightline moves **four blocks in the current gravity direction**, if its swept volume is clear. The tool reaches 96 blocks, including repeated copies beyond the physical collision room. Stand on a surface to operate it. Ctrl turns gravity while grounded; Space jumps.

All six directions are available to every beam. A horizontal member can move sideways or vertically as well as along its length. Its orientation and shape stay fixed. A move that intersects another beam or the player's body is rejected. Moving a supporting beam downward opens space beneath the player, who then falls onto the lowered surface.

The upper-right panel shows:

- The signed logical gravity axis, such as `−Y` or `+X`.
- The focused beam's color and number, with a movement indicator or blocked cross for timber clearance.
- Progress during a translation.

The clearance indicator describes timber geometry. Player clearance is checked when the tool is used. Minecraft's F3 coordinates describe the rotated physical room; the panel describes the puzzle's logical axes.

| Member | Wood tone | Long axis |
| --- | --- | --- |
| I / 1 | Honey oak | X |
| II / 2 | Pale ash | X |
| III / 3 | Cedar | Y |
| IV / 4 | Smoked oak | Y |
| V / 5 | Walnut | Z |
| VI / 6 | Maple | Z |

The scene uses satin wood, soft cast shadows and contact shading. Fine grain and distant contrast vary smoothly with distance. The resource pack supplies warm-neutral health, food and hotbar sprites; these sprites apply wherever the pack is enabled. Vanilla health and food values remain visible. The tool uses a carpenter's-square icon, with selection feedback in the gravity HUD.

One to six dots on the end faces identify the members. Wood tone, grain and dot inlays travel with each beam. Every repeated image shares that beam's position. The end dots turn softly green at home.

## One assembly route

The initial arrangement has a thirteen-click solution. Each row uses the logical gravity direction shown in the panel.

| Order | Member | Gravity | Clicks |
| --- | --- | --- | --- |
| 1 | VI, maple | `−X` | 1 |
| 2 | V, walnut | `+X` | 1 |
| 3 | IV, smoked oak | `−Y` | 1 |
| 4 | II, pale ash | `−Y` | 1 |
| 5 | III, cedar | `−Y` | 1 |
| 6 | I, honey oak | `−X` | 8 |

Close the two side members, then lower the three raised members. The solid honey-oak member is the key: its final eight translations fill the channel through the joint. The completed assembly covers the rectangular timber envelopes exactly, with a single owner for every occupied module.

Use the open space and repeating copies to reach a standing surface for each gravity direction. Aim at any exposed face of the desired beam; the panel identifies the nearest hit. Reposition as the joint closes to keep a clear sightline and standing place.

When all six beams reach home, the localized victory title appears: **Joined as One / 六榫归一**.

## Recovery

```mcfunction
/function manifold:joinery/undo
/function manifold:joinery/checkpoint/restore
/function manifold:reset
/function manifold:stop
```

Undo restores the previous three-dimensional arrangement and player pose together. Each completed move saves a checkpoint. Reset restores the starting joint. Stop returns to the saved entry position and game mode, and removes session tools. `/function manifold:help` presents controls and recovery in English or Simplified Chinese. Fall protection remains active throughout the session.

Saves using the current layout retain their progress. Saves from earlier layouts open at the current starting arrangement.

## Verification

```sh
cabal test semantics --test-show-details=direct --test-options=joinery
python3 scripts/verify/run_tests.py --suite joinery
python3 scripts/verify/run_tests.py --suite joinery-render
```

The `joinery` suite covers periodic occupancy, six-direction movement, tool targeting, animation, the assembly route and recovery. It also verifies that saved tools receive the current appearance while retaining their item state. The route checks find supported operating stations connected to exterior air; the periodic approach check uses actual movement input.

The `joinery-render` suite checks materials, lighting, retained frames and all six gravity views. Completed-state checks in both suites compare every block in the native collision window and GPU ray distances against the complete timber envelopes.

[Back to documentation](../README.md)
