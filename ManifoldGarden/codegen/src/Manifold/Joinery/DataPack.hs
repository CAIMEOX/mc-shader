module Manifold.Joinery.DataPack (resources) where

import Manifold.Gravity qualified as G
import Manifold.Joinery qualified as J
import Manifold.Joinery.Spatial (axes, call, pose)
import Manifold.Joinery.Spatial qualified as Spatial
import Manifold.Json
import Manifold.Messages qualified as M
import Manifold.Runtime qualified as R

resources :: [(FilePath, String)]
resources = R.resources "joinery" (functions ++ Spatial.functions) ++ [("data/manifold/item_modifier/joinery_tool.json", render $ object [("type", string "minecraft:set_components"), ("components", object [("minecraft:item_model", string "manifold:joinery_tool")])])]

tool :: String
tool = "minecraft:carrot_on_a_stick[minecraft:custom_data={manifold_joinery_tool:1b},minecraft:item_name={translate:\"manifold.joinery.tool\"},minecraft:item_model=\"manifold:joinery_tool\",minecraft:unbreakable={}]"

toolMatch :: String
toolMatch = "minecraft:carrot_on_a_stick[minecraft:custom_data~{manifold_joinery_tool:1b}]"

functions :: R.Functions
functions =
  [ ("load", ["scoreboard objectives add manifold.joinery.use minecraft.used:minecraft.carrot_on_a_stick", R.set "j.held" 0]),
    ("start", ["execute as @p at @s run " ++ call "session"]),
    ("session", ["execute if entity @s[tag=manifold.pilot] run function manifold:session/stop", R.set "h.level" 1, R.call "hybrid/start"]),
    ("validate", [R.when (R.test "j.layout" "3") "return 1", R.call "hybrid/reset", "return 0"]),
    ( "reset",
      [R.call "objects/reach/release", R.set "j.layout" 3, R.set "period" 64, R.set "g.period" (64 * G.unit)]
        ++ [R.set n v | (n, v) <- [("r.period", 64), ("r.window", 32 * G.unit), ("r.two", 2), ("r.four", 4), ("r.eight", 8), ("r.sixteen", 16), ("r.thirtytwo", 32), ("r.thousand", 1000), ("r.region0", -1), ("r.region1", -1), ("r.complete", 0), ("h.cache0", -1), ("h.cache1", -1), ("j.moving", -1), ("j.direction", 0), ("j.time", 0), ("j.steps", 0), ("j.held", 0), ("j.module", 4 * G.unit), ("j.eye", 2949), ("j.low", -6), ("j.high", 37)]]
        ++ [R.set (pose i a) v | (i, offset) <- zip [0 ..] J.initial, (a, v) <- zip axes (G.components offset)]
        ++ [R.set "g.x" (48 * G.unit), R.set "g.y" (44 * G.unit + G.unit `div` 2 + G.bodyHeight - G.unit), R.set "g.z" (35 * G.unit), "tp @s 48.5 240 35.5 100 15", R.call "objects/bank/start", "data modify storage manifold:joinery history set value []", call "encode", call "checkpoint/save", call "tool", "scoreboard players set @s manifold.joinery.use 0"]
        ++ M.chapter M.JoineryName
    ),
    ("tool", ["execute unless data entity @s Inventory[{components:{\"minecraft:custom_data\":{manifold_joinery_tool:1b}}}] run give @s " ++ tool]),
    ("tool/equip", ["execute if items entity @s weapon.mainhand " ++ toolMatch ++ " run item modify entity @s weapon.mainhand manifold:joinery_tool"]),
    ("activate", [call "tool", call "tool/equip"]),
    ("native", [R.call "rooms/prefetch"]),
    ("active_tick", [R.call "rooms/tick", R.when (R.test "j.moving" "0..") (call "motion/tick"), R.op "j.held.old" "=" "j.held", "execute store success score #j.held manifold if items entity @s weapon.mainhand " ++ toolMatch, R.when ("unless score #j.held manifold = #j.held.old manifold") (call "encode_motion"), R.when (R.test "j.held" "1" ++ " " ++ R.test "j.held.old" "0") (call "tool/equip"), "execute if score @s manifold.joinery.use matches 1.. run " ++ call "input"]),
    ("input", ["scoreboard players set @s manifold.joinery.use 0", R.when (R.test "j.held" "1") (call "use")]),
    ("use", [R.when ("unless score #h.mode manifold matches 1") "return 0", R.when (R.test "h.busy" "1") "return 0", R.call "hybrid/sync", R.when (R.test "g.grounded" "0") "return 0", call "ray/start"] ++ [R.when (R.test "j.hit" (show i)) ("return run " ++ call ("select/" ++ show i)) | i <- [0 .. 5 :: Int]]),
    ("gravity_changed", ["return 0"]),
    ("can_turn", [R.when (R.test "h.busy" "1") "return 0", "return 1"]),
    ("blocked", [M.actionbar "aqua" M.TurnSpace]),
    ("air_input", [R.set "g.armed" 0]),
    ("cleanup", ["kill @e[tag=manifold.object.bank]", "clear @s " ++ toolMatch, R.set "h.busy" 0, R.set "j.moving" (-1)]),
    ("help", [M.chat "aqua" M.JoineryControls, M.chat "white" M.JoineryRoute, M.chat "gray" M.JoineryRecovery]),
    ("blocked/timber", [M.actionbar "gold" M.JoineryBlocked, "playsound minecraft:block.wood.hit master @s ~ ~ ~ 0.3 0.6"]),
    ("blocked/player", [M.actionbar "aqua" M.JoineryStand]),
    ( "encode",
      [R.set "j.configuration" 0]
        ++ concat [[R.op ("j.s" ++ show i ++ a) "=" (pose i a), R.op ("j.s" ++ show i ++ a) "*=" "j.module", R.op "j.configuration" "+=" (pose i a)] | i <- [0 .. 5 :: Int], a <- axes]
        ++ concat [[R.set "j.word" 0] ++ concat [[R.op "j.part" "=" (pose i a), R.op "j.part" "*=" ("pow" ++ show (12 * (i `mod` 2) + 4 * axis)), R.op "j.word" "+=" "j.part"] | i <- [2 * word, 2 * word + 1], (axis, a) <- zip [0 :: Int ..] axes] ++ ["execute store result storage manifold:object_bank colors[" ++ show word ++ "] int 1 run scoreboard players get #j.word manifold"] | word <- [0 .. 2 :: Int]]
        ++ [call "encode_motion"]
    ),
    ("encode_motion", [R.op "j.part" "=" "j.held", R.op "j.part" "*=" "pow4", R.op "j.part" "+=" "j.time", R.op "j.part" "*=" "pow3", R.op "j.part" "+=" "j.direction", R.op "j.part" "*=" "pow3", R.op "j.part" "+=" "j.moving", R.add "j.part" 1, "execute store result storage manifold:object_bank colors[3] int 1 run scoreboard players get #j.part manifold", R.set "r.bank_dirty" 1]),
    ("motion/tick", [R.add "j.time" 1, call "encode_motion", R.call "gravity/publish", R.when (R.test "j.time" "12..") (call "motion/finish")]),
    ("motion/finish", [R.when (R.test "j.moving" (show i) ++ " " ++ R.test "j.direction" (show d)) (call ("commit/" ++ show i ++ "/" ++ show d)) | i <- [0 .. 5 :: Int], d <- [0 .. 5 :: Int]] ++ [R.set "j.moving" (-1), R.set "j.time" 0, R.set "h.busy" 0, R.add "j.steps" 1, call "encode", call "goal", call "checkpoint/save", R.set "r.region0" (-1), R.set "r.region1" (-1), R.call "hybrid/land", R.call "gravity/publish", "playsound minecraft:block.wood.place master @s ~ ~ ~ 0.35 0.8"]),
    ("goal", [R.when (R.test "j.configuration" "0" ++ " " ++ R.test "r.complete" "0") (call "complete"), R.when ("unless score #j.configuration manifold matches 0") (R.set "r.complete" 0)]),
    ("complete", [R.set "r.complete" 1] ++ M.victory M.JoineryVictory M.JoineryEnding ++ ["playsound minecraft:ui.toast.challenge_complete master @s ~ ~ ~ 0.6"]),
    ("snapshot", ["data modify storage manifold:joinery snapshot set value {}"] ++ ["execute store result storage manifold:joinery snapshot.\"" ++ field ++ "\" int 1 run scoreboard players get #" ++ field ++ " manifold" | field <- savedFields]),
    ("checkpoint/save", [call "snapshot", "data modify storage manifold:joinery checkpoint set from storage manifold:joinery snapshot"]),
    ("checkpoint/restore", ["execute as @a[tag=manifold.pilot,limit=1] at @s run " ++ call "checkpoint/resume"]),
    ("checkpoint/resume", [R.when ("unless score #h.level manifold matches 1") "return 0", R.when ("unless score #j.layout manifold matches 3") ("return run " ++ R.call "hybrid/reset"), "execute unless data storage manifold:joinery checkpoint run return run function manifold:hybrid/reset", "data modify storage manifold:joinery snapshot set from storage manifold:joinery checkpoint", call "restore"]),
    ("undo", ["execute as @a[tag=manifold.pilot,limit=1] at @s run " ++ call "undo/apply"]),
    ("undo/apply", [R.when ("unless score #h.level manifold matches 1") "return 0", R.when (R.test "h.busy" "1") "return 0", "execute unless data storage manifold:joinery history[0] run return 0", "data modify storage manifold:joinery snapshot set from storage manifold:joinery history[-1]", "data remove storage manifold:joinery history[-1]", call "restore", call "checkpoint/save"]),
    ("restore", ["execute store result score #" ++ field ++ " manifold run data get storage manifold:joinery snapshot.\"" ++ field ++ "\"" | field <- savedFields] ++ [R.set "j.moving" (-1), R.set "j.time" 0, R.set "h.busy" 0, R.set "g.vx" 0, R.set "g.vy" 0, R.set "g.vz" 0, R.set "r.region0" (-1), R.set "r.region1" (-1), R.call "gravity/bounds", call "encode", "gamemode spectator @s", R.call "hybrid/land", R.call "gravity/publish"])
  ]
    ++ [("select/" ++ show i, [R.when (R.test ("g.d" ++ a) (show sign)) ("return run " ++ call ("move/" ++ show i ++ "/" ++ show d)) | (d, direction) <- zip [0 :: Int ..] G.downDirections, (a, sign) <- zip axes (G.components direction), sign /= 0]) | i <- [0 .. 5 :: Int]]
    ++ [ ( "move/" ++ show i ++ "/" ++ show d,
           [R.when (R.test "h.busy" "1") "return 0"]
             ++ concat [[R.op ("j.target" ++ a) "=" (pose i a), R.add ("j.target" ++ a) delta] | (a, delta) <- zip axes (G.components direction)]
             ++ [R.set "j.blocker" (-1), call ("obstruction/" ++ show i), R.when (R.test "j.blocker" "0..") ("return run " ++ call "blocked/timber"), call ("player/" ++ show i ++ "/" ++ show d), R.when (R.test "g.blocked" "1") ("return run " ++ call "blocked/player"), call "snapshot", "data modify storage manifold:joinery history append from storage manifold:joinery snapshot", R.set "j.moving" i, R.set "j.direction" d, R.set "j.time" 0, R.set "h.busy" 1, R.set "h.mode" 3, "gamemode spectator @s", call "encode_motion", R.call "gravity/publish", "playsound minecraft:block.wood.hit master @s ~ ~ ~ 0.25 1.1"]
         )
       | i <- [0 .. 5 :: Int],
         (d, direction) <- zip [0 :: Int ..] G.downDirections
       ]
    ++ [("commit/" ++ show i ++ "/" ++ show d, concat [[R.add (pose i a) delta, R.op (pose i a) "%=" "r.sixteen"] | (a, delta) <- zip axes (G.components direction), delta /= 0]) | i <- [0 .. 5 :: Int], (d, direction) <- zip [0 :: Int ..] G.downDirections]
    ++ [("obstruction/" ++ show i, concat [concat [[R.op ("j.relative" ++ a) "=" ("j.target" ++ a), R.op ("j.relative" ++ a) "-=" (pose other a), R.op ("j.relative" ++ a) "%=" "r.sixteen"] | a <- axes] ++ ["execute if function manifold:joinery/overlap/" ++ show i ++ "/" ++ show other ++ " run return 1"] | other <- [0 .. 5], other /= i] ++ ["return 0"]) | i <- [0 .. 5 :: Int]]
    ++ [("overlap/" ++ show i ++ "/" ++ show other, [R.when (unwords [R.test ("j.relative" ++ a) (show low ++ ".." ++ show high) | (a, low, high) <- zip3 axes (G.components lo) (G.components hi)]) ("return run " ++ call ("blocked_by/" ++ show other)) | (lo, hi) <- J.mergeCells 0 (J.obstructingOffsets rod second)] ++ ["return 0"]) | rod <- J.rods, second <- J.rods, let i = J.rodId rod, let other = J.rodId second, i /= other]
    ++ [("blocked_by/" ++ show i, [R.set "j.blocker" i, "return 1"]) | i <- [0 .. 5 :: Int]]
  where
    savedFields = [pose i a | i <- [0 .. 5], a <- axes] ++ ["g.x", "g.y", "g.z", "g.frame", "r.complete", "j.steps"]
