module Backrooms.DataPack (dataPack) where

import Backrooms.Domain
import Backrooms.Json
import Backrooms.Protocol
import Data.List (intercalate)

dataPack :: [(FilePath, String)]
dataPack =
  [("data/backrooms/function/" ++ name ++ ".mcfunction", unlines body) | (name, body) <- functions]
    ++ [("data/minecraft/tags/function/" ++ tag ++ ".json", render (object [("values", array [string ("backrooms:" ++ tag)])])) | tag <- ["load", "tick"]]

functions :: [(String, [String])]
functions =
  [ ( "enter",
      [ "execute as @p at @s run function backrooms:worldgen/enter"
      ]
    ),
    ("home", ["execute as @p[tag=backrooms.explorer] at @s run function backrooms:worldgen/home"]),
    ("exit", ["execute as @p[tag=backrooms.explorer] at @s run function backrooms:worldgen/exit"]),
    ( "lab/enter",
      [ "execute as @p at @s run function backrooms:session/request"
      ]
    ),
    ( "session/request",
      [ "execute if entity @s[tag=backrooms.owner] run return run function backrooms:reset",
        "tag @s add backrooms.waiting",
        "title @s actionbar {text:\"正在进入后室\",color:\"yellow\"}",
        "execute unless score #building backrooms matches 1 run function backrooms:setup/request"
      ]
    ),
    ( "setup/request",
      [ "scoreboard players set #building backrooms 1",
        "execute in backrooms:level0 run forceload add -16 -32 15 79",
        "execute in backrooms:level0 run forceload add 112 -32 159 31",
        "schedule function backrooms:setup/check 1t replace"
      ]
    ),
    ( "setup/check",
      [ "scoreboard players set #loaded backrooms 1",
        "execute in backrooms:level0 unless loaded -16 64 -32 run scoreboard players set #loaded backrooms 0",
        "execute in backrooms:level0 unless loaded -16 64 -16 run scoreboard players set #loaded backrooms 0",
        "execute in backrooms:level0 unless loaded -16 64 0 run scoreboard players set #loaded backrooms 0",
        "execute in backrooms:level0 unless loaded -16 64 16 run scoreboard players set #loaded backrooms 0",
        "execute in backrooms:level0 unless loaded -16 64 32 run scoreboard players set #loaded backrooms 0",
        "execute in backrooms:level0 unless loaded -16 64 48 run scoreboard players set #loaded backrooms 0",
        "execute in backrooms:level0 unless loaded -16 64 64 run scoreboard players set #loaded backrooms 0",
        "execute in backrooms:level0 unless loaded 0 64 -32 run scoreboard players set #loaded backrooms 0",
        "execute in backrooms:level0 unless loaded 0 64 -16 run scoreboard players set #loaded backrooms 0",
        "execute in backrooms:level0 unless loaded 0 64 0 run scoreboard players set #loaded backrooms 0",
        "execute in backrooms:level0 unless loaded 0 64 16 run scoreboard players set #loaded backrooms 0",
        "execute in backrooms:level0 unless loaded 0 64 32 run scoreboard players set #loaded backrooms 0",
        "execute in backrooms:level0 unless loaded 0 64 48 run scoreboard players set #loaded backrooms 0",
        "execute in backrooms:level0 unless loaded 0 64 64 run scoreboard players set #loaded backrooms 0",
        "execute in backrooms:level0 unless loaded 112 64 -32 run scoreboard players set #loaded backrooms 0",
        "execute in backrooms:level0 unless loaded 112 64 -16 run scoreboard players set #loaded backrooms 0",
        "execute in backrooms:level0 unless loaded 112 64 0 run scoreboard players set #loaded backrooms 0",
        "execute in backrooms:level0 unless loaded 112 64 16 run scoreboard players set #loaded backrooms 0",
        "execute in backrooms:level0 unless loaded 128 64 -32 run scoreboard players set #loaded backrooms 0",
        "execute in backrooms:level0 unless loaded 128 64 -16 run scoreboard players set #loaded backrooms 0",
        "execute in backrooms:level0 unless loaded 128 64 0 run scoreboard players set #loaded backrooms 0",
        "execute in backrooms:level0 unless loaded 128 64 16 run scoreboard players set #loaded backrooms 0",
        "execute in backrooms:level0 unless loaded 144 64 -32 run scoreboard players set #loaded backrooms 0",
        "execute in backrooms:level0 unless loaded 144 64 -16 run scoreboard players set #loaded backrooms 0",
        "execute in backrooms:level0 unless loaded 144 64 0 run scoreboard players set #loaded backrooms 0",
        "execute in backrooms:level0 unless loaded 144 64 16 run scoreboard players set #loaded backrooms 0",
        "execute if score #loaded backrooms matches 0 run schedule function backrooms:setup/check 1t replace",
        "execute if score #loaded backrooms matches 1 run function backrooms:setup/complete"
      ]
    ),
    ( "setup/complete",
      [ "execute unless score #ready backrooms matches 1 in backrooms:level0 run function backrooms:setup/build",
        "scoreboard players set #ready backrooms 1",
        "scoreboard players set #building backrooms 0",
        "execute as @a[tag=backrooms.waiting,limit=1] at @s run function backrooms:session/enter"
      ]
    ),
    ( "session/enter",
      [ "tag @a remove backrooms.owner",
        "data modify storage backrooms:session return set value {dimension:\"minecraft:overworld\"}",
        "data modify storage backrooms:session return.dimension set from entity @s Dimension",
        "data modify storage backrooms:session return.x set from entity @s Pos[0]",
        "data modify storage backrooms:session return.y set from entity @s Pos[1]",
        "data modify storage backrooms:session return.z set from entity @s Pos[2]",
        "data modify storage backrooms:session return.yaw set from entity @s Rotation[0]",
        "data modify storage backrooms:session return.pitch set from entity @s Rotation[1]",
        "data modify storage backrooms:session return.mode set from entity @s playerGameType",
        "tag @s remove backrooms.waiting",
        "tag @s add backrooms.owner",
        "gamemode adventure @s",
        "execute in backrooms:level0 run tp @s 0 64 2 0 0",
        "execute in backrooms:level0 run function backrooms:carrier/create",
        "scoreboard players set #active backrooms 1",
        "scoreboard players set #enabled backrooms 1",
        "scoreboard players set #room backrooms 0",
        "scoreboard players set #mirror backrooms 1",
        "scoreboard players set #door.z backrooms 12",
        "function backrooms:send",
        "title @s actionbar {text:\"\"}"
      ]
    ),
    ( "carrier/create",
      [ "kill @e[tag=backrooms.carrier]",
        "summon minecraft:item_display 0 66 10 {Tags:[\"backrooms.carrier\"],width:0f,height:0f,view_range:4f,billboard:\"fixed\",item:{id:\"minecraft:stone\",count:1,components:{\"minecraft:item_model\":\"backrooms:carrier\",\"minecraft:custom_model_data\":{colors:[0,0,0,0]}}}}"
      ]
    ),
    ( "tick",
      [ "execute as @a[tag=backrooms.explorer,scores={backrooms.action=1..}] at @s run function backrooms:worldgen/controls",
        "scoreboard players enable @a[tag=backrooms.explorer] backrooms.action",
        "execute if entity @a[tag=backrooms.explorer] run scoreboard players add #lobby.hum backrooms 1",
        "execute if score #lobby.hum backrooms matches 100.. run function backrooms:worldgen/ambient",
        "execute as @a[tag=backrooms.owner,scores={backrooms.action=1..}] at @s run function backrooms:controls",
        "scoreboard players enable @a[tag=backrooms.owner] backrooms.action",
        "execute if score #active backrooms matches 1 as @a[tag=backrooms.owner,limit=1] in backrooms:level0 at @s run function backrooms:motion",
        "execute if score #enabled backrooms matches 1 as @a[tag=backrooms.owner,limit=1] in backrooms:level0 at @s run tp @e[type=minecraft:item_display,tag=backrooms.carrier,limit=1] ~ ~2 ~4",
        "execute if score #active backrooms matches 1 run scoreboard players add #hum backrooms 1",
        "execute if score #hum backrooms matches 80.. run function backrooms:ambient"
      ]
    ),
    ( "motion",
      [ "execute store result score #x backrooms run data get entity @s Pos[0] 1000",
        "execute store result score #z backrooms run data get entity @s Pos[2] 1000",
        "execute if score #room backrooms matches 0 run function backrooms:corridor/check",
        "execute if score #room backrooms matches 1 if score #x backrooms matches ..115999 if score #z backrooms matches -700..700 run function backrooms:portal/return"
      ]
    ),
    ( "corridor/check",
      [ "execute if score #z backrooms matches 48000.. run function backrooms:loop/forward",
        "execute if score #z backrooms matches ..-1 run function backrooms:loop/backward",
        "execute if score #x backrooms matches 4000.. if score #z backrooms matches 11300..12700 run function backrooms:portal/enter_first",
        "execute if score #x backrooms matches 4000.. if score #z backrooms matches 35300..36700 run function backrooms:portal/enter_second"
      ]
    ),
    ( "mirror/toggle",
      [ "scoreboard players set #next backrooms 1",
        "scoreboard players operation #next backrooms -= #mirror backrooms",
        "scoreboard players operation #mirror backrooms = #next backrooms",
        "function backrooms:send"
      ]
    ),
    ( "controls",
      [ "execute if score @s backrooms.action matches 1 run function backrooms:mirror/toggle",
        "execute if score @s backrooms.action matches 2 run function backrooms:stop",
        "execute if score @s backrooms.action matches 3 run function backrooms:reset",
        "scoreboard players set @s backrooms.action 0"
      ]
    ),
    ( "reset",
      [ "execute in backrooms:level0 run tp @s 0 64 2 0 0",
        "scoreboard players set #room backrooms 0",
        "scoreboard players set #enabled backrooms 1",
        "scoreboard players set #active backrooms 1",
        "function backrooms:send"
      ]
    ),
    ( "ambient",
      [ "scoreboard players set #hum backrooms 0",
        "execute as @a[tag=backrooms.owner,limit=1] at @s run playsound minecraft:block.beacon.ambient ambient @s ~ ~ ~ 0.15 0.6 0"
      ]
    ),
    ( "stop",
      [ "scoreboard players set #enabled backrooms 0",
        "scoreboard players set #active backrooms 0",
        "function backrooms:send",
        "schedule function backrooms:session/finish 4t replace"
      ]
    ),
    ( "session/return",
      [ "$execute in $(dimension) run tp @s $(x) $(y) $(z) $(yaw) $(pitch)",
        "execute if data storage backrooms:session {return:{mode:0}} run gamemode survival @s",
        "execute if data storage backrooms:session {return:{mode:1}} run gamemode creative @s",
        "execute if data storage backrooms:session {return:{mode:2}} run gamemode adventure @s",
        "execute if data storage backrooms:session {return:{mode:3}} run gamemode spectator @s"
      ]
    )
  ]
    ++ [("load", loadCommands), ("send", sendCommands), ("setup/build", buildCommands), ("session/finish", ["execute as @a[tag=backrooms.owner] at @s run function backrooms:session/return with storage backrooms:session return", "tag @a remove backrooms.owner"])]
    ++ portalFunctions
    ++ worldGenFunctions

