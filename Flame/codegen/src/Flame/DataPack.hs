module Flame.DataPack (dataPack) where

import Flame.Domain
import Flame.Json
import Flame.Protocol

type Asset = (FilePath, String)

blockMatch :: [(String, Json)] -> Int -> Json
blockMatch fields value = object [("condition", object (("type", string "minecraft:match_block") : fields)), ("value", int value)]

shapeProvider :: Json
shapeProvider = object [("type", string "minecraft:number_dispatcher"), ("cases", array rules), ("default", int unknownShape)]
  where
    match blocks props value = blockMatch ([("blocks", blocks)] ++ [("state", object [(k, string v) | (k, v) <- props]) | not (null props)]) value
    names = array . map (string . ("minecraft:" ++))
    rules =
      [ match (names ["air", "cave_air", "void_air", "fire", "soul_fire"]) [] 0,
        match (string "#minecraft:slabs") [("type", "double")] 1,
        match (string "#minecraft:slabs") [("type", "bottom")] 2,
        match (string "#minecraft:slabs") [("type", "top")] 3
      ]
        ++ [match (string "#minecraft:stairs") [("half", halfName h), ("facing", facingName f), ("shape", turnName turn)] (shapeId (stairMask stair)) | stair@(Stair h f turn) <- stairs]
        ++ [match (string tag) [] 1 | tag <- ["#minecraft:logs", "#minecraft:planks", "#minecraft:leaves", "#minecraft:wool"]]
        ++ [match (names ["stone", "dirt", "grass_block", "andesite", "polished_andesite", "smooth_stone", "stone_bricks", "cobblestone", "deepslate", "white_concrete", "light_gray_concrete", "gray_concrete", "black_concrete", "sea_lantern", "glass", "sand", "sandstone", "quartz_block", "iron_block", "bedrock"]) [] 1]

materialProvider :: Json
materialProvider = object [("type", string "minecraft:number_dispatcher"), ("cases", array rules), ("default", int (0 :: Int))]
  where
    rules =
      [blockMatch [("state", object [("waterlogged", string "true")])] 0]
        ++ [ blockMatch [("blocks", string tag)] (fromEnum m)
           | (m, tags) <-
               [ (Wood, ["#minecraft:logs", "#minecraft:planks", "#minecraft:wooden_stairs", "#minecraft:wooden_slabs"]),
                 (Foliage, ["#minecraft:leaves"]),
                 (Cloth, ["#minecraft:wool", "#minecraft:wool_stairs", "#minecraft:wool_slabs"])
               ],
             tag <- tags
           ]

terrainCommands :: Config -> [[String]]
terrainCommands c = [sample i p | (i, p) <- zip [0 ..] (coordinates (region c))]
  where
    sample i (V3 x y z) =
      [ setScore "cell" (fromIntegral unknownShape),
        setScore "material" 0,
        "execute if loaded " ++ position ++ " store result score " ++ score "cell" ++ " run compute block " ++ position ++ " integer flame:shape",
        "execute if loaded " ++ position ++ " store result score " ++ score "material" ++ " run compute block " ++ position ++ " integer flame:material",
        operation "material" "*=" "pow5",
        operation "cell" "+=" "material"
      ]
        ++ concatMap (fragment i) (pieces (i * 7) 7)
      where
        position = unwords (map (('~' :) . show) [x, y, z])
    fragment cell p =
      pieceCommands "cell" "word" p
        ++ if wordShift p + pieceWidth p == 24 || (cell == volume (region c) - 1 && valueShift p + pieceWidth p == 7)
          then
            [ "execute store result storage flame:tx word int 1 run scoreboard players get " ++ score "word",
              "data modify storage flame:tx colors append from storage flame:tx word",
              setScore "word" 0
            ]
          else []

