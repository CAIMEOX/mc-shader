module Manifold.Objects.DataPack (resources) where

import Data.List (intercalate)
import Manifold.Gravity qualified as G
import Manifold.Json
import Manifold.Objects qualified as O
import Manifold.Runtime qualified as R

resources :: [O.Cube] -> (O.Cube -> String) -> String -> [(FilePath, String)]
resources definitions material callbacks = R.resources "objects" (functions definitions material callbacks) ++ [("data/manifold/advancement/object_interaction.json", render $ object [("criteria", object [("use", object [("trigger", string "minecraft:player_interacted_with_entity"), ("conditions", object [("entity", object [("type", string "minecraft:entity_properties"), ("entity", string "this"), ("predicate", object [("minecraft:entity_type", string "minecraft:interaction")])])])])]), ("rewards", object [("function", string "manifold:objects/interaction")])])]

axes :: [String]
axes = ["x", "y", "z"]

call :: String -> String
call name = R.call ("objects/" ++ name)

fields :: [String]
fields = ["id", "x", "y", "z", "gravity", "phase"]

bankFunctions :: Int -> R.Functions
bankFunctions count =
  [ ( "bank/start",
      [ "kill @e[tag=manifold.object.bank]",
        "data modify storage manifold:object_bank colors set value " ++ colors,
        "summon minecraft:item_display ~ ~ ~ {Tags:[\"manifold.object.bank\"],width:0f,height:0f,view_range:4f,billboard:\"fixed\",item:{id:\"minecraft:stone\",count:1,components:{\"minecraft:item_model\":\"manifold:object_bank\",\"minecraft:custom_model_data\":{colors:" ++ colors ++ "}}}}",
        R.set "r.bank_dirty" 1,
        R.set "ray.word.old" 0
      ]
    ),
    ("bank/publish", ["execute unless entity @e[tag=manifold.object.bank,limit=1] run return 0", "execute at @s run tp @e[tag=manifold.object.bank,limit=1] ~ ~ ~", R.when (R.test "r.bank_dirty" "0") "return 0", R.set "r.bank_dirty" 0, "scoreboard players add #r.revision manifold 1", R.op "r.revision" "%=" "pow16", "execute store result storage manifold:object_bank colors[" ++ show (count + 2) ++ "] int 1 run scoreboard players get #r.revision manifold", "data modify entity @e[type=minecraft:item_display,tag=manifold.object.bank,limit=1] item.components.\"minecraft:custom_model_data\".colors set from storage manifold:object_bank colors", "scoreboard players add #r.bank_publications manifold 1"]),
    ("cursor_zero", [R.set "ray.word" 0, call "cursor_encode"]),
    ("cursor_encode", [R.op "ray.word.old" "=" "ray.word", "execute store result storage manifold:object_bank colors[" ++ show (count) ++ "] int 1 run scoreboard players get #ray.word manifold", R.set "r.bank_dirty" 1])
  ]
  where
    colors = "[" ++ intercalate "," (replicate (count + 1) "0" ++ ["5392718", "0"]) ++ "]"

playerFunctions :: R.Functions
playerFunctions = [("player_clear", [R.op ("o.safe" ++ a) "=" ("o." ++ a) | a <- axes] ++ [R.op ("o." ++ a) "=" ("q." ++ a) | a <- axes] ++ [call "bounds", R.set "q.player_blocked" 0, R.when (unwords [R.cmp ("g." ++ a) ">" ("o.l" ++ a) ++ " " ++ R.cmp ("g." ++ a) "<" ("o.u" ++ a) | a <- axes]) (R.set "q.player_blocked" 1)] ++ [R.op ("o." ++ a) "=" ("o.safe" ++ a) | a <- axes])]