worldGenFunctions :: [(String, [String])]
worldGenFunctions =
  [ ( "worldgen/enter",
      [ "execute if entity @s[tag=backrooms.explorer] run return run function backrooms:worldgen/home",
        "data modify storage backrooms:exploration return set value {}",
        "data modify storage backrooms:exploration return.dimension set from entity @s Dimension",
        "data modify storage backrooms:exploration return.x set from entity @s Pos[0]",
        "data modify storage backrooms:exploration return.y set from entity @s Pos[1]",
        "data modify storage backrooms:exploration return.z set from entity @s Pos[2]",
        "data modify storage backrooms:exploration return.yaw set from entity @s Rotation[0]",
        "data modify storage backrooms:exploration return.pitch set from entity @s Rotation[1]",
        "data modify storage backrooms:exploration return.mode set from entity @s playerGameType",
        "tag @s add backrooms.explorer",
        "gamemode adventure @s",
        "function backrooms:worldgen/home",
        "title @s actionbar {text:\"后室 · Level 0\",color:\"yellow\"}"
      ]
    ),
    ("worldgen/home", ["execute in backrooms:interior run tp @s 0.5 64.0 0.5 0 0", "scoreboard players set #lobby backrooms 1"]),
    ( "worldgen/controls",
      [ "execute if score @s backrooms.action matches 2 run function backrooms:worldgen/exit",
        "execute if score @s backrooms.action matches 3 run function backrooms:worldgen/home",
        "scoreboard players set @s backrooms.action 0"
      ]
    ),
    ( "worldgen/exit",
      [ "function backrooms:worldgen/return with storage backrooms:exploration return",
        "tag @s remove backrooms.explorer",
        "scoreboard players set #lobby backrooms 0"
      ]
    ),
    ( "worldgen/return",
      [ "$execute in $(dimension) run tp @s $(x) $(y) $(z) $(yaw) $(pitch)",
        "execute if data storage backrooms:exploration {return:{mode:0}} run gamemode survival @s",
        "execute if data storage backrooms:exploration {return:{mode:1}} run gamemode creative @s",
        "execute if data storage backrooms:exploration {return:{mode:2}} run gamemode adventure @s",
        "execute if data storage backrooms:exploration {return:{mode:3}} run gamemode spectator @s"
      ]
    ),
    ( "worldgen/ambient",
      [ "scoreboard players set #lobby.hum backrooms 0",
        "execute as @a[tag=backrooms.explorer] at @s run playsound minecraft:block.beacon.ambient ambient @s ~ ~ ~ 0.12 0.65 0"
      ]
    )
  ]

