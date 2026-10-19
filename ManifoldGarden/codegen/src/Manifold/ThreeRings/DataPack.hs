module Manifold.ThreeRings.DataPack (resources) where

import Manifold.Circuits.DataPack qualified as Circuits
import Manifold.Gravity qualified as G
import Manifold.Messages qualified as M
import Manifold.Objects.DataPack qualified as Objects
import Manifold.Runtime qualified as R
import Manifold.Scene.DataPack qualified as Spatial
import Manifold.ThreeRings qualified as T

resources :: [(FilePath, String)]
resources = Objects.resources T.cubes T.cubeMaterial "three_rings" ++ Spatial.resources T.scene ++ Circuits.resources T.circuits [0 .. length T.cubes - 1] [T.socketCube s | s <- T.sockets, T.socketFinal s] ++ R.resources "three_rings" functions

functions :: R.Functions
functions =
  [ ("start", ["execute as @p at @s run function manifold:three_rings/session"]),
    ("session", ["execute if entity @s[tag=manifold.pilot] run function manifold:session/stop", R.set "h.level" 2, "execute at @s run function manifold:hybrid/start"]),
    ("validate", [R.when (R.test "r.layout" "1") "return 1", R.call "hybrid/reset", "return 0"]),
    ( "reset",
      [R.set "r.layout" 1, R.set "period" 64, R.set "g.period" (64 * G.unit)]
        ++ [R.set name value | (name, value) <- [("r.period", 64), ("r.window", 32 * G.unit), ("r.two", 2), ("r.four", 4), ("r.eight", 8), ("r.sixteen", 16), ("r.thirtytwo", 32), ("r.thousand", 1000), ("r.target", 0), ("r.erasing", 0), ("r.gate0", 0), ("r.gate1", 0), ("r.complete", 0), ("r.gravity", 0), ("o.gravity.old", 0), ("r.region0", -1), ("r.region1", -1), ("h.cache0", -1), ("h.cache1", -1), ("r.preview", 0), ("r.checkpoint", 0), ("r.checkpoint_pending", 0), ("r.stage", 0), ("c.dirty0", 1), ("c.dirty1", 1), ("c.dirty2", 1)]]
        ++ [R.set "g.x" (10 * G.unit), R.set "g.y" (G.unit `div` 2 + G.bodyHeight), R.set "g.z" (4 * G.unit), R.call "circuits/reset", R.call "objects/bank/start", R.call "objects/reset", "kill @e[tag=manifold.object.ray]", "summon minecraft:marker 0 200 0 {Tags:[\"manifold.object.ray\"]}", "data remove storage manifold:runtime checkpoint", "tp @s 10.5 201 4.5 90 25"]
        ++ M.chapter M.RingsName
    ),
    ("activate", [R.call "objects/activate", R.when (R.test "r.checkpoint" "0") (R.call "three_rings/checkpoint/save")]),
    ("native", [R.call "objects/cursor", R.call "rooms/prefetch", R.when (R.test "r.checkpoint_pending" "1" ++ " " ++ R.test "g.grounded" "1" ++ " " ++ R.test "r.held" "-1") (R.call "three_rings/checkpoint/save")]),
    ("active_tick", [R.call "rooms/tick", R.call "objects/tick"]),
    ("gravity_changed", [R.call "objects/gravity"]),
    ("can_turn", [R.when (R.test "r.held" "0..") ("return run " ++ R.call "three_rings/holding"), "return 1"]),
    ("holding", [M.actionbar "aqua" M.PutDown, "return 0"]),
    ("blocked", [M.actionbar "aqua" M.TurnSpace]),
    ("air_input", [R.set "g.armed" 0]),
    ("cleanup", ["kill @e[tag=manifold.object.active]", "kill @e[tag=manifold.object.proxy]", "kill @e[tag=manifold.object.ray]", "kill @e[tag=manifold.object.bank]", R.call "objects/reach/release"]),
    ( "circuits",
      [R.call "circuits/drain", R.when (R.test "c.goal_dirty" "1") (R.call "three_rings/goal"), R.when (R.test "c.changed" "1") (R.call "rooms/doors"), R.when (R.test "c.changed" "1") (R.call "objects/wake_direction"), R.call "three_rings/progress"]
    ),
    ( "goal",
      [ R.set "c.goal_dirty" 0,
        R.set "c.goal" 0,
        R.when (unwords [occupied socket | socket <- T.sockets, T.socketFinal socket]) (R.set "c.goal" 1),
        R.when (R.test "c.goal" "1" ++ " " ++ R.test "r.complete" "0") "execute as @a[tag=manifold.pilot] run function manifold:three_rings/complete",
        R.op "r.complete" "=" "c.goal"
      ]
    ),
    ("complete", [R.set "r.complete" 1] ++ M.victory M.RingsVictory M.RingsEnding ++ ["playsound minecraft:ui.toast.challenge_complete master @s ~ ~ ~ 0.6", R.call "three_rings/checkpoint/save"]),
    ("help", [M.chat "aqua" M.CubeControls, M.chat "aqua" M.RingsBlueHelp, M.chat "gold" M.RingsRelayHelp, M.chat "green" M.RingsGoalHelp]),
    ( "checkpoint/save",
      [R.set "r.checkpoint" 1, R.set "r.checkpoint_pending" 0, "data modify storage manifold:runtime checkpoint set value {}"]
        ++ ["data modify storage manifold:runtime checkpoint." ++ field ++ " set from storage manifold:runtime " ++ field | field <- ["cubes", "cells", "bins", "groups"]]
        ++ [R.put ("checkpoint." ++ name) name | name <- ["g.x", "g.y", "g.z", "g.frame", "r.gate0", "r.gate1", "r.gates", "r.complete", "r.held"]]
    ),
    ("checkpoint/restore", ["execute as @a[tag=manifold.pilot,limit=1] at @s run function manifold:three_rings/checkpoint/resume"]),
    ( "checkpoint/resume",
      [R.when ("unless score #h.level manifold matches 2") "return 0", "execute unless data storage manifold:runtime checkpoint run return run function manifold:hybrid/reset", "kill @e[tag=manifold.object.active]", "kill @e[tag=manifold.object.proxy]"]
        ++ ["data modify storage manifold:runtime " ++ field ++ " set from storage manifold:runtime checkpoint." ++ field | field <- ["cubes", "cells", "bins", "groups"]]
        ++ [R.get name ("checkpoint." ++ name) | name <- ["g.x", "g.y", "g.z", "g.frame", "r.gate0", "r.gate1", "r.gates", "r.complete", "r.held"]]
        ++ [R.set "h.cache0" (-1), R.set "h.cache1" (-1), R.set "g.vx" 0, R.set "g.vy" 0, R.set "g.vz" 0, R.call "gravity/bounds", "gamemode spectator @s", R.call "hybrid/land", R.call "objects/restore", R.call "gravity/publish"]
    ),
    ( "progress",
      [R.op "r.stage.old" "=" "r.stage"]
        ++ [R.when (occupied socket ++ " " ++ R.test "r.stage" (".." ++ show (stage - 1))) (R.set "r.stage" stage) | (stage, socket) <- zip [1 .. 4 :: Int] (take 4 T.sockets)]
        ++ [R.when (R.cmp "r.stage" ">" "r.stage.old") (R.set "r.checkpoint_pending" 1)]
    )
  ]
    ++ [("mark/" ++ show ident, [R.call ("circuits/mark/" ++ show ident)]) | ident <- [0 .. length T.cubes - 1]]
  where
    occupied socket = let (x, y, z) = T.socketCell socket; ident = show (T.socketCube socket) in "if data storage manifold:runtime cubes[{id:" ++ ident ++ ",x:" ++ show x ++ ",y:" ++ show y ++ ",z:" ++ show z ++ "}] unless data storage manifold:runtime cubes[{id:" ++ ident ++ ",phase:1}]"
