module Manifold.DataPack (resources) where

import Data.List (intercalate)
import Manifold.Gravity.DataPack qualified as Gravity
import Manifold.Hybrid.DataPack qualified as Hybrid
import Manifold.Json
import Manifold.Level.DataPack qualified as Level
import Manifold.Protocol
import Manifold.Quality

resources :: [(FilePath, String)]
resources =
  Gravity.resources
    ++ Hybrid.resources
    ++ Level.resources
    ++ [("data/manifold/function/" ++ name ++ ".mcfunction", unlines body) | (name, body) <- functions ++ encodingFunctions]
    ++ [("data/minecraft/tags/function/" ++ name ++ ".json", render $ object [("values", array [string ("manifold:" ++ name)])]) | name <- ["load", "tick"]]
  where
    carrier = "@e[type=minecraft:item_display,tag=manifold.carrier,limit=1]"
    colors = "[" ++ intercalate "," (replicate payloadWords "0") ++ "]"
    fallProtection = "attributes[{id:\"minecraft:fall_damage_multiplier\"}].modifiers[{id:\"manifold:session_fall_protection\"}]"
    functions =
      [ ( "load",
          ["scoreboard objectives add manifold dummy", "scoreboard objectives add manifold.action trigger", "function manifold:joinery/load"]
            ++ constants
            ++ ["scoreboard players add " ++ score (fieldName f) ++ " 0" | f <- header]
            ++ ["execute if score #h.level manifold matches 1.. run function manifold:rooms/restore"]
            ++ [setScore "tx.ready" 0, setScore "tx.defer" 0, setScore "tx.pending" 0, "execute unless data storage manifold:tx colors[" ++ show (payloadWords - 1) ++ "] run data modify storage manifold:tx colors set value " ++ colors]
        ),
        ("start", ["execute as @p at @s run function manifold:session/start"]),
        ("flight", ["execute as @p at @s run function manifold:session/flight"]),
        ("stop", ["execute as @a[tag=manifold.pilot] at @s run function manifold:session/stop"]),
        ("reset", ["execute as @a[tag=manifold.pilot] at @s run function manifold:session/reset"]),
        ("help", ["execute as @p at @s run function manifold:session/help"]),
        ("session/help", ["execute if score #h.mode manifold matches 0 run return run function manifold:gravity/help", "execute if score #h.level manifold matches 1 run return run function manifold:joinery/help", "execute if score #h.level manifold matches 2 run return run function manifold:three_rings/help", "function manifold:atrium/help"]),
        ("session/start", ["execute if entity @s[tag=manifold.pilot] run function manifold:session/stop", setScore "h.level" 0, "execute at @s run function manifold:hybrid/start"]),
        ("session/flight", ["execute if entity @s[tag=manifold.pilot] run function manifold:session/stop", setScore "h.level" 0, setScore "h.mode" 0, "execute at @s run function manifold:gravity/start"]),
        ("session/stop", ["execute if score #h.mode manifold matches 1.. run return run function manifold:hybrid/stop", "function manifold:gravity/stop"]),
        ("session/reset", ["execute if score #h.mode manifold matches 1.. run return run function manifold:hybrid/reset", "function manifold:gravity/reset"]),
        ( "session/protect",
          [ "tag @s remove manifold.returning",
            "execute unless data entity @s " ++ fallProtection ++ " run attribute @s minecraft:fall_damage_multiplier modifier add manifold:session_fall_protection -1 add_multiplied_total"
          ]
        ),
        ( "session/release",
          [ "tag @s add manifold.returning",
            "execute if entity @s[nbt={fall_distance:0.0d}] run function manifold:session/unprotect"
          ]
        ),
        ( "session/unprotect",
          [ "execute if data entity @s " ++ fallProtection ++ " run attribute @s minecraft:fall_damage_multiplier modifier remove manifold:session_fall_protection",
            "tag @s remove manifold.returning"
          ]
        ),
        ( "tick",
          [ "execute as @a[tag=manifold.returning,tag=!manifold.pilot,nbt={fall_distance:0.0d}] run function manifold:session/unprotect",
            "execute as @a[tag=manifold.pilot,limit=1] at @s run function manifold:session/tick"
          ]
        ),
        ( "session/tick",
          [setScore "tx.defer" 1, setScore "tx.pending" 0, "function manifold:session/step", setScore "tx.defer" 0, "execute if entity @s[tag=manifold.pilot] if score #tx.pending manifold matches 1 run function manifold:gravity/flush"]
        ),
        ( "session/step",
          [ "execute if entity @s[nbt={Health:0.0f}] if score #h.mode manifold matches 1.. run tag @s add manifold.respawn_pending",
            "execute if entity @s[nbt={Health:0.0f}] run return 0",
            "function manifold:session/protect",
            "execute if entity @s[tag=manifold.respawn_pending] if score #h.mode manifold matches 1.. run return run function manifold:hybrid/respawn",
            "execute store result score #h.level.ready manifold run " ++ Level.invoke Level.Validate,
            "execute if score #h.level.ready manifold matches 0 run return 0",
            "execute if dimension manifold:stage if score #h.mode manifold matches 1 unless score #h.cache.version manifold matches " ++ show Hybrid.cacheVersion ++ " run return run function manifold:hybrid/rebuild",
            "scoreboard players enable @s manifold.action",
            "execute if score @s manifold.action matches 1.. run function manifold:controls",
            "execute if score #h.mode manifold matches 1.. run function manifold:hybrid/tick",
            "execute if entity @s[tag=manifold.pilot] if score #h.mode manifold matches 0 run function manifold:gravity/tick"
          ]
        ),
        ( "controls",
          [ "execute if score @s manifold.action matches 1 if score #h.mode manifold matches 0 run function manifold:gravity/aim",
            "execute if score @s manifold.action matches 1 if score #h.mode manifold matches 1 run function manifold:hybrid/turn/aim",
            "execute if score @s manifold.action matches 3 if score #h.mode manifold matches 0 run function manifold:gravity/flight",
            "execute if score @s manifold.action matches 4 run function manifold:session/reset",
            "scoreboard players set @s manifold.action 0"
          ]
        ),
        ( "carrier/start",
          [ setScore "tx.ready" 0,
            "kill @e[tag=manifold.carrier]",
            "summon minecraft:item_display ~ ~ ~ {Tags:[\"manifold.carrier\"],width:0f,height:0f,view_range:4f,billboard:\"fixed\",item:{id:\"minecraft:stone\",count:1,components:{\"minecraft:item_model\":\"manifold:carrier\",\"minecraft:custom_model_data\":{colors:" ++ colors ++ "}}}}",
            "data modify storage manifold:tx colors set value " ++ colors
          ]
        ),
        ("send", encodeCommands ++ ["data modify entity " ++ carrier ++ " item.components.\"minecraft:custom_model_data\".colors set from storage manifold:tx colors"])
      ]
        ++ [("quality/" ++ qualityName q, [setScore "quality" (fromIntegral (qualityId q)), "function manifold:send"]) | q <- qualities]
