module Signal.Water (assets, meanGap, fitModel, receive, Model (..), windowSeconds, clusterMedian, fitFour, receiveFour) where

import Data.Bits (shiftR, xor)
import Signal.Json

windowSeconds :: Double
windowSeconds = 1.5

data Model = Model {threshold :: Int, highBit :: Int} deriving (Eq, Show)

meanGap :: [Int] -> Maybe Int
meanGap (first : _ : _ : fourth : rest) =
  Just ((foldl (flip const) fourth rest - first) * 1000 `div` (3 + length rest))
meanGap _ = Nothing

clusterMedian :: [Int] -> Maybe Int
clusterMedian [] = Nothing
clusterMedian (first : rest) =
  case reverse (zipWith (-) (drop 1 starts) starts) of
    a : b : c : _ -> Just ((a + b + c - minimum [a, b, c] - maximum [a, b, c]) * 1000)
    _ -> Nothing
  where
    starts = reverse (snd (foldl add (first, [first]) rest))
    add (previous, groups) t = (t, if t - previous < 20 then groups else t : groups)

fitModel :: [Int] -> [Int] -> Maybe Model
fitModel light heavy
  | null light || null heavy || abs (center1 - center0) < 5000 = Nothing
  | otherwise = Just (Model ((center0 + center1) `div` 2) (if center1 > center0 then 1 else 0))
  where
    center0 = sum light `div` length light
    center1 = sum heavy `div` length heavy

receive :: Model -> Int -> Int
receive model value = if value > threshold model then highBit model else 1 - highBit model

fitFour :: [[Int]] -> Maybe ([Int], [Int])
fitFour classes
  | length classes /= 4 || any null classes = Nothing
  | any (< 5000) (zipWith (-) (drop 1 centers) centers) = Nothing
  | otherwise = Just (centers, zipWith (\a b -> (a + b) `div` 2) centers (drop 1 centers))
  where
    centers = map (\values -> sum values `div` length values) classes

receiveFour :: [Int] -> Int -> Maybe Int
receiveFour cuts value
  | length cuts /= 3 || not (and (zipWith (<) cuts (drop 1 cuts))) = Nothing
  | otherwise = Just (level `xor` shiftR level 1)
  where
    level = length (filter (value >) cuts)

