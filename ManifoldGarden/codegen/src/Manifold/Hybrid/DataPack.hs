module Manifold.Hybrid.DataPack (resources, cacheVersion) where

import Manifold.Gravity qualified as G
import Manifold.Json
import Manifold.Level.DataPack qualified as Level
import Manifold.Messages qualified as M
import Manifold.Protocol
import Manifold.Stage qualified as S

cacheVersion :: Int
cacheVersion = 4

resources :: [(FilePath, String)]
resources =
  [("data/manifold/function/hybrid/" ++ name ++ ".mcfunction", unlines body) | (name, body) <- functions]
    ++ [ ( "data/manifold/dimension/stage.json",
           render $
             object
               [ ("type", string "minecraft:overworld"),
                 ( "generator",
                   object
                     [ ("type", string "minecraft:flat"),
                       ( "settings",
                         object
                           [ ("biome", string "minecraft:the_void"),
                             ("features", bool False),
                             ("lakes", bool False),
                             ("layers", array [object [("block", string "minecraft:air"), ("height", int (1 :: Int))]]),
                             ("structure_overrides", array [])
                           ]
                       )
                     ]
                 )
               ]
         )
       ]

set :: String -> Int -> String
set n = setScore n . fromIntegral

op :: String -> String -> String -> String
op = operation

test :: String -> String -> String
test n range = "if score " ++ score n ++ " matches " ++ range

cmp :: String -> String -> String -> String
cmp a relation b = "if score " ++ score a ++ " " ++ relation ++ " " ++ score b

when :: String -> String -> String
when condition action = "execute " ++ condition ++ " run " ++ action

call :: String -> String
call name = "function manifold:hybrid/" ++ name

xyz :: [String]
xyz = ["x", "y", "z"]