loadCommands :: [String]
loadCommands =
  ["scoreboard objectives add backrooms dummy", "scoreboard objectives add backrooms.action trigger", "scoreboard objectives add backrooms.laps dummy"]
    ++ ["data modify storage backrooms:tx colors set value [" ++ intercalate "," (replicate headerWords "0") ++ "]"]
    ++ ["scoreboard players set #pow" ++ show i ++ " backrooms " ++ show (2 ^ i :: Integer) | i <- [0 .. 26 :: Int]]
    ++ ["scoreboard players set #" ++ name ++ " backrooms " ++ show value | (name, value) <- [("period", period), ("enabled", 0), ("active", 0), ("building", 0), ("quality", 2), ("mirror", 1), ("room", 0), ("hum", 0)]]

sendCommands :: [String]
sendCommands =
  ["scoreboard players set #origin.x backrooms 0", "scoreboard players set #origin.y backrooms " ++ show baseY, "scoreboard players set #origin.z backrooms 0", "execute if score #room backrooms matches 1 run scoreboard players set #origin.x backrooms 128"]
    ++ encodeCommands
    ++ ["execute in backrooms:level0 run data modify entity @e[type=minecraft:item_display,tag=backrooms.carrier,limit=1] item.components.\"minecraft:custom_model_data\".colors set from storage backrooms:tx colors"]