assets :: [(FilePath, String)]
assets =
  [("data/signal/function/water/" ++ name ++ ".mcfunction", unlines body) | (name, body) <- functions]
    ++ [ ( "data/signal/predicate/water/moving.json",
           render $
             object
               [ ("type", string "minecraft:entity_properties"),
                 ("entity", string "this"),
                 ("predicate", object [("minecraft:movement", object [("horizontal_speed", object [("min", number 0.001)])])])
               ]
         )
       ]
  where
    score name = "#water_" ++ name ++ " signal"
    set name value = "scoreboard players set " ++ score name ++ " " ++ show (value :: Int)
    op dst operator src = "scoreboard players operation " ++ score dst ++ " " ++ operator ++ " " ++ score src
    store path name = "execute store result storage signal:water " ++ path ++ " int 1 run scoreboard players get " ++ score name
    player = "@a[tag=signal.probe,limit=1]"
    functions =
      [ ( "load",
          [ "scoreboard objectives add signal.rx dummy",
            "stopwatch create signal:water/window",
            set "collect" 0,
            set "scale" 1000,
            set "duration" 1500,
            set "stat" 0,
            set "alphabet" 2,
            set "negative" (-1),
            "schedule clear signal:water/poll"
          ]
        ),
        ( "stage",
          [ "fill -2 63 -2 10 67 2 minecraft:air strict",
            "fill -1 63 -1 9 63 1 minecraft:polished_andesite strict",
            "fill -1 64 -1 9 65 -1 minecraft:glass strict",
            "fill -1 64 1 9 65 1 minecraft:glass strict",
            "fill -1 64 0 -1 65 0 minecraft:glass strict",
            "fill 9 64 0 9 65 0 minecraft:glass strict"
          ]
            ++ ["setblock " ++ show x ++ " 64 0 minecraft:water[level=" ++ show x ++ "]" | x <- [0 .. 7 :: Int]]
        ),
        ( "reset",
          [ set "collect" 0,
            "schedule clear signal:water/poll",
            "gamemode adventure " ++ player,
            "tp " ++ player ++ " 0.5 64 0.5 -90 15"
          ]
        ),
        ( "start",
          [ "data modify storage signal:water events set value []",
            "stopwatch restart signal:water/window",
            "scoreboard players set " ++ player ++ " signal.rx -1",
            set "polls" 0,
            set "moving_polls" 0,
            set "events" 0,
            set "groups" 0,
            set "group_intervals" 0,
            set "g1" 0,
            set "g2" 0,
            set "g3" 0,
            set "intervals" 0,
            set "gap_sum" 0,
            set "valid" 0,
            "execute as " ++ player ++ " store result score " ++ score "x" ++ " run data get entity @s Pos[0] 1000000",
            op "last_x" "=" "x",
            "execute store result score " ++ score "last_change" ++ " run stopwatch query signal:clock 1000",
            set "collect" 1,
            "schedule function signal:water/poll 1t replace"
          ]
        ),
        ( "poll",
          [ "execute unless score " ++ score "collect" ++ " matches 1 run return 0",
            "execute store result score " ++ score "elapsed" ++ " run stopwatch query signal:water/window 1000",
            "execute if score " ++ score "elapsed" ++ " >= " ++ score "duration" ++ " run return run function signal:water/stop",
            "execute as " ++ player ++ " at @s run function signal:water/sample",
            "schedule function signal:water/poll 1t replace"
          ]
        ),
        ( "sample",
          [ "scoreboard players add " ++ score "polls" ++ " 1",
            "execute store success score " ++ score "moving" ++ " if predicate signal:water/moving",
            op "moving_polls" "+=" "moving",
            "execute store result score " ++ score "x" ++ " run data get entity @s Pos[0] 1000000",
            "execute store result score " ++ score "now" ++ " run stopwatch query signal:clock 1000",
            op "dx" "=" "x",
            op "dx" "-=" "last_x",
            "execute unless score " ++ score "dx" ++ " matches 0 run function signal:water/change"
          ]
        ),
        ( "change",
          [ op "gap" "=" "now",
            op "gap" "-=" "last_change",
            "function signal:water/cluster",
            "execute if score " ++ score "events" ++ " matches 1.. run " ++ op "gap_sum" "+=" "gap",
            "execute if score " ++ score "events" ++ " matches 1.. run scoreboard players add " ++ score "intervals" ++ " 1",
            "scoreboard players add " ++ score "events" ++ " 1",
            store "event.time_ms" "now",
            store "event.gap_ms" "gap",
            store "event.dx_microblocks" "dx",
            store "event.x_microblocks" "x",
            store "event.moving" "moving",
            "data modify storage signal:water events append from storage signal:water event",
            op "last_x" "=" "x",
            op "last_change" "=" "now"
          ]
        ),
        ( "cluster",
          [ "execute if score " ++ score "groups" ++ " matches 0 run return run function signal:water/new_group",
            "execute unless score " ++ score "gap" ++ " matches ..19 run function signal:water/new_group"
          ]
        ),
        ( "new_group",
          [ "execute if score " ++ score "groups" ++ " matches 1.. run function signal:water/group_gap",
            op "group_last" "=" "now",
            "scoreboard players add " ++ score "groups" ++ " 1"
          ]
        ),
        ( "group_gap",
          [ op "group_delta" "=" "now",
            op "group_delta" "-=" "group_last",
            op "g3" "=" "g2",
            op "g2" "=" "g1",
            op "g1" "=" "group_delta",
            "scoreboard players add " ++ score "group_intervals" ++ " 1"
          ]
        ),
        ("stop", [set "collect" 0, "function signal:water/feature", "function signal:water/decode"]),
        ( "feature",
          [ set "valid" 0,
            set "value" 0,
            "execute if score " ++ score "stat" ++ " matches 1 run return run function signal:water/median",
            "execute unless score " ++ score "intervals" ++ " matches 3.. run return 0",
            op "value" "=" "gap_sum",
            op "value" "*=" "scale",
            op "value" "/=" "intervals",
            set "valid" 1
          ]
        ),
        ( "median",
          [ "execute unless score " ++ score "group_intervals" ++ " matches 3.. run return 0",
            op "minimum" "=" "g1",
            op "minimum" "<" "g2",
            op "minimum" "<" "g3",
            op "maximum" "=" "g1",
            op "maximum" ">" "g2",
            op "maximum" ">" "g3",
            op "value" "=" "g1",
            op "value" "+=" "g2",
            op "value" "+=" "g3",
            op "value" "-=" "minimum",
            op "value" "-=" "maximum",
            op "value" "*=" "scale",
            set "valid" 1
          ]
        ),
        ( "training/reset",
          [ set "sum0" 0,
            set "sum1" 0,
            set "count0" 0,
            set "count1" 0,
            set "ready" 0,
            set "alphabet" 2
          ]
        ),
        ( "training/zero",
          [ "execute unless score " ++ score "valid" ++ " matches 1 run return 0",
            op "sum0" "+=" "value",
            "scoreboard players add " ++ score "count0" ++ " 1"
          ]
        ),
        ( "training/one",
          [ "execute unless score " ++ score "valid" ++ " matches 1 run return 0",
            op "sum1" "+=" "value",
            "scoreboard players add " ++ score "count1" ++ " 1"
          ]
        ),
        ( "model",
          [ set "ready" 0,
            "execute unless score " ++ score "count0" ++ " matches 1.. run return 0",
            "execute unless score " ++ score "count1" ++ " matches 1.. run return 0",
            op "center0" "=" "sum0",
            op "center0" "/=" "count0",
            op "center1" "=" "sum1",
            op "center1" "/=" "count1",
            op "separation" "=" "center1",
            op "separation" "-=" "center0",
            "execute if score " ++ score "separation" ++ " matches ..-1 run " ++ op "separation" "*=" "negative",
            "execute unless score " ++ score "separation" ++ " matches 5000.. run return 0",
            op "threshold" "=" "center0",
            op "threshold" "+=" "center1",
            set "two" 2,
            op "threshold" "/=" "two",
            set "high_bit" 0,
            "execute if score " ++ score "center1" ++ " > " ++ score "center0" ++ " run " ++ set "high_bit" 1,
            set "low_bit" 1,
            op "low_bit" "-=" "high_bit",
            set "ready" 1
          ]
        ),
        ( "decode",
          [ set "decoded" (-1),
            "scoreboard players set " ++ player ++ " signal.rx -1",
            "execute unless score " ++ score "valid" ++ " matches 1 run return 0",
            "execute unless score " ++ score "ready" ++ " matches 1 run return 0",
            "execute if score " ++ score "alphabet" ++ " matches 4 run return run function signal:water/four/decode",
            op "decoded" "=" "low_bit",
            "execute if score " ++ score "value" ++ " > " ++ score "threshold" ++ " run " ++ op "decoded" "=" "high_bit",
            "scoreboard players operation " ++ player ++ " signal.rx = " ++ score "decoded"
          ]
        )
      ]
        ++ fourFunctions
    levelName stem i = stem ++ show (i :: Int)
    fourFunctions =
      [("four/training/reset", [set "ready" 0, set "alphabet" 4] ++ [set (levelName stem i) 0 | i <- [0 .. 3], stem <- ["sum_", "count_"]])]
        ++ [ ( "four/training/" ++ show i,
               [ "execute unless score " ++ score "valid" ++ " matches 1 run return 0",
                 op (levelName "sum_" i) "+=" "value",
                 "scoreboard players add " ++ score (levelName "count_" i) ++ " 1"
               ]
             )
           | i <- [0 .. 3]
           ]
        ++ [ ( "four/model",
               [set "ready" 0, set "two" 2]
                 ++ ["execute unless score " ++ score (levelName "count_" i) ++ " matches 1.. run return 0" | i <- [0 .. 3]]
                 ++ concat
                   [ [ op (levelName "c" i) "=" (levelName "sum_" i),
                       op (levelName "c" i) "/=" (levelName "count_" i)
                     ]
                   | i <- [0 .. 3]
                   ]
                 ++ concat
                   [ [ op "separation" "=" (levelName "c" (i + 1)),
                       op "separation" "-=" (levelName "c" i),
                       "execute unless score " ++ score "separation" ++ " matches 5000.. run return 0",
                       op (levelName "cut" i) "=" (levelName "c" i),
                       op (levelName "cut" i) "+=" (levelName "c" (i + 1)),
                       op (levelName "cut" i) "/=" "two"
                     ]
                   | i <- [0 .. 2]
                   ]
                 ++ [set "ready" 1]
             ),
             ( "four/decode",
               [set "level" 0]
                 ++ ["execute if score " ++ score "value" ++ " > " ++ score (levelName "cut" i) ++ " run " ++ set "level" (i + 1) | i <- [0 .. 2]]
                 ++ ["execute if score " ++ score "level" ++ " matches " ++ show i ++ " run " ++ set "decoded" symbol | (i, symbol) <- zip [0 .. 3 :: Int] [0, 1, 3, 2]]
                 ++ ["scoreboard players operation " ++ player ++ " signal.rx = " ++ score "decoded"]
             )
           ]
