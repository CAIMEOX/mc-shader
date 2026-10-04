module Escher.DataPack (dataPack) where

import Data.List (intercalate)
import Escher.Folding qualified as F
import Escher.Folding.Scene qualified as Folding
import Escher.Json
import Escher.Protocol
import Escher.Quality
import Escher.Scene

dataPack :: [(FilePath, String)]
dataPack =
  [("data/escher/function/" ++ name ++ ".mcfunction", unlines body) | (name, body) <- functions]
    ++ [("data/minecraft/tags/function/" ++ tag ++ ".json", render (object [("values", array [string ("escher:" ++ tag)])])) | tag <- ["load", "tick"]]
  where
    carrier = "@e[type=minecraft:item_display,tag=escher.carrier,limit=1]"
    functions =
      [ ( "load",
          ["scoreboard objectives add escher dummy", "scoreboard objectives add escher.action trigger", "scoreboard objectives add escher.laps dummy"]
            ++ constants
            ++ [setScore "ratio" 655, setScore "fold" 1]
            ++ ["execute unless score " ++ score name ++ " matches " ++ range ++ " run " ++ setScore name value | (name, range, value) <- [("turn", "0..1199", 399), ("enabled", "0..1", 1), ("quality", "0..3", 2), ("scene", "0..1", 0), ("folding", "0..1000", 1000), ("animate", "0..1", 1), ("rolling", "0..1", 1), ("overview", "0..1", 0)]]
            ++ ["function escher:period"]
        ),
        ( "period",
          [ "execute if score #scene escher matches 0 run " ++ setScore "period" 18,
            "execute if score #scene escher matches 1 run " ++ setScore "period" (fromIntegral F.physicalPeriod),
            operation "span" "=" "period",
            operation "span" "*=" "pow1"
          ]
        ),
        ( "start",
          [setScore "ready" 0, "kill @e[tag=escher.carrier]", "execute align xyz run summon minecraft:item_display ~ ~ ~ {Tags:[\"escher.carrier\"],width:0f,height:0f,view_range:4f,billboard:\"fixed\",item:{id:\"minecraft:stone\",count:1,components:{\"minecraft:item_model\":\"escher:carrier\",\"minecraft:custom_model_data\":{colors:" ++ emptyColors ++ "}}}}"]
            ++ ["execute store result score " ++ score ("origin." ++ axis) ++ " run data get entity " ++ carrier ++ " Pos[" ++ show i ++ "]" | (i, axis) <- zip [0 :: Int ..] ["x", "y", "z"]]
            ++ [ "function escher:period",
                 "execute if score #scene escher matches 0 as " ++ carrier ++ " at @s run tp @s ~ ~ ~18",
                 "execute if score #scene escher matches 1 as " ++ carrier ++ " at @s run tp @s ~ ~ ~" ++ show F.physicalPeriod,
                 "data modify storage escher:tx colors set value " ++ emptyColors,
                 "function escher:send",
                 setScore "ready" 1
               ]
        ),
        ( "send",
          [ "execute if score " ++ score "ratio" ++ " matches ..511 run " ++ setScore "ratio" 512,
            "execute if score " ++ score "ratio" ++ " matches 1005.. run " ++ setScore "ratio" 1004,
            "execute if score #folding escher matches ..-1 run " ++ setScore "folding" 0,
            "execute if score #folding escher matches 1001.. run " ++ setScore "folding" 1000
          ]
            ++ encodeCommands
            ++ ["data modify entity " ++ carrier ++ " item.components.\"minecraft:custom_model_data\".colors set from storage escher:tx colors"]
            ++ ["execute store result storage escher:control " ++ name ++ " int 1 run scoreboard players get " ++ score name | name <- ["enabled", "turn", "quality", "scene", "folding", "animate", "rolling", "overview"]]
        ),
        ( "tick",
          [ "execute as @a[scores={escher.action=1..}] at @s run function escher:controls",
            "scoreboard players enable @a escher.action",
            "execute if score #scene escher matches 1 if score #overview escher matches 1 if score #enabled escher matches 1 run function escher:folding/anchor",
            "execute if score " ++ score "fold" ++ " matches 1 at " ++ carrier ++ " as @a[distance=..100] at @s run function escher:fold/check"
          ]
        ),
        ( "controls",
          [ "execute if score @s escher.action matches 1 if score #scene escher matches 0 run function escher:twist",
            "execute if score @s escher.action matches 1 if score #scene escher matches 1 run function escher:folding/toggle",
            "execute if score @s escher.action matches 2 run function escher:toggle",
            "scoreboard players set @s escher.action 0"
          ]
        ),
        ("twist", ["scoreboard players add " ++ score "turn" ++ " 200", "execute if score " ++ score "turn" ++ " matches 1200.. run " ++ setScore "turn" 0, "function escher:send"]),
        ("toggle", [setScore "one" 1, operation "one" "-=" "enabled", operation "enabled" "=" "one", "function escher:send"]),
        ( "fold/check",
          [ "execute store result score " ++ score "z" ++ " run data get entity @s Pos[2]",
            operation "z" "-=" "origin.z",
            "execute if score #z escher >= #span escher run function escher:fold/forward",
            "execute if score " ++ score "z" ++ " matches ..-1 run function escher:fold/backward"
          ]
        ),
        ("fold/forward", wrapCommands (-1) ++ ["scoreboard players add @s escher.laps 2"]),
        ("fold/backward", wrapCommands 1 ++ ["scoreboard players remove @s escher.laps 2"]),
        ( "demo",
          [setScore "ready" 0, setScore "turn" 399, setScore "enabled" 1, "function escher:period", "forceload add -16 -64 16 144"]
            ++ ["fill -11 64 " ++ show z ++ " 8 77 " ++ show (z + F.physicalPeriod - 1) ++ " minecraft:air strict" | z <- copies F.physicalPeriod]
            ++ ["execute if score #scene escher matches 0 positioned 0 70 " ++ show z ++ " run function escher:room" | z <- [-18, 0, 18, 36 :: Int]]
            ++ ["execute if score #scene escher matches 1 positioned 0 70 " ++ show z ++ " run function escher:room/folding" | z <- copies F.physicalPeriod]
            ++ ["execute positioned 0 70 0 run function escher:start", "time set noon", "weather clear", "gamerule minecraft:advance_time false", "gamerule minecraft:advance_weather false"]
        ),
        ("room", blocks voxels),
        ("room/folding", blocks Folding.collisionBlocks),
        ("scene/gallery", [setScore "scene" 0, setScore "overview" 0, "function escher:demo", "gamemode adventure @a", "tp @a 0 65 2 0 0"]),
        ("scene/folding", [setScore "scene" 1, setScore "overview" 1, setScore "folding" 1000, setScore "animate" 1, setScore "rolling" 1, "function escher:demo", "gamemode spectator @a", "tp @a 0 65 22 0 10"]),
        ("folding/flat", [setScore "folding" 0, setScore "animate" 1, "function escher:send"]),
        ("folding/spiral", [setScore "folding" 1000, setScore "animate" 1, "function escher:send"]),
        ("folding/toggle", [setScore "next" 1000, "execute if score #folding escher matches 1.. run " ++ setScore "next" 0, operation "folding" "=" "next", setScore "animate" 1, "function escher:send"]),
        ("folding/set", ["$scoreboard players set #folding escher $(amount)", setScore "animate" 0, "function escher:send"]),
        ("folding/overview", [setScore "overview" 1, setScore "enabled" 1, "function escher:send", "gamemode spectator @a", "tp @a 0 65 22 0 10"]),
        ("folding/anchor", ["execute at " ++ carrier ++ " as @a run tp @s ~ ~-5 ~-" ++ show (F.physicalPeriod `div` 2)]),
        ("folding/walk", [setScore "overview" 0, setScore "enabled" 1, "function escher:send", "gamemode adventure @a", "tp @a 0 65 2 0 0"]),
        ("folding/balls/pause", [setScore "rolling" 0, "function escher:send"]),
        ("folding/balls/run", [setScore "rolling" 1, "function escher:send"])
      ]
        ++ [("quality/" ++ qualityName q, [setScore "quality" (fromIntegral (qualityId q)), "function escher:send"]) | q <- qualities]
    emptyColors = "[" ++ intercalate "," (replicate headerWords "0") ++ "]"
    copies size = map (* size) [-1, 0, 1, 2]
    wrapCommands direction = ["execute if score #scene escher matches " ++ show sceneId ++ " run tp @s ~ ~ ~" ++ show (direction * 2 * period) ++ " ~ ~" | (sceneId, period) <- [(0 :: Int, 18), (1, F.physicalPeriod)]]
    blocks values = ["setblock ~" ++ show x ++ " ~" ++ show y ++ " ~" ++ show z ++ " minecraft:" ++ block material x z ++ " strict" | ((x, y, z), material) <- values]
    block Checker x z = if even (x + z) then "white_concrete" else "green_terracotta"
    block Stone _ _ = "smooth_sandstone"
    block Chalk _ _ = "smooth_quartz"
    block Green _ _ = "green_concrete"
    block Red _ _ = "red_concrete"
    block Brass _ _ = "yellow_terracotta"