functions :: [O.Cube] -> (O.Cube -> String) -> String -> R.Functions
functions definitions material callbacks =
  bankFunctions (length definitions)
    ++ playerFunctions
    ++ [ ( "reach",
           [ call "reach/release",
             "execute store result score #o.reach.block manifold run attribute @s minecraft:block_interaction_range get " ++ show G.unit,
             "execute store result score #o.reach.entity manifold run attribute @s minecraft:entity_interaction_range get " ++ show G.unit,
             R.op "o.reach.block" "-=" "o.reach.entity",
             R.when (R.test "o.reach.block" "..0") "return 0",
             "execute store result storage manifold:interaction amount double 0.000244140625 run scoreboard players get #o.reach.block manifold",
             "data modify storage manifold:interaction amount_text set string storage manifold:interaction amount 0 -1",
             call "reach/apply with storage manifold:interaction"
           ]
         ),
         ("reach/apply", ["$attribute @s minecraft:entity_interaction_range modifier add manifold:cube_reach $(amount_text) add_value"]),
         ("reach/release", ["execute if entity @s[type=minecraft:player] if data entity @s attributes[{id:\"minecraft:entity_interaction_range\"}].modifiers[{id:\"manifold:cube_reach\"}] run attribute @s minecraft:entity_interaction_range modifier remove manifold:cube_reach"]),
         ("bucket", [R.op "q.bucket" "=" "q.z", R.op "q.bucket" "/=" "r.eight", R.op "q.bucket" "*=" "r.eight", R.op "q.tmp" "=" "q.y", R.op "q.tmp" "/=" "r.eight", R.op "q.bucket" "+=" "q.tmp", R.op "q.bucket" "*=" "r.eight", R.op "q.tmp" "=" "q.x", R.op "q.tmp" "/=" "r.eight", R.op "q.bucket" "+=" "q.tmp"]),
         ( "reset",
           [ "kill @e[tag=manifold.object.active]",
             "kill @e[tag=manifold.object.proxy]",
             "data modify storage manifold:runtime cubes set value [" ++ intercalate "," (map cubeNbt definitions) ++ "]",
             "data modify storage manifold:runtime cells set value {}",
             "data modify storage manifold:runtime bins set value [" ++ intercalate "," (replicate 512 "[]") ++ "]",
             "data modify storage manifold:runtime groups set value [[],[],[],[],[],[]]",
             "data modify storage manifold:runtime pending set value []",
             R.set "r.held" (-1),
             R.set "o.awake" 0,
             R.set "o.gravity" 0,
             R.set "r.object_dirty" 0
           ]
             ++ concat [["data modify storage manifold:runtime work set value {id:" ++ show (O.cubeId cube) ++ "}", call "load with storage manifold:runtime work", call "index", call "group with storage manifold:runtime work", call "encode"] | cube <- definitions]
         ),
         ("register", ["$data modify storage manifold:runtime cubes append value {id:$(id),x:$(x),y:$(y),z:$(z),gravity:$(gravity),phase:0,material:\"minecraft:quartz_block\"}", "$data modify storage manifold:runtime work set value {id:$(id)}", call "load with storage manifold:runtime work", call "index", call "group with storage manifold:runtime work"]),
         ("group", ["$data modify storage manifold:runtime groups[$(gravity)] append value {id:$(id)}"]),
         ("load", ["$data modify storage manifold:runtime current set from storage manifold:runtime cubes[$(id)]"] ++ [R.get ("o." ++ field) ("current." ++ field) | field <- fields] ++ ["data modify storage manifold:runtime work set from storage manifold:runtime current"]),
         ("save", [R.put ("current." ++ field) ("o." ++ field) | field <- fields] ++ [call "save_record with storage manifold:runtime work", call "encode", R.when (R.test "o.id" ("0.." ++ show (length definitions - 1))) (call "mark with storage manifold:runtime work")]),
         ("mark", ["$function manifold:" ++ callbacks ++ "/mark/$(id)"]),
         ("restore", ["data modify storage manifold:runtime restoring set from storage manifold:runtime cubes", "data modify storage manifold:runtime pending set value []", call "restore_loop", R.set "o.gravity.old" (-1), call "gravity"]),
         ("restore_loop", ["execute unless data storage manifold:runtime restoring[0] run return 0", "data modify storage manifold:runtime work set from storage manifold:runtime restoring[0]", "data remove storage manifold:runtime restoring[0]", call "load with storage manifold:runtime work", R.when (R.test "o.phase" "2") (R.set "o.phase" 0), call "save", call "restore_loop"]),
         ("save_record", ["$data modify storage manifold:runtime cubes[$(id)] set from storage manifold:runtime current"]),
         ("encode", [R.when (R.test "o.id" (show (length definitions) ++ "..")) "return 0", R.op "o.word" "=" "o.gravity", R.op "o.word" "*=" "r.four", R.op "o.word" "+=" "o.phase", R.op "o.word" "*=" "r.period", R.op "o.word" "+=" "o.z", R.op "o.word" "*=" "r.period", R.op "o.word" "+=" "o.y", R.op "o.word" "*=" "r.period", R.op "o.word" "+=" "o.x", R.put "work.word" "o.id", call "encode_word with storage manifold:runtime work"]),
         ("encode_word", ["$execute store result storage manifold:object_bank colors[$(word)] int 1 run scoreboard players get #o.word manifold", R.set "r.bank_dirty" 1]),
         ("coordinates", [R.op ("q." ++ a) "=" ("o." ++ a) | a <- axes] ++ [R.put ("work." ++ a) ("o." ++ a) | a <- axes] ++ [call "bucket", R.put "work.bucket" "q.bucket"]),
         ("index", [call "coordinates", call "index_record with storage manifold:runtime work"]),
         ("index_record", ["$data modify storage manifold:runtime cells.\"$(x)_$(y)_$(z)\" set value $(id)", "$data remove storage manifold:runtime bins[$(bucket)][{id:$(id)}]", "$data modify storage manifold:runtime bins[$(bucket)] append value {id:$(id)}"]),
         ("unindex", [call "coordinates", call "unindex_record with storage manifold:runtime work", call "neighbors"]),
         ("unindex_record", ["$data remove storage manifold:runtime cells.\"$(x)_$(y)_$(z)\"", "$data remove storage manifold:runtime bins[$(bucket)][{id:$(id)}]"]),
         ("cell", [R.put ("query." ++ a) ("q." ++ a) | a <- axes] ++ [R.set "q.object" (-1), call "cell_record with storage manifold:runtime query"]),
         ("cell_record", ["$execute if data storage manifold:runtime cells.\"$(x)_$(y)_$(z)\" store result score #q.object manifold run data get storage manifold:runtime cells.\"$(x)_$(y)_$(z)\""]),
         ("blocked", ["execute store result score #q.blocked manifold run function manifold:scene/cell", R.when (R.test "q.blocked" "1") "return 1", call "cell", R.when (R.test "q.object" "0..") "return 1", "return 0"]),
         ( "neighbors",
           concat
             [ [R.op ("q." ++ a) "=" ("o." ++ a) | a <- axes]
                 ++ [R.add ("q." ++ a) n | (a, n) <- zip axes (G.components direction), n /= 0]
                 ++ [R.op ("q." ++ a) "%=" "r.period" | a <- axes]
                 ++ [call "cell", R.when (R.test "q.object" "0..") (call "queue")]
             | direction <- G.downDirections
             ]
         ),
         ("queue", [R.put "queued.id" "q.object", "data modify storage manifold:runtime pending append from storage manifold:runtime queued"]),
         ("drain", ["execute unless data storage manifold:runtime pending[0] run return 0", "data modify storage manifold:runtime work set from storage manifold:runtime pending[0]", "data remove storage manifold:runtime pending[0]", call "load with storage manifold:runtime work", call "wake", call "drain"]),
         ( "target",
           [R.op ("q." ++ a) "=" ("o." ++ a) | a <- axes]
             ++ concat [[R.when (R.test "o.gravity" (show i)) (R.add ("q." ++ a) n) | (a, n) <- zip axes (G.components direction), n /= 0] | (i, direction) <- zip [0 :: Int ..] G.downDirections]
             ++ [R.op ("q." ++ a) "%=" "r.period" | a <- axes]
         ),
         ("wake", [R.when (R.test "o.phase" "1..") "return 0", R.when ("unless score #o.gravity manifold = #r.gravity manifold") "return 0", call "target", "execute store result score #q.blocked manifold run function manifold:objects/blocked", R.when (R.test "q.blocked" "1") "return 0", R.set "o.phase" 2, call "save", "summon minecraft:marker 0 200 0 {Tags:[\"manifold.object.active\",\"manifold.object.new\"]}", "scoreboard players operation @e[tag=manifold.object.new,limit=1] manifold = #o.id manifold", "tag @e[tag=manifold.object.new] remove manifold.object.new"]),
         ( "gravity",
           concat [[R.when (unwords [R.test ("g.d" ++ a) (show n) | (a, n) <- zip axes (G.components direction)]) (R.set "r.gravity" i)] | (i, direction) <- zip [0 :: Int ..] G.downDirections]
             ++ [R.when (R.cmp "r.gravity" "=" "o.gravity.old") "return 0", R.op "o.gravity.old" "=" "r.gravity", "execute as @e[tag=manifold.object.active] run function manifold:objects/freeze", call "wake_direction"]
         ),
         ("wake_direction", [R.put "wake.gravity" "r.gravity", call "wake_group with storage manifold:runtime wake", call "wake_group_loop"]),
         ("wake_group", ["$data modify storage manifold:runtime waking set from storage manifold:runtime groups[$(gravity)]"]),
         ("wake_group_loop", ["execute unless data storage manifold:runtime waking[0] run return 0", "data modify storage manifold:runtime work set from storage manifold:runtime waking[0]", "data remove storage manifold:runtime waking[0]", call "load with storage manifold:runtime work", call "wake", call "wake_group_loop"]),
         ("freeze", ["scoreboard players operation #o.id manifold = @s manifold", R.put "work.id" "o.id", call "load with storage manifold:runtime work", R.set "o.phase" 0, call "save", "kill @s"]),
         ("tick", [R.set "o.visits" 0, call "gravity", "execute as @e[tag=manifold.object.active] run function manifold:objects/step", "execute if data storage manifold:runtime pending[0] run function manifold:objects/drain", R.when (R.test "r.object_dirty" "1") (call "changed")]),
         ( "step",
           [ "scoreboard players add #o.visits manifold 1",
             "scoreboard players operation #o.id manifold = @s manifold",
             R.put "work.id" "o.id",
             call "load with storage manifold:runtime work",
             call "target",
             "execute store result score #q.blocked manifold run function manifold:objects/blocked",
             R.when (R.test "q.blocked" "1") ("return run " ++ call "freeze"),
             call "player_clear",
             R.when (R.test "q.player_blocked" "1") "return 0",
             "data modify storage manifold:runtime destination set value {}"
           ]
             ++ [R.put ("destination." ++ a) ("q." ++ a) | a <- axes]
             ++ [call "erase", call "unindex"]
             ++ [R.get ("o." ++ a) ("destination." ++ a) | a <- axes]
             ++ [call "index", call "save", call "project_both", R.set "r.object_dirty" 1]
         ),
         ("erase", ["execute as @e[tag=manifold.object.proxy] if score @s manifold = #o.id manifold run kill @s", "data modify storage manifold:runtime point.material set value \"minecraft:air\"", R.set "r.erasing" 1, call "project_both", R.set "r.erasing" 0]),
         ("project_both", [R.op "r.saved_target" "=" "r.target"] ++ concat [[R.set "r.target" slot, R.when (R.test ("h.cache" ++ show slot) "0..23") (call "project")] | slot <- [0, 1 :: Int]] ++ [R.op "r.target" "=" "r.saved_target"]),
         ( "project",
           [R.when (R.test "o.phase" "1" ++ " " ++ R.test "r.erasing" "0") "return 0"]
             ++ [R.op ("q." ++ a) "=" ("o." ++ a) | a <- axes]
             ++ [R.call "rooms/point", R.when (R.test "r.visible" "0") "return 0", R.when (R.test "r.erasing" "0") "data modify storage manifold:runtime point.material set from storage manifold:runtime current.material", R.call "rooms/block with storage manifold:runtime point", R.when (R.test "r.erasing" "1") "return 0", R.when ("unless score #r.target manifold = #h.slot manifold") "return 0", R.put "point.id" "o.id"]
             ++ concat [[R.op ("p." ++ a) "*=" "r.thousand", R.add ("p." ++ a) (if a == "y" then -30 else 500)] | a <- axes]
             ++ [R.call "rooms/entity_point", R.call "rooms/proxy with storage manifold:runtime point"]
         ),
         ("materialize", [R.set "r.projections" 0, "data modify storage manifold:runtime projection set value []"] ++ [R.when (R.test "r.target" (show slot)) (R.op "r.project_region" "=" ("r.region" ++ show slot)) | slot <- [0, 1 :: Int]] ++ [R.when (R.test "r.project_region" (show region)) (call ("projection/" ++ show region)) | region <- [0 .. 7 :: Int]] ++ [call "materialize_loop"]),
         ("materialize_loop", ["execute unless data storage manifold:runtime projection[0] run return 0", "scoreboard players add #r.projections manifold 1", "data modify storage manifold:runtime work set from storage manifold:runtime projection[0]", "data remove storage manifold:runtime projection[0]", call "load with storage manifold:runtime work", call "project", call "materialize_loop"]),
         ("activate", ["kill @e[tag=manifold.object.proxy]", R.op "r.target" "=" "h.slot", call "materialize", R.call "objects/reach"]),
         ("interaction", ["advancement revoke @s only manifold:object_interaction", R.when ("unless score #h.level manifold matches 2") "return 0", R.when ("unless score #h.mode manifold matches 1") "return 0", "execute as @e[type=minecraft:interaction,tag=manifold.object.proxy,distance=..7] if data entity @s interaction run function manifold:objects/click"]),
         ("click", ["scoreboard players operation #o.clicked manifold = @s manifold", "execute on target if entity @s[tag=manifold.pilot] at @s run function manifold:objects/use", "data remove entity @s interaction"]),
         ("use", [R.when (R.test "g.grounded" "0") "return 0", R.when (R.test "o.clicked" "-1") ("return run " ++ call "place"), R.when (R.test "r.held" "0..") "return 0", R.op "o.id" "=" "o.clicked", R.put "work.id" "o.id", call "load with storage manifold:runtime work", R.when ("unless score #o.gravity manifold = #r.gravity manifold") "return 0", R.when ("unless score #o.phase manifold matches 0") "return 0", call "take"]),
         ("take", [call "erase", call "unindex", R.set "o.phase" 1, R.op "r.held" "=" "o.id", call "save", R.set "r.object_dirty" 1, call "changed"]),
         ( "place",
           [R.when (R.test "r.held" "..-1") "return 0", R.when (R.test "r.preview" "0") "return 0", R.op "o.id" "=" "r.held", R.put "work.id" "o.id", call "load with storage manifold:runtime work"]
             ++ [R.get ("q." ++ a) ("preview." ++ a) | a <- axes]
             ++ ["execute store result score #q.blocked manifold run function manifold:objects/blocked", R.when (R.test "q.blocked" "1") "return 0", call "placement_clear", R.when (R.test "g.blocked" "1") "return 0"]
             ++ [R.op ("o." ++ a) "=" ("q." ++ a) | a <- axes]
             ++ [R.set "o.phase" 0, R.set "r.held" (-1), "kill @e[tag=manifold.object.cursor]", R.set "r.preview" 0, call "index", call "save", call "project_both", call "wake", R.set "r.object_dirty" 1, call "changed"]
         ),
         ("changed", [R.set "r.object_dirty" 0, R.call (callbacks ++ "/circuits"), "execute if data storage manifold:runtime pending[0] run function manifold:objects/drain", "execute as @a[tag=manifold.pilot,limit=1] at @s run function manifold:gravity/publish"]),
         ("near", [call "bucket", "data modify storage manifold:runtime query.items set value []", call "near_dispatch"]),
         ("inside", [call "near", call "inside_loop"]),
         ("inside_loop", ["execute unless data storage manifold:runtime query.items[0] run return 0", "data modify storage manifold:runtime work set from storage manifold:runtime query.items[0]", "data remove storage manifold:runtime query.items[0]", call "load with storage manifold:runtime work", call "bounds", R.when (unwords [R.cmp ("g." ++ a) ">" ("o.l" ++ a) ++ " " ++ R.cmp ("g." ++ a) "<" ("o.u" ++ a) | a <- axes]) (R.set "g.blocked" 1), call "inside_loop"]),
         ("bounds", concat [[R.op ("o.c" ++ a) "=" ("o." ++ a), R.op ("o.c" ++ a) "*=" "g.unit", R.op ("o.c" ++ a) "-=" ("g." ++ a), "scoreboard players add #o.c" ++ a ++ " manifold 131072", R.op ("o.c" ++ a) "%=" "g.period", "scoreboard players remove #o.c" ++ a ++ " manifold 131072", R.op ("o.c" ++ a) "+=" ("g." ++ a), R.op ("o.l" ++ a) "=" ("o.c" ++ a), R.add ("o.l" ++ a) (G.beamRadius - G.unit `div` 2), R.op ("o.l" ++ a) "-=" ("g.b" ++ a), R.op ("o.u" ++ a) "=" ("o.c" ++ a), R.add ("o.u" ++ a) (G.unit `div` 2 - G.beamRadius), R.op ("o.u" ++ a) "+=" ("g.b" ++ a)] | a <- axes]),
         ("placement_clear", [R.op ("o." ++ a) "=" ("q." ++ a) | a <- axes] ++ [call "bounds", R.set "g.blocked" 0, R.when (unwords [R.cmp ("g." ++ a) ">" ("o.l" ++ a) ++ " " ++ R.cmp ("g." ++ a) "<" ("o.u" ++ a) | a <- axes]) (R.set "g.blocked" 1)]),
         ( "cursor",
           [ R.set "r.preview" 0,
             R.when (R.test "r.held" "..-1") ("return run " ++ call "cursor_clear"),
             R.set "ray.steps" 0,
             "execute anchored eyes positioned ^ ^ ^0.25 run function manifold:objects/ray/step",
             R.when (R.test "r.preview" "0") (call "cursor_clear")
           ]
         ),
         ("cursor_clear", ["kill @e[tag=manifold.object.cursor]", R.when (R.test "ray.word.old" "1..") (call "cursor_zero")]),
         ("ray/step", ["execute unless block ~ ~ ~ minecraft:air run return run function manifold:objects/ray/hit", "tp @e[tag=manifold.object.ray,limit=1] ~ ~ ~", "scoreboard players add #ray.steps manifold 1", R.when (R.test "ray.steps" "..17") "execute positioned ^ ^ ^0.25 run function manifold:objects/ray/step"]),
         ( "ray/hit",
           [R.when (R.test "ray.steps" "0") "return 0"]
             ++ concat [["execute store result score #q." ++ a ++ " manifold run data get entity @e[tag=manifold.object.ray,limit=1] Pos[" ++ show i ++ "]", R.op ("p." ++ a) "=" ("q." ++ a), R.op ("p." ++ a) "*=" "r.thousand", R.add ("p." ++ a) (if a == "y" then -30 else 500)] | (i, a) <- zip [0 :: Int ..] axes]
             ++ [R.call "rooms/entity_point", R.call "rooms/cell"]
             ++ [R.put ("preview." ++ a) ("q." ++ a) | a <- axes]
             ++ [R.set "r.preview" 1, call "cursor_move with storage manifold:runtime point", R.op "ray.word" "=" "q.z", R.op "ray.word" "*=" "r.period", R.op "ray.word" "+=" "q.y", R.op "ray.word" "*=" "r.period", R.op "ray.word" "+=" "q.x", "scoreboard players add #ray.word manifold 262144", R.when ("unless score #ray.word manifold = #ray.word.old manifold") (call "cursor_encode")]
         ),
         ("cursor_move", ["$execute unless entity @e[tag=manifold.object.cursor,limit=1] run summon minecraft:interaction $(px) $(py) $(pz) {Tags:[\"manifold.object.proxy\",\"manifold.object.cursor\"],width:1.06f,height:1.06f,response:1b}", "scoreboard players set @e[tag=manifold.object.cursor] manifold -1", "$tp @e[tag=manifold.object.cursor,limit=1] $(px) $(py) $(pz)"])
       ]
    ++ R.dispatch "objects" "near_dispatch" "q.bucket" [(i, "objects/near/" ++ show i) | i <- [0 .. 511 :: Int]]
    ++ [("near/" ++ show (x + 8 * y + 64 * z), ["data modify storage manifold:runtime query.items append from storage manifold:runtime bins[" ++ show (((x + dx) `mod` 8) + 8 * ((y + dy) `mod` 8) + 64 * ((z + dz) `mod` 8)) ++ "][]" | dx <- [-1 .. 1], dy <- [-1 .. 1], dz <- [-1 .. 1]]) | x <- [0 .. 7 :: Int], y <- [0 .. 7], z <- [0 .. 7]]
    ++ [("projection/" ++ show (rx + 2 * ry + 4 * rz), ["data modify storage manifold:runtime projection append from storage manifold:runtime bins[" ++ show (x `mod` 8 + 8 * (y `mod` 8) + 64 * (z `mod` 8)) ++ "][]" | x <- [rx * 4 - 1 .. rx * 4 + 4], y <- [ry * 4 - 1 .. ry * 4 + 4], z <- [rz * 4 - 1 .. rz * 4 + 4]]) | rx <- [0, 1 :: Int], ry <- [0, 1], rz <- [0, 1]]
    ++ [("clip/" ++ axis, [call "near", call ("clip_loop/" ++ axis)]) | axis <- axes]
    ++ [("clip_loop/" ++ axis, ["execute unless data storage manifold:runtime query.items[0] run return 0", "data modify storage manifold:runtime work set from storage manifold:runtime query.items[0]", "data remove storage manifold:runtime query.items[0]", call "load with storage manifold:runtime work", call "bounds", R.op "o.distance" "=" ("o.l" ++ axis), R.op "o.distance" "-=" ("g." ++ axis), R.when (orthogonal axis ++ " " ++ R.test "g.step" "1.." ++ " " ++ R.cmp ("g." ++ axis) "<=" ("o.l" ++ axis)) (R.op "g.step" "<" "o.distance"), R.op "o.distance" "=" ("o.u" ++ axis), R.op "o.distance" "-=" ("g." ++ axis), R.when (orthogonal axis ++ " " ++ R.test "g.step" "..-1" ++ " " ++ R.cmp ("g." ++ axis) ">=" ("o.u" ++ axis)) (R.op "g.step" ">" "o.distance"), call ("clip_loop/" ++ axis)]) | axis <- axes]
  where
    orthogonal axis = unwords [R.cmp ("g." ++ a) ">" ("o.l" ++ a) ++ " " ++ R.cmp ("g." ++ a) "<" ("o.u" ++ a) | a <- axes, a /= axis]
    cubeNbt cube = "{id:" ++ show (O.cubeId cube) ++ ",x:" ++ show (G.component 0 (O.cubeCell cube)) ++ ",y:" ++ show (G.component 1 (O.cubeCell cube)) ++ ",z:" ++ show (G.component 2 (O.cubeCell cube)) ++ ",gravity:" ++ show (sum [i | (i, g) <- zip [0 :: Int ..] G.downDirections, g == O.cubeGravity cube]) ++ ",phase:0,material:\"" ++ material cube ++ "\"}"