dataPack :: Config -> [Asset]
dataPack c =
  [("data/flame/function/" ++ name ++ ".mcfunction", unlines commands) | (name, commands) <- functions]
    ++ [ ("data/flame/context_int_provider/shape.json", render shapeProvider),
         ("data/flame/context_int_provider/material.json", render materialProvider),
         ("data/minecraft/tags/function/load.json", render (object [("values", array [string "flame:load"])])),
         ("data/minecraft/tags/function/tick.json", render (object [("values", array [string "flame:tick"])]))
       ]
  where
    carrier = "@e[type=minecraft:item_display,tag=flame.carrier,limit=1]"
    marker = "@e[type=minecraft:marker,tag=flame.ignition,limit=1]"
    carrierNbt = "{Tags:[\"flame.carrier\"],width:0f,height:0f,view_range:4f,billboard:\"fixed\",item:{id:\"minecraft:stone\",count:1,components:{\"minecraft:item_model\":\"flame:carrier\",\"minecraft:custom_model_data\":{colors:" ++ render (array (replicate (dataWords c) (int (0 :: Int)))) ++ "}}}}"
    batches = chunks 256 (terrainCommands c)
    scans =
      concat
        [ [ ("scan/" ++ show i, ["execute at " ++ carrier ++ " run function flame:scan/body_" ++ show i]),
            ("scan/body_" ++ show i, concat body ++ if i == length batches - 1 then ["function flame:publish"] else ["schedule function flame:scan/" ++ show (i + 1) ++ " 1t replace"])
          ]
        | (i, body) <- zip [0 ..] batches
        ]
    encodeHeader =
      [setScore ("head" ++ show i) 0 | i <- [0 .. headerWords - 1]]
        ++ concat
          [ [operation "value" "=" (fieldName f)]
              ++ ["scoreboard players add " ++ score "value" ++ " " ++ show (fieldBias f) | fieldBias f /= 0]
              ++ concatMap (\p -> pieceCommands "value" ("head" ++ show (wordIndex p)) p) (pieces offset (fieldWidth f))
          | (offset, f) <- fieldOffsets header
          ]
        ++ ["execute store result storage flame:tx colors[" ++ show i ++ "] int 1 run scoreboard players get " ++ score ("head" ++ show i) | i <- [0 .. headerWords - 1]]
    sourceDefault = linear (grid c) (V3 7 3 17)
    V3 nx ny nz = grid c
    functions =
      [ ( "load",
          ["scoreboard objectives add flame dummy", "scoreboard objectives add flame.action trigger"]
            ++ constantCommands
            ++ [setScore "power" 128, setScore "mode" 0, setScore "ready" 0, setScore "nx" (fromIntegral nx), setScore "ny" (fromIntegral ny)]
        ),
        ("tick", ["execute as @a[scores={flame.action=1..}] at @s run function flame:controls", "scoreboard players enable @a flame.action"]),
        ("controls", ["execute if score @s flame.action matches 1 run function flame:input/ignite", "execute if score @s flame.action matches 2 run function flame:quench", "execute if score @s flame.action matches 3 run function flame:rescan", "scoreboard players set @s flame.action 0"]),
        ( "start",
          ["kill @e[tag=flame.carrier]", "execute align xyz run summon minecraft:item_display ~ ~ ~ " ++ carrierNbt]
            ++ ["execute store result score " ++ score ("origin." ++ axis) ++ " run data get entity " ++ carrier ++ " Pos[" ++ show i ++ "]" | (i, axis) <- zip [0 :: Int ..] ["x", "y", "z"]]
            ++ [setScore "source" (fromIntegral sourceDefault), setScore "mode" 1, "function flame:rescan"]
        ),
        ( "rescan",
          ["schedule clear flame:scan/" ++ show i | i <- [1 .. length batches - 1]]
            ++ [setScore "ready" 0, setScore "word" 0, "data modify storage flame:tx colors set value " ++ render (array (replicate headerWords (int (0 :: Int)))), "function flame:scan/0"]
        ),
        ("publish", ["scoreboard players add " ++ score "epoch" ++ " 1", "execute if score " ++ score "epoch" ++ " matches 16777216.. run " ++ setScore "epoch" 1, setScore "ready" 1, "function flame:send"]),
        ("send", encodeHeader ++ ["data modify entity " ++ carrier ++ " item.components.\"minecraft:custom_model_data\".colors set from storage flame:tx colors"]),
        ("source/on", [setScore "mode" 1, "execute if score " ++ score "ready" ++ " matches 1 run function flame:send"]),
        ("source/off", [setScore "mode" 0, "execute if score " ++ score "ready" ++ " matches 1 run function flame:send"]),
        ("quench", [setScore "mode" 2, "execute if score " ++ score "ready" ++ " matches 1 run function flame:send"]),
        ("reset", ["execute if score " ++ score "ready" ++ " matches 1 run function flame:publish"]),
        ("input/ignite", [setScore "ray" 0, "execute anchored eyes positioned ^ ^ ^ anchored feet run function flame:input/ray"]),
        ( "input/ray",
          [ "execute unless block ~ ~ ~ #minecraft:air run return run function flame:ignite",
            "scoreboard players add " ++ score "ray" ++ " 1",
            "execute if score " ++ score "ray" ++ " matches ..64 positioned ^ ^ ^0.25 run function flame:input/ray"
          ]
        ),
        ( "ignite",
          ["execute unless score " ++ score "ready" ++ " matches 1 run return 0", "kill @e[tag=flame.ignition]", "execute align xyz run summon minecraft:marker ~ ~ ~ {Tags:[\"flame.ignition\"]}"]
            ++ concat [["execute store result score " ++ score ("s" ++ axis) ++ " run data get entity " ++ marker ++ " Pos[" ++ show i ++ "]", operation ("s" ++ axis) "-=" ("origin." ++ axis), operation ("s" ++ axis) "*=" "pow1", "scoreboard players add " ++ score ("s" ++ axis) ++ " 1"] | (i, axis) <- zip [0 :: Int ..] ["x", "y", "z"]]
            ++ ["kill @e[tag=flame.ignition]"]
            ++ ["execute unless score " ++ score axis ++ " matches 0.." ++ show (n - 1) ++ " run return 0" | (axis, n) <- [("sx", nx), ("sy", ny), ("sz", nz)]]
            ++ [operation "source" "=" "sz", operation "source" "*=" "ny", operation "source" "+=" "sy", operation "source" "*=" "nx", operation "source" "+=" "sx", "function flame:source/on"]
        ),
        ("demo", demo ++ ["execute positioned 0 64 0 run function flame:start"])
      ]
        ++ scans
    demo =
      [ "fill 0 64 0 15 71 15 minecraft:air strict",
        "fill 0 64 0 15 64 15 minecraft:polished_andesite strict",
        "fill 2 65 7 8 65 9 minecraft:oak_planks strict",
        "fill 7 66 7 8 66 8 minecraft:oak_leaves[persistent=true] strict",
        "setblock 5 66 8 minecraft:oak_slab[type=bottom] strict",
        "setblock 6 66 8 minecraft:oak_stairs[facing=west] strict",
        "fill 10 65 5 10 70 11 minecraft:stone_bricks strict",
        "fill 12 65 7 13 65 9 minecraft:white_wool strict",
        "fill 4 69 6 8 69 10 minecraft:smooth_stone strict"
      ]

chunks :: Int -> [a] -> [[a]]
chunks _ [] = []
chunks n xs = let (a, b) = splitAt n xs in a : chunks n b
