module Manifold.Gravity.DataPack (resources) where

import Manifold.Gravity qualified as G
import Manifold.Json
import Manifold.Level.DataPack qualified as Level
import Manifold.Messages qualified as M
import Manifold.Protocol (operation, score, setScore)

resources :: [(FilePath, String)]
resources =
  [("data/manifold/function/gravity/" ++ name ++ ".mcfunction", unlines body) | (name, body) <- functions]
    ++ [ ( "data/manifold/predicate/gravity/" ++ key ++ ".json",
           render $
             object
               [ ("type", string "minecraft:entity_properties"),
                 ("entity", string "this"),
                 ("predicate", object [("minecraft:type_specific/player", object [("input", object [(key, bool True)])])])
               ]
         )
       | key <- ["forward", "backward", "left", "right", "jump", "sneak", "sprint"]
       ]

s :: String -> Int -> String
s name = setScore ("g." ++ name) . fromIntegral

o :: String -> String -> String -> String
o a op b = operation ("g." ++ a) op ("g." ++ b)

test :: String -> String -> String
test a range = "if score " ++ score ("g." ++ a) ++ " matches " ++ range

cmp :: String -> String -> String -> String
cmp a op b = "if score " ++ score ("g." ++ a) ++ " " ++ op ++ " " ++ score ("g." ++ b)

when :: String -> String -> String
when condition action = "execute " ++ condition ++ " run " ++ action

call :: String -> String
call name = "function manifold:gravity/" ++ name

xyz :: [String]
xyz = ["x", "y", "z"]

marker :: String
marker = "@e[type=minecraft:marker,tag=manifold.direction,limit=1]"