functions :: [(String, [String])]
functions =
  [ ( "start",
      [ set "h.available" 0,
        "execute in manifold:stage run scoreboard players set #h.available manifold 1",
        when (test "h.available" "0") (M.chat "yellow" M.StageUnavailable),
        when (test "h.available" "0") "return 0",
        when "if entity @a[tag=manifold.pilot]" "return 0",
        "tag @s add manifold.pilot",
        "function manifold:session/protect",
        "data modify storage manifold:session position set from entity @s Pos",
        "data modify storage manifold:session rotation set from entity @s Rotation",
        "data modify storage manifold:session dimension set from entity @s Dimension"
      ]
        ++ [when ("if entity @s[gamemode=" ++ mode ++ "]") (set "g.savedmode" i) | (i, mode) <- zip [0 ..] ["survival", "creative", "adventure", "spectator"]]
        ++ [ set "g.loaded" 1,
             set "enabled" 1,
             set "quality" 1,
             "gamemode spectator @s",
             "execute in manifold:stage run tp @s 8.5 202.0 0.5 0 20",
             "execute in manifold:stage run function manifold:hybrid/setup"
           ]
    ),
    ( "respawn",
      [ "tag @s remove manifold.respawn_pending",
        "gamemode spectator @s",
        "execute in manifold:stage run tp @s 8.5 202.0 0.5 0 20",
        when (test "h.level" "1") "execute in manifold:stage positioned 8.5 202.0 0.5 run return run function manifold:joinery/checkpoint/resume",
        when (test "h.level" "2") "execute in manifold:stage positioned 8.5 202.0 0.5 run return run function manifold:three_rings/checkpoint/resume",
        "execute in manifold:stage positioned 8.5 202.0 0.5 run function manifold:hybrid/reset"
      ]
    ),
    ( "setup",
      [ "forceload add -34 -34 114 34",
        "kill @e[tag=manifold.direction]",
        "summon minecraft:marker 0.0 200.0 0.0 {Tags:[\"manifold.direction\"]}",
        "execute positioned 0.5 204.0 0.5 run function manifold:carrier/start",
        call "reset"
      ]
    ),
    ( "reset",
      [ "gamemode spectator @s",
        "function manifold:gravity/reset",
        set "h.mode" 3,
        set "h.busy" 0,
        set "h.cache.version" cacheVersion,
        set "h.preparing" 1,
        set "h.slot" 0,
        set "h.sprint.old" 0,
        set "g.fly" 0,
        Level.invoke Level.Reset,
        "function manifold:gravity/publish"
      ]
    ),
    ( "stop",
      [ "execute in manifold:stage run forceload remove -34 -34 114 34",
        "execute in manifold:stage run " ++ Level.invoke Level.Cleanup,
        "execute in manifold:stage run function manifold:gravity/stop",
        set "h.mode" 0,
        set "h.busy" 0,
        set "h.level" 0
      ]
    ),
    ( "tick",
      [ when "unless dimension manifold:stage" (call "stop"),
        Level.invoke Level.ActiveTick,
        when (test "h.busy" "1") "return 0",
        when (test "h.mode" "1") ("return run " ++ call "native"),
        when (test "h.mode" "2") ("return run " ++ call "air"),
        when (test "h.mode" "3") ("return run " ++ call "waiting")
      ]
    ),
    ( "waiting",
      [ when (test "h.preparing" "1") (call "prepare"),
        when (test "h.preparing" "0" ++ " " ++ test "h.wait" "1..") "scoreboard players remove #h.wait manifold 1",
        when (test "h.preparing" "0" ++ " " ++ test "h.wait" "0") (call "resume"),
        "function manifold:gravity/publish"
      ]
    ),
    ( "prepare",
      [set "h.loaded" 1]
        ++ [when ("unless loaded " ++ show x ++ " 200 " ++ show z) (set "h.loaded" 0) | x <- [-48, -32 .. 112 :: Int], z <- [-48, -32 .. 32 :: Int]]
        ++ [ when (test "h.loaded" "0") "return 0",
             Level.invoke (Level.Build 0 0),
             Level.invoke (Level.Build 1 0),
             set "h.cache0" 0,
             set "h.cache1" 0,
             set "h.cache.version" cacheVersion,
             set "h.preparing" 0,
             set "h.wait" 12,
             call "place"
           ]
    ),
    ( "resume",
      [ when ("unless score " ++ score "h.cache.version" ++ " matches " ++ show cacheVersion) ("return run " ++ call "land"),
        call "place",
        "gamemode adventure @s",
        set "h.mode" 1,
        set "g.fly" 0,
        set "g.grounded" 1,
        set "g.vx" 0,
        set "g.vy" 0,
        set "g.vz" 0,
        call "sync",
        Level.invoke Level.Activate
      ]
    ),
    ( "native",
      [ when "unless entity @s[gamemode=adventure] unless entity @s[gamemode=survival]" (call "stop"),
        when (test "h.mode" "0") "return 0"
      ]
        ++ [op ("h.old" ++ a) "=" ("g." ++ a) | a <- xyz]
        ++ [call "sync", when ("unless score #h.mode manifold matches 1") "return run function manifold:gravity/publish"]
        ++ concat
          [ [ op ("g.v" ++ a) "=" ("g." ++ a),
              op ("g.v" ++ a) "-=" ("h.old" ++ a),
              when (test ("g.v" ++ a) "65537..") (op ("g.v" ++ a) "-=" "g.period"),
              when (test ("g.v" ++ a) "..-65537") (op ("g.v" ++ a) "+=" "g.period")
            ]
          | a <- xyz
          ]
        ++ [ "execute at @s run " ++ Level.invoke Level.Native,
             set "h.sprint" 0,
             when "if predicate manifold:gravity/sprint" (set "h.sprint" 1),
             when (test "g.cooldown" "1..") "scoreboard players remove #g.cooldown manifold 1",
             when (test "h.sprint" "1" ++ " " ++ test "h.sprint.old" "0") (call "turn/aim"),
             op "h.sprint.old" "=" "h.sprint",
             "function manifold:gravity/publish"
           ]
    ),
    ( "sync",
      [when (test "h.level" "1..") "return run function manifold:rooms/sync", "execute store result score #g.grounded manifold run data get entity @s OnGround"]
        ++ concat [["execute store result score " ++ score ("h.p" ++ a) ++ " run data get entity @s Pos[" ++ show i ++ "] " ++ show G.unit] | (i, a) <- zip [0 :: Int ..] xyz]
        ++ [when (test "h.slot" (show slot)) (call ("origin/" ++ show slot)) | slot <- [0, 1 :: Int]]
        ++ ["scoreboard players add #h.py manifold " ++ show G.bodyHeight]
        ++ [when (test "g.frame" (show i)) (call ("read/" ++ show i)) | i <- [0 .. 23 :: Int]]
        ++ [when (test "g.frame" (show i)) (call ("wrap/" ++ show i)) | i <- [0 .. 23 :: Int]]
        ++ [op ("g." ++ a) "%=" "g.period" | a <- xyz]
    ),
    ("turn/aim", turnGuard ++ [op "h.before" "=" "g.frame", "function manifold:gravity/aim", call "begin"]),
    ( "begin",
      [ when (test "g.blocked" "1") (Level.invoke Level.Blocked),
        when (cmp "g.frame" "=" "h.before") "return 0",
        Level.invoke Level.GravityChanged,
        set "h.mode" 2,
        "gamemode spectator @s",
        set "g.sprint.old" 1,
        "function manifold:gravity/publish"
      ]
    ),
    ( "air",
      [ when (test "g.cooldown" "1..") "scoreboard players remove #g.cooldown manifold 1",
        "function manifold:gravity/input"
      ]
        ++ [when (test "g.cooldown" "1..") (set ("g.a" ++ a) 0) | a <- xyz]
        ++ [ "function manifold:gravity/integrate",
             "function manifold:gravity/move",
             when (test "g.grounded" "1" ++ " " ++ test "g.fly" "0" ++ " " ++ test "g.cooldown" "0") (call "land")
           ]
        ++ [when (test "h.mode" "2" ++ " " ++ test "h.slot" (show slot)) ("execute positioned " ++ show (80 * slot) ++ ".5 202.0 0.5 unless entity @s[distance=..40] run tp @s " ++ show (80 * slot) ++ ".5 202.0 0.5 ~ ~") | slot <- [0, 1 :: Int]]
        ++ ["function manifold:gravity/publish"]
    ),
    ( "land",
      [set "h.next" 1, op "h.next" "-=" "h.slot"]
        ++ [ when (test "h.next" (show slot) ++ " " ++ test "g.frame" (show frame)) (Level.invoke (Level.Build slot frame))
           | slot <- [0, 1 :: Int],
             frame <- [0 .. 23 :: Int]
           ]
        ++ [when (test "h.next" (show slot)) (op ("h.cache" ++ show slot) "=" "g.frame") | slot <- [0, 1 :: Int]]
        ++ [op "h.slot" "=" "h.next", set "h.cache.version" cacheVersion, set "h.mode" 3, set "h.preparing" 0, set "h.wait" 12, when (test "h.level" "1..") (op "h.wait" "=" "r.wait"), call "place"]
    ),
    ("rebuild", [call "sync", "gamemode spectator @s", call "land", "function manifold:gravity/publish"]),
    ( "place",
      [when (test "h.level" "1..") "return run function manifold:rooms/place"]
        ++ [when (test "g.frame" (show i)) (call ("write/" ++ show i)) | i <- [0 .. 23 :: Int]]
        ++ [call "place_coordinates"]
    ),
    ( "place_coordinates",
      [when (test "h.slot" (show slot)) (call ("offset/" ++ show slot)) | slot <- [0, 1 :: Int]]
        ++ [ "scoreboard players remove #h.py manifold " ++ show G.bodyHeight,
             "data modify storage manifold:landing position set value [0.0d,0.0d,0.0d]"
           ]
        ++ concat
          [ [ "execute store result storage manifold:landing position[" ++ show i ++ "] double 0.000244140625 run scoreboard players get " ++ score ("h.p" ++ a),
              "data modify storage manifold:landing " ++ a ++ " set string storage manifold:landing position[" ++ show i ++ "] 0 -1"
            ]
          | (i, a) <- zip [0 :: Int ..] xyz
          ]
        ++ [call "teleport with storage manifold:landing"]
    ),
    ("teleport", ["$tp @s $(x) $(y) $(z) ~ ~"])
  ]
    ++ [ ("turn/" ++ name, turnGuard ++ [op "h.before" "=" "g.frame", set "g.want" i, "function manifold:gravity/choose", call "begin"])
       | (i, name) <- zip [0 ..] ["floor", "ceiling", "west", "east", "north", "south"]
       ]
    ++ [("origin/" ++ show slot, ["scoreboard players remove " ++ score ("h.p" ++ a) ++ " " ++ show (n * G.unit + G.unit `div` 2) | (a, n) <- zip xyz (G.components (S.stageOrigin slot))]) | slot <- [0, 1 :: Int]]
    ++ [("offset/" ++ show slot, ["scoreboard players add " ++ score ("h.p" ++ a) ++ " " ++ show (n * G.unit + G.unit `div` 2) | (a, n) <- zip xyz (G.components (S.stageOrigin slot))]) | slot <- [0, 1 :: Int]]
    ++ [("read/" ++ show i, mapVector "g." "h.p" (G.apply frame)) | (i, frame) <- zip [0 :: Int ..] G.frames]
    ++ [("write/" ++ show i, mapVector "h.p" "g." (S.transformBlock frame)) | (i, frame) <- zip [0 :: Int ..] G.frames]
    ++ [ ( "wrap/" ++ show i,
           concat
             [ let physical = S.transformBlock frame (G.scale (32 * sign) basis)
                in [when (test ("g." ++ axis) (if sign > 0 then "..-1" else show G.period ++ "..")) (Level.invoke (Level.Wrap axis (sign < 0)))]
                     ++ [ when
                            (test ("g." ++ axis) (if sign > 0 then "..-1" else show G.period ++ ".."))
                            ("execute at @s run tp @s " ++ unwords ["~" ++ show n | n <- G.components physical] ++ " ~ ~")
                        ]
             | (axis, basis) <- zip xyz G.axes,
               sign <- [1, -1]
             ]
         )
       | (i, frame) <- zip [0 :: Int ..] G.frames
       ]
  where
    turnGuard =
      [when ("unless score " ++ score "h.mode" ++ " matches 1") "return 0", when ("unless score " ++ score "g.grounded" ++ " matches 1") "return 0", when "if predicate manifold:gravity/sneak" "return 0", call "sync", when ("unless score " ++ score "g.grounded" ++ " matches 1") "return 0"]
        ++ ["execute store result score #h.turn.allowed manifold run " ++ Level.invoke Level.CanTurn, when (test "h.turn.allowed" "0") "return 0"]
    mapVector destination source transform =
      concat
        [ let entries = G.components (transform basis); output = sum [j | (j, v) <- zip [0 ..] entries, v /= 0]; sign = entries !! output
           in [op (destination ++ xyz !! output) "=" (source ++ axis)] ++ [op (destination ++ xyz !! output) "*=" "g.neg" | sign < 0]
        | (axis, basis) <- zip xyz G.axes
        ]