buildCommands :: [String]
buildCommands =
  ["fill -6 64 -24 6 72 72 minecraft:air strict", "fill 114 64 -20 141 74 20 minecraft:air strict"]
    ++ map collisionCommand (collisionVolumes Corridor ++ collisionVolumes Hall)

collisionCommand :: Box -> String
collisionCommand b = "fill " ++ intercalate " " (map (show . (round :: Double -> Int)) (components (lower b) ++ map (subtract 1) (components (upper b)))) ++ " " ++ blockName (material b) ++ " strict"

portalFunctions :: [(String, [String])]
portalFunctions =
  [ ("portal/enter_first", enterPortal 0),
    ("portal/enter_second", enterPortal 1),
    ("portal/return", returnPortal),
    ("loop/forward", ["tp @s ~ ~ ~-" ++ show spanLength ++ " ~ ~", "scoreboard players add @s backrooms.laps 2"]),
    ("loop/backward", ["tp @s ~ ~ ~" ++ show spanLength ++ " ~ ~", "scoreboard players remove @s backrooms.laps 2"])
  ]
  where
    worldShiftX = let (a, _, _) = origin (room Hall); (b, _, _) = origin (room Corridor) in round (a - b + targetX portal - sourceX portal) :: Int
    anchor cell = round (centerZ portal) + cell * period :: Int
    enterPortal cell =
      [ "scoreboard players set #door.z backrooms " ++ show (anchor cell),
        "tp @s ~" ++ show worldShiftX ++ " ~ ~-" ++ show (anchor cell) ++ " ~ ~",
        "scoreboard players set #room backrooms 1",
        "function backrooms:send"
      ]
    returnPortal =
      ["execute if score #door.z backrooms matches " ++ show (anchor cell) ++ " run tp @s ~-" ++ show worldShiftX ++ " ~ ~" ++ show (anchor cell) ++ " ~ ~" | cell <- [0, 1]]
        ++ ["scoreboard players set #room backrooms 0", "function backrooms:send"]