functions :: [(String, [String])]
functions =
  [ ( "start",
      [ when "if entity @a[tag=manifold.pilot]" "return 0",
        "tag @s add manifold.pilot",
        "title @s reset",
        "function manifold:session/protect",
        "data modify storage manifold:session position set from entity @s Pos",
        "data modify storage manifold:session rotation set from entity @s Rotation",
        "data modify storage manifold:session dimension set from entity @s Dimension"
      ]
        ++ [when ("if entity @s[gamemode=" ++ mode ++ "]") (s "savedmode" i) | (i, mode) <- zip [0 ..] modes]
        ++ [ "execute store success score #g.loaded manifold run forceload query 0 0",
             "forceload add 0 0",
             "kill @e[tag=manifold.direction]",
             "summon minecraft:marker 0 0 0 {Tags:[\"manifold.direction\"]}",
             setScore "enabled" 1,
             setScore "quality" 1,
             "execute positioned 0 200 0 run function manifold:carrier/start",
             "gamemode spectator @s",
             "tp @s 0 200 0 0 0",
             call "reset"
           ]
    ),
    ("help", [M.chat "aqua" M.FlightControls, M.chat "gray" M.ExitHelp]),
    ( "stop",
      [ when "unless entity @s[tag=manifold.pilot]" "return 0",
        s "running" 0,
        setScore "enabled" 0,
        "function manifold:send",
        "data modify storage manifold:session x set string storage manifold:session position[0] 0 -1",
        "data modify storage manifold:session y set string storage manifold:session position[1] 0 -1",
        "data modify storage manifold:session z set string storage manifold:session position[2] 0 -1",
        "data modify storage manifold:session yaw set from storage manifold:session rotation[0]",
        "data modify storage manifold:session pitch set from storage manifold:session rotation[1]",
        call "restore with storage manifold:session"
      ]
        ++ [when (test "savedmode" (show i)) ("gamemode " ++ mode ++ " @s") | (i, mode) <- zip [0 :: Int ..] modes]
        ++ [ when (test "loaded" "0") "forceload remove 0 0",
             "tag @s remove manifold.pilot",
             "tag @s remove manifold.respawn_pending",
             "function manifold:session/release",
             "kill @e[tag=manifold.direction]",
             "kill @e[tag=manifold.carrier]"
           ]
    ),
    ("restore", ["$execute in $(dimension) run tp @s $(x) $(y) $(z) $(yaw) $(pitch)"]),
    ( "reset",
      [ s name value
      | (name, value) <-
          [ ("unit", G.unit),
            ("period", G.period),
            ("neg", -1),
            ("diag2", 2896),
            ("diag3", 2365),
            ("x", 8 * G.unit),
            ("y", 4 * G.unit),
            ("z", 0),
            ("vx", 0),
            ("vy", 0),
            ("vz", 0),
            ("frame", 0),
            ("fly", 1),
            ("grounded", 0),
            ("running", 1),
            ("cooldown", 0),
            ("jump.old", 0),
            ("sprint.old", 0),
            ("combo.old", 0),
            ("armed", 0),
            ("drag.ground", 3072),
            ("drag.air", 4055),
            ("drag.fly", 3482),
            ("accel.walk", 164),
            ("accel.fly", 307),
            ("accel.fall", G.acceleration),
            ("terminal", G.terminalSpeed),
            ("jump.speed", 1720)
          ]
      ]
        ++ [setScore "period" 32, setScore "r.wx" 0, setScore "r.wy" 0, setScore "r.wz" 0, setScore "r.window0" 0, setScore "r.window1" 0, setScore "r.held" (-1), "scoreboard players add #g.epoch manifold 1", call "bounds", call "publish"]
    ),
    ( "tick",
      [ when (test "running" "0") "return 0",
        when ("unless entity @s[gamemode=spectator]") (call "stop"),
        when (test "running" "0") "return 0",
        "execute positioned 0 200 0 unless entity @s[distance=..40] run tp @s 0 200 0 ~ ~",
        when (test "cooldown" "1..") "scoreboard players remove #g.cooldown manifold 1",
        call "input",
        call "integrate",
        call "move",
        call "publish"
      ]
    ),
    ( "input",
      [s "forward" 0, s "left" 0, s "vertical" 0, s "jump" 0, s "sprint" 0, s "sneak" 0]
        ++ [ when ("if predicate manifold:gravity/" ++ key) action
           | (key, action) <-
               [ ("forward", s "forward" 1),
                 ("backward", "scoreboard players remove #g.forward manifold 1"),
                 ("left", s "left" 1),
                 ("right", "scoreboard players remove #g.left manifold 1"),
                 ("jump", s "jump" 1),
                 ("sneak", s "sneak" 1),
                 ("sprint", s "sprint" 1)
               ]
           ]
        ++ [ s "combo" 0,
             when (test "jump" "1" ++ " " ++ test "sneak" "1") (s "combo" 1),
             when (test "jump" "0" ++ " " ++ test "sneak" "0" ++ " " ++ test "sprint" "0") (s "armed" 1),
             when ("if score #h.mode manifold matches 2") (Level.invoke Level.AirInput),
             when (test "armed" "1" ++ " " ++ test "combo" "1" ++ " " ++ test "combo.old" "0") (call "flight"),
             when (test "armed" "1" ++ " " ++ test "sprint" "1" ++ " " ++ test "sprint.old" "0") (call "aim"),
             when (test "fly" "1") (o "vertical" "=" "jump"),
             when (test "fly" "1") (o "vertical" "-=" "sneak"),
             "execute positioned 0.0 0.0 0.0 rotated as @s rotated ~ 0 positioned ^ ^ ^1 run tp " ++ marker ++ " ~ ~ ~"
           ]
        ++ readVector "f"
        ++ [ o "lx" "=" "fx",
             o "lx" "*=" "forward",
             o "temp" "=" "fz",
             o "temp" "*=" "left",
             o "lx" "+=" "temp",
             o "lz" "=" "fz",
             o "lz" "*=" "forward",
             o "temp" "=" "fx",
             o "temp" "*=" "left",
             o "lz" "-=" "temp",
             o "ly" "=" "vertical",
             o "ly" "*=" "unit",
             s "count" 0
           ]
        ++ [when ("unless score " ++ score ("g." ++ key) ++ " matches 0") "scoreboard players add #g.count manifold 1" | key <- ["forward", "left", "vertical"]]
        ++ concat
          [ [ when (test "count" (show count)) (o ("l" ++ axis) "*=" factor),
              when (test "count" (show count)) (o ("l" ++ axis) "/=" "unit")
            ]
          | count <- [2, 3 :: Int],
            let factor = if count == 2 then "diag2" else "diag3",
            axis <- xyz
          ]
        ++ [ call "transform",
             when (test "armed" "1" ++ " " ++ test "fly" "0" ++ " " ++ test "grounded" "1" ++ " " ++ test "jump" "1" ++ " " ++ test "jump.old" "0" ++ " " ++ test "combo" "0") (call "jump"),
             o "jump.old" "=" "jump",
             o "sprint.old" "=" "sprint",
             o "combo.old" "=" "combo"
           ]
    ),
    ("flight", [s "temp" 1, o "temp" "-=" "fly", o "fly" "=" "temp", s "grounded" 0]),
    ("jump", concat [[o "temp" "=" ("d" ++ axis), o "temp" "*=" "jump.speed", o ("v" ++ axis) "-=" "temp"] | axis <- xyz] ++ [s "grounded" 0]),
    ( "aim",
      [ when (test "cooldown" "1..") "return 0",
        "execute positioned 0.0 0.0 0.0 rotated as @s positioned ^ ^ ^1 run tp " ++ marker ++ " ~ ~ ~"
      ]
        ++ readVector "l"
        ++ [call "transform", s "best" (-1)]
        ++ concat
          [ [ o "abs" "=" ("a" ++ axis),
              when (test "abs" "..-1") (o "abs" "*=" "neg"),
              when (cmp "abs" ">" "best") (call ("aim/" ++ axis))
            ]
          | axis <- xyz
          ]
        ++ [call "choose"]
    ),
    ( "integrate",
      [ o "drag" "=" "drag.air",
        o "accel" "=" "accel.walk",
        when (test "grounded" "1") (o "drag" "=" "drag.ground"),
        when (test "fly" "1") (o "drag" "=" "drag.fly"),
        when (test "fly" "1") (o "accel" "=" "accel.fly")
      ]
        ++ concatMap integrate xyz
    ),
    ("move", [s "grounded" 0] ++ [call ("sweep/" ++ axis) | axis <- xyz]),
    ("publish", [setScore "tx.pending" 1, "execute unless score #tx.defer manifold matches 1 run function manifold:gravity/flush"]),
    ( "flush",
      [ setScore "tx.pending" 0,
        "scoreboard players add #g.seq manifold 1",
        "scoreboard players operation #g.seq manifold %= #pow16 manifold",
        "scoreboard players operation #g.epoch manifold %= #pow16 manifold",
        "execute at @s run tp @e[type=minecraft:item_display,tag=manifold.carrier,limit=1] ~ ~ ~",
        "execute if score #h.level manifold matches 1.. run function manifold:objects/bank/publish",
        "function manifold:send"
      ]
    ),
    ("transform", [when (test "frame" (show i)) (call ("basis/" ++ show i)) | i <- [0 .. 23 :: Int]]),
    ("bounds", [when (test "frame" (show i)) (call ("bounds/" ++ show i)) | i <- [0 .. 23 :: Int]]),
    ( "inside",
      [when "if score #h.mode manifold matches 1..3" ("return run " ++ Level.invoke Level.Inside), s "blocked" 0]
        ++ concat
          [ [ s ("near" ++ axis) 0,
              when (cmp axis "<" ("b" ++ axis)) (s ("near" ++ axis) 1),
              when (cmp axis ">" ("u" ++ axis)) (s ("near" ++ axis) 1)
            ]
          | axis <- xyz
          ]
        ++ [when (unwords [test ("near" ++ xyz !! i) "1" | i <- [0 .. 2], i /= free]) (s "blocked" 1) | G.Beam free _ <- G.beams]
    ),
    ( "choose",
      [when (test "cooldown" "1..") "return 0"]
        ++ [when (test "want" (show i)) (call ("candidate/" ++ show i)) | i <- [0 .. 5 :: Int]]
        ++ [ call "inside",
             when (test "blocked" "1") (call "bounds"),
             when (test "blocked" "1") "return 0",
             o "oldframe" "=" "frame"
           ]
        ++ [when (test "oldframe" (show i)) (call ("turn/" ++ show i)) | i <- [0 .. 23 :: Int]]
        ++ [call "bounds", s "fly" 0, s "grounded" 0, s "cooldown" 8]
    ),
    ("step", [call "integrate", call "move", call "publish"])
  ]
    ++ [ ("aim/" ++ axis, [o "best" "=" "abs", when (test ("a" ++ axis) "..-1") (s "want" negative), when (test ("a" ++ axis) "0..") (s "want" positive)])
       | (axis, negative, positive) <- [("x", 2, 3), ("y", 0, 1), ("z", 4, 5)]
       ]
    ++ [ ( "basis/" ++ show i,
           concat
             [ let entries = G.components (G.apply frame basis); j = sum [k | (k, v) <- zip [0 ..] entries, v /= 0]; sign = entries !! j
                in [o ("a" ++ xyz !! j) "=" ("l" ++ axis)] ++ [o ("a" ++ xyz !! j) "*=" "neg" | sign < 0]
             | (axis, basis) <- zip xyz G.axes
             ]
         )
       | (i, frame) <- zip [0 :: Int ..] G.frames
       ]
    ++ [("bounds/" ++ show i, bounds (G.gravity frame)) | (i, frame) <- zip [0 :: Int ..] G.frames]
    ++ [("candidate/" ++ show i, bounds g) | (i, g) <- zip [0 :: Int ..] G.downDirections]
    ++ [ ( "turn/" ++ show i,
           [ when (test "want" (show j)) (s "frame" (G.frameIndex (G.turnFrame frame g)))
           | (j, g) <- zip [0 :: Int ..] G.downDirections
           ]
         )
       | (i, frame) <- zip [0 :: Int ..] G.frames
       ]
    ++ [("down/" ++ name, [s "want" i, call "choose", call "publish"]) | (i, name) <- zip [0 ..] ["floor", "ceiling", "west", "east", "north", "south"]]
    ++ [ ( "sweep/" ++ axis,
           [when (test ("v" ++ axis) "0") "return 0", o "step" "=" ("v" ++ axis)]
             ++ ["execute if score #h.mode manifold matches 0 run " ++ command | G.Beam free _ <- G.beams, xyz !! free /= axis, command <- clip axis free]
             ++ [when ("if score " ++ score "h.mode" ++ " matches 2") (Level.invoke (Level.Clip axis))]
             ++ [ s "hit" 0,
                  when ("unless score " ++ score "g.step" ++ " = " ++ score ("g.v" ++ axis)) (s "hit" 1),
                  when (test "hit" "1" ++ " " ++ test ("d" ++ axis) "-1" ++ " " ++ test ("v" ++ axis) "..-1") (s "grounded" 1),
                  when (test "hit" "1" ++ " " ++ test ("d" ++ axis) "1" ++ " " ++ test ("v" ++ axis) "1..") (s "grounded" 1),
                  when (test "hit" "1") (s ("v" ++ axis) 0),
                  o axis "+=" "step",
                  when ("if score #h.mode manifold matches 2 " ++ test axis "..-1") (Level.invoke (Level.Wrap axis False)),
                  when ("if score #h.mode manifold matches 2 " ++ cmp axis ">=" "period") (Level.invoke (Level.Wrap axis True)),
                  o axis "%=" "period"
                ]
         )
       | axis <- xyz
       ]
    ++ [ ( "clip/" ++ axis,
           [ when (test "step" "0..") (o "limit" "=" ("u" ++ axis)),
             when (test "step" "..-1") (o "limit" "=" ("b" ++ axis)),
             o "limit" "-=" axis,
             when (test "step" "0..") (o "step" "<" "limit"),
             when (test "step" "..-1") (o "step" ">" "limit")
           ]
         )
       | axis <- xyz
       ]
  where
    modes = ["survival", "creative", "adventure", "spectator"]
    readVector prefix = ["execute store result score " ++ score ("g." ++ prefix ++ axis) ++ " run data get entity " ++ marker ++ " Pos[" ++ show i ++ "] " ++ show G.unit | (i, axis) <- zip [0 :: Int ..] xyz]
    bounds g =
      concat
        [ [s ("d" ++ axis) direction, s ("b" ++ axis) (G.beamRadius + extent), s ("u" ++ axis) (G.period - G.beamRadius - extent)]
        | (axis, direction, extent) <- zip3 xyz (G.components g) (G.components (G.extents g))
        ]
    integrate axis =
      [ when (test "fly" "1") (o ("v" ++ axis) "*=" "drag"),
        when (test "fly" "1") (o ("v" ++ axis) "/=" "unit"),
        when (test "fly" "0" ++ " " ++ test ("d" ++ axis) "0") (o ("v" ++ axis) "*=" "drag"),
        when (test "fly" "0" ++ " " ++ test ("d" ++ axis) "0") (o ("v" ++ axis) "/=" "unit"),
        o "temp" "=" ("a" ++ axis),
        o "temp" "*=" "accel",
        o "temp" "/=" "unit",
        o ("v" ++ axis) "+=" "temp",
        o "temp" "=" ("d" ++ axis),
        o "temp" "*=" "accel.fall",
        when (test "fly" "0") (o ("v" ++ axis) "+=" "temp"),
        when (test ("v" ++ axis) (show (G.terminalSpeed + 1) ++ "..")) (s ("v" ++ axis) G.terminalSpeed),
        when (test ("v" ++ axis) (".." ++ show (-G.terminalSpeed - 1))) (s ("v" ++ axis) (-G.terminalSpeed))
      ]
    clip axis free =
      let other = concat [a | a <- xyz, a /= axis, a /= xyz !! free]
       in [ when (cmp other "<" ("b" ++ other)) (call ("clip/" ++ axis)),
            when (cmp other ">" ("u" ++ other)) (call ("clip/" ++ axis))
          ]
