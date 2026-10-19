# Three Rings

A placement puzzle in a 64-block periodic world. Three directional cubes serve as temporary floors, alternate power supplies, and final keys for the central garden.

## Start

```sh
python3 scripts/run/vanilla.py --level three-rings
```

In an installed world:

```mcfunction
/function manifold:three_rings/start
```

The launcher uses `vanilla-playground/saves/Three Rings/`. Use first-person view. Default controls are right-click to take/place, Ctrl to turn gravity while grounded, and Space to jump.

## Rules

- A cube can be picked up when its gravity direction matches yours.
- Carry one cube at a time, and place it before changing gravity.
- Aligned cubes move along their bound direction until supported. Other cubes freeze and can support the player.
- Repeated images belong to the same logical cube and level state.
- A cube waits if its next cell would intersect the player.

Cube arrows keep their world direction when the camera turns. Blue is bound to logical `+Y`, amber to `−X`, and green to `+Z`. Those are level coordinates; the physical cache axes shown by F3 change with orientation.

## Solution

1. **Collect blue from the entrance's back face.** Look straight up from the entrance and press Ctrl. Fall through the vertical repetition and land behind the platform, then take the blue cube.
2. **Power the gallery.** Follow the blue line along that surface and place blue in the temporary socket beside the gallery.
3. **Borrow blue's side.** Turn around toward the way you came and change gravity. Fall horizontally through the periodic boundary and land on blue's frozen side. Walk onto the adjoining gallery wall and collect amber.
4. **Deliver amber through the shaft.** Follow the orange line to the outer delivery ledge. Place amber beside the crossbeam at the shaft opening so it can fall into the shaft. It crosses the periodic boundary and reaches the distant temporary socket, opening the green court.
5. **Collect green.** Follow the shaft to its receiving platform, enter the opened court, and turn gravity in the green cube's arrow direction. Land and take green.
6. **Transfer the gallery supply to green.** Travel along the green wall, going over the intervening wall's top before returning to the green line. Put green in the temporary relay socket beside the gallery.
7. **Move blue to its main socket.** Return to blue's gravity direction and retrieve it from the temporary socket. Green now maintains the gallery supply. Carry blue through the open passage to the blue chamber near the central tower and place it in the main socket.
8. **Move green to its main socket.** Blue's main socket maintains the gallery supply. Return to green's gravity, retrieve green from the relay, and carry it through the central passage to its main socket.
9. **Move amber to its main socket.** Return to amber's gravity and the shaft's receiving platform. Retrieve amber, travel toward the central support, and place it in the amber main socket.

The three occupied main sockets complete the puzzle. The central architecture lights up and the English victory title reads **Rings United**.

## Recovery

The level saves checkpoints at power-supply milestones. This command restores the player, cubes, and circuits together:

```mcfunction
/function manifold:three_rings/checkpoint/restore
```

Death also restores the checkpoint. `/function manifold:reset` starts the puzzle from the entrance. `/function manifold:help` displays the level's controls and route hints on request.

If amber stays on the delivery ledge, place it beyond the supported edge and into the shaft opening. If a cube cannot be picked up, land first, match its arrow direction, and approach with a clear line of sight.

## Authoring coordinates

These are logical block centres, not F3 coordinates.

| Cube | Initial cell | Temporary socket | Main socket |
| --- | --- | --- | --- |
| Blue | `(8, 63, 4)` | `(26, 63, 4)` | `(38, 63, 12)` |
| Amber | `(27, 3, 4)` | `(52, 3, 18)` | `(38, 3, 9)` |
| Green | `(53, 3, 28)` | `(24, 3, 28)` | `(38, 3, 28)` |

The amber delivery cell is `(6, 3, 18)`. Its `−X` fall crosses the seam and stops at the receiving socket. Blue's temporary socket, green's relay socket, and blue's main socket are alternate gallery supplies. Amber's temporary and main sockets supply the green court.

The level definitions are in `codegen/src/Manifold/ThreeRings.hs`; its runtime adapter is in `ThreeRings/DataPack.hs`. Verify the complete keyboard-and-mouse route with:

```sh
python3 scripts/verify/run_tests.py --suite rings
```

[Back to documentation](../README.md)
