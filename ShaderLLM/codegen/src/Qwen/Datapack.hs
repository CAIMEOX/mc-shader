{-# LANGUAGE OverloadedStrings #-}

module Qwen.Datapack (compileDatapack) where

import Data.Aeson (encode)
import Data.ByteString.Lazy qualified as B
import Data.Char (chr)
import Data.Text qualified as T
import Data.Text.Encoding qualified as T
import Numeric (showHex)
import Qwen.Limits (maxGeneration)
import System.Directory (createDirectoryIfMissing)
import System.FilePath (takeDirectory, (</>))

compileDatapack :: FilePath -> IO ()
compileDatapack output = do
  let write path body = do createDirectoryIfMissing True (takeDirectory (output </> path)); writeFile (output </> path) body
      function name commands = write ("data/qwen/function/" ++ name ++ ".mcfunction") (unlines commands)
      json s = T.unpack (T.decodeUtf8 (B.toStrict (encode s)))
      color i = "#" ++ replicate (4 - length h) '0' ++ h ++ "00" where h = showHex i ""
  write "pack.mcmeta" "{\"pack\":{\"description\":\"Qwen3 shader inference\",\"min_format\":[121,0],\"max_format\":[121,0]}}"
  write "data/minecraft/tags/function/load.json" "{\"values\":[\"qwen:load\"]}"
  write "data/minecraft/tags/function/tick.json" "{\"values\":[\"qwen:tick\"]}"
  function
    "load"
    [ "scoreboard objectives add qwen dummy",
      "scoreboard objectives add qwen.action trigger",
      "scoreboard players set #mod qwen 256",
      "execute unless data storage qwen:input prompt run data modify storage qwen:input prompt set value \"What is 2 + 2? Answer briefly.\"",
      "execute unless data storage qwen:input max_tokens run data modify storage qwen:input max_tokens set value " ++ show maxGeneration ++ "",
      "data modify storage qwen:tx colors set value " ++ json [color i | i <- [0 :: Int .. maxGeneration]]
    ]
  function
    "tick"
    [ "execute as @a[scores={qwen.action=1..}] at @s run function qwen:submit",
      "scoreboard players set @a[scores={qwen.action=1..}] qwen.action 0",
      "scoreboard players enable @a qwen.action",
      "execute at @a run tp @e[type=minecraft:text_display,tag=qwen.carrier,limit=1] ~ ~2 ~"
    ]
  function
    "submit"
    [ "execute store result score #length qwen run data get storage qwen:input prompt",
      "execute if score #length qwen matches 129.. run tellraw @s {text:\"Qwen: prompt limit is 128 BMP characters.\",color:\"red\"}",
      "execute if score #length qwen matches 129.. run return 0",
      "kill @e[tag=qwen.carrier]",
      "summon minecraft:text_display ~ ~2 ~ {Tags:[\"qwen.carrier\"],text:{text:\"\"},width:0f,height:0f,view_range:8f,background:0,see_through:true,shadow:false,line_width:100000}",
      "scoreboard players add #epoch qwen 1",
      "scoreboard players operation #epoch qwen %= #mod qwen",
      "execute store result storage qwen:tx epoch int 1 run scoreboard players get #epoch qwen",
      "execute store result storage qwen:tx length int 1 run scoreboard players get #length qwen",
      "execute store result score #limit qwen run data get storage qwen:input max_tokens",
      "execute if score #limit qwen matches ..0 run scoreboard players set #limit qwen 1",
      "execute if score #limit qwen matches " ++ show (maxGeneration + 1) ++ ".. run scoreboard players set #limit qwen " ++ show maxGeneration ++ "",
      "execute store result storage qwen:tx max_tokens int 1 run scoreboard players get #limit qwen",
      "data modify storage qwen:tx component set value {text:\"\",font:\"qwen:wire\",extra:[]}",
      "function qwen:headers with storage qwen:tx",
      "scoreboard players set #i qwen 0",
      "execute if score #length qwen matches 1.. run function qwen:loop",
      "data modify entity @e[type=minecraft:text_display,tag=qwen.carrier,limit=1] text set from storage qwen:tx component"
    ]
  function
    "headers"
    [ "data modify storage qwen:tx part set value {text:" ++ json ([chr 0xe100] :: String) ++ ",color:\"#000000\"}",
      "$data modify storage qwen:tx part.color set from storage qwen:tx colors[$(epoch)]",
      "data modify storage qwen:tx component.extra append from storage qwen:tx part",
      "data modify storage qwen:tx part.text set value " ++ json ([chr 0xe101] :: String),
      "$data modify storage qwen:tx part.color set from storage qwen:tx colors[$(length)]",
      "data modify storage qwen:tx component.extra append from storage qwen:tx part",
      "data modify storage qwen:tx part.text set value " ++ json ([chr 0xe102] :: String),
      "$data modify storage qwen:tx part.color set from storage qwen:tx colors[$(max_tokens)]",
      "data modify storage qwen:tx component.extra append from storage qwen:tx part"
    ]
  function
    "loop"
    [ "execute store result storage qwen:tx i int 1 run scoreboard players get #i qwen",
      "scoreboard players operation #end qwen = #i qwen",
      "scoreboard players add #end qwen 1",
      "execute store result storage qwen:tx end int 1 run scoreboard players get #end qwen",
      "function qwen:character with storage qwen:tx",
      "scoreboard players add #i qwen 1",
      "execute if score #i qwen < #length qwen run function qwen:loop"
    ]
  function "character" $
    [ "data modify storage qwen:tx part set value {text:\"\",color:\"#000000\"}",
      "$data modify storage qwen:tx part.text set string storage qwen:input prompt $(i) $(end)",
      "$data modify storage qwen:tx part.color set from storage qwen:tx colors[$(i)]"
    ]
      ++ ["execute if data storage qwen:tx {part:{text:" ++ json ([chr c] :: String) ++ "}} run data modify storage qwen:tx part.text set value " ++ json ([chr (0xe000 + c)] :: String) | c <- [0 .. 31]]
      ++ ["data modify storage qwen:tx component.extra append from storage qwen:tx part"]
