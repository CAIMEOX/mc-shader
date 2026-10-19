# Atrium

An infinite lattice for exploring native movement and six-axis gravity.

## Start

```sh
python3 scripts/run/vanilla.py --level atrium
```

In an installed world:

```mcfunction
/function manifold:start
```

The launcher uses `vanilla-playground/saves/Manifold/`.

## Explore

Walk along the repeating beams with WASD and jump with Space. While grounded, look toward a wall, the ceiling, or another axial direction and press Ctrl to turn gravity. The camera turns with you; landing restores native movement on the new surface.

The lattice repeats every 32 blocks along all three axes. Crossing a period keeps your movement continuous. Atrium is an open exploration scene; [Three Rings](three-rings.md) provides the cube puzzle.

`/function manifold:help` displays controls, `/function manifold:reset` returns to the entrance, and `/function manifold:stop` returns to the saved entry position and game mode.

For free-flight exploration, use `/function manifold:flight`. Its controls are available through the same help command.

Verify native jumping, depth alignment, periodic movement, and the gravity handoff with:

```sh
python3 scripts/verify/run_tests.py --suite hybrid
```

[Back to documentation](../README.md)
