module Signal.Rotate (assets, receiverAssets, probeTurn, isMarker, responseMean) where

-- Angles are sampled in millionths of a degree. The guard keeps float rounding
-- near zero from making the server's remainder operation clear the marker.
probeTurn :: Int -> Maybe Int
probeTurn yaw
  | yaw >= -180000000 && yaw <= -10000 = Just 360
  | yaw >= 10000 && yaw < 180000000 = Just (-360)
  | otherwise = Nothing

isMarker :: Int -> Bool
isMarker yaw = yaw < -180000000 || yaw >= 180000000

responseMean :: [Int] -> Maybe Int
responseMean delays
  | length delays < 3 = Nothing
  | otherwise = Just (sum delays * 1000 `div` length delays)

assets :: [(FilePath, String)]
assets =
  receiverAssets "@a[tag=signal.probe,limit=1]"
    ++ [ ( "data/signal/function/rotate/stage.mcfunction",
           unlines
             [ "fill -32 64 -32 32 70 32 minecraft:air strict",
               "fill -32 63 -32 32 63 32 minecraft:polished_andesite strict",
               "gamemode survival @a[tag=signal.probe,limit=1]",
               "tp @a[tag=signal.probe,limit=1] 0.5 64 0.5 -90 0"
             ]
         )
       ]

receiverAssets :: String -> [(FilePath, String)]
receiverAssets player = [("data/signal/function/rotate/" ++ name ++ ".mcfunction", unlines body) | (name, body) <- functions]
  where
    score name = "#rotate_" ++ name ++ " signal"
    set name value = "scoreboard players set " ++ score name ++ " " ++ show (value :: Int)
    add name value = "scoreboard players add " ++ score name ++ " " ++ show (value :: Int)
    op dst operator src = "scoreboard players operation " ++ score dst ++ " " ++ operator ++ " " ++ score src
    save path name = "execute store result storage signal:rotate " ++ path ++ " int 1 run scoreboard players get " ++ score name
    call name = "function signal:rotate/" ++ name
    sampleYaw = "execute store result score " ++ score "yaw" ++ " run data get entity @s Rotation[0] 1000000"
    functions =
      [ ( "load",
          [ "stopwatch create signal:rotate/window",
            set "collect" 0,
            set "duration" 500,
            set "limit" 512,
            set "enabled" 1,
            set "winding" 0,
            set "minimum_separation" 2000,
            set "scale" 1000,
            set "two" 2,
            set "negative" (-1),
            "schedule clear signal:rotate/poll"
          ]
        ),
        ( "start",
          [ "data modify storage signal:rotate events set value []",
            "stopwatch restart signal:rotate/window",
            "scoreboard players set " ++ player ++ " signal.rx -1"
          ]
            ++ [ set name 0
               | name <-
                   [ "polls",
                     "events",
                     "arms",
                     "skips",
                     "timeouts",
                     "sum",
                     "waiting",
                     "ground_polls",
                     "valid",
                     "value"
                   ]
               ]
            ++ [ set "collect" 1,
                 "execute as " ++ player ++ " at @s run " ++ call "arm",
                 "schedule function signal:rotate/poll 1t replace"
               ]
        ),
        ( "poll",
          [ "execute unless score " ++ score "collect" ++ " matches 1 run return 0",
            "execute store result score " ++ score "elapsed" ++ " run stopwatch query signal:rotate/window 1000",
            "execute if score " ++ score "elapsed" ++ " >= " ++ score "duration" ++ " run return run " ++ call "stop",
            "execute as " ++ player ++ " at @s run " ++ call "sample",
            "schedule function signal:rotate/poll 1t replace"
          ]
        ),
        ( "sample",
          [ add "polls" 1,
            sampleYaw,
            "execute if entity @s[nbt={OnGround:1b}] run " ++ add "ground_polls" 1,
            "execute if score " ++ score "waiting" ++ " matches 1 if score " ++ score "yaw" ++ " matches -180000000..179999999 run " ++ call "reply",
            "execute if score " ++ score "waiting" ++ " matches 0 if score " ++ score "arms" ++ " < " ++ score "limit" ++ " run " ++ call "arm"
          ]
        ),
        ( "arm",
          [ "execute unless score " ++ score "enabled" ++ " matches 1 run return 0",
            sampleYaw,
            set "turn" 0,
            "execute if score " ++ score "yaw" ++ " matches -180000000..-10000 run " ++ set "turn" 360,
            "execute if score " ++ score "yaw" ++ " matches 10000..179999999 run " ++ set "turn" (-360),
            "execute if score " ++ score "turn" ++ " matches 0 run return run " ++ add "skips" 1,
            "execute store result score " ++ score "sent" ++ " run stopwatch query signal:clock 1000",
            "execute if score " ++ score "turn" ++ " matches 360 run rotate @s ~360 ~",
            "execute if score " ++ score "turn" ++ " matches -360 run rotate @s ~-360 ~",
            op "winding" "+=" "turn",
            sampleYaw,
            op "armed_yaw" "=" "yaw",
            add "arms" 1,
            set "waiting" 1
          ]
        ),
        ( "reply",
          [ "execute store result score " ++ score "now" ++ " run stopwatch query signal:clock 1000",
            op "delay" "=" "now",
            op "delay" "-=" "sent",
            op "sum" "+=" "delay",
            add "events" 1,
            save "event.time_ms" "now",
            save "event.delay_ms" "delay",
            save "event.armed_yaw" "armed_yaw",
            save "event.reply_yaw" "yaw",
            "execute store result storage signal:rotate event.on_ground int 1 run data get entity @s OnGround",
            "data modify storage signal:rotate events append from storage signal:rotate event",
            set "waiting" 0
          ]
        ),
        ( "stop",
          [ set "collect" 0,
            "schedule clear signal:rotate/poll",
            op "timeouts" "=" "waiting",
            call "feature",
            call "decode",
            "execute as " ++ player ++ " at @s run " ++ call "unwind"
          ]
        ),
        ( "unwind",
          [ "execute if score " ++ score "winding" ++ " matches 0 run return 0",
            set "undo" 0,
            op "undo" "-=" "winding",
            save "unwind.turn" "undo",
            "function signal:rotate/unwind_apply with storage signal:rotate unwind",
            set "winding" 0,
            set "waiting" 0
          ]
        ),
        ("unwind_apply", ["$rotate @s ~$(turn) ~"]),
        ( "feature",
          [ set "valid" 0,
            set "value" 0,
            "execute unless score " ++ score "events" ++ " matches 3.. run return 0",
            op "value" "=" "sum",
            op "value" "*=" "scale",
            op "value" "/=" "events",
            set "valid" 1
          ]
        ),
        ("training/reset", [set name 0 | name <- ["sum0", "sum1", "count0", "count1", "ready"]])
      ]
        ++ [ ( "training/" ++ show bit,
               [ "execute unless score " ++ score "valid" ++ " matches 1 run return 0",
                 op ("sum" ++ show bit) "+=" "value",
                 add ("count" ++ show bit) 1
               ]
             )
           | bit <- [0, 1 :: Int]
           ]
        ++ [ ( "model",
               [set "ready" 0]
                 ++ ["execute unless score " ++ score ("count" ++ show bit) ++ " matches 1.. run return 0" | bit <- [0, 1 :: Int]]
                 ++ concat
                   [ [ op ("center" ++ show bit) "=" ("sum" ++ show bit),
                       op ("center" ++ show bit) "/=" ("count" ++ show bit)
                     ]
                   | bit <- [0, 1 :: Int]
                   ]
                 ++ [ op "separation" "=" "center1",
                      op "separation" "-=" "center0",
                      "execute if score " ++ score "separation" ++ " matches ..-1 run " ++ op "separation" "*=" "negative",
                      "execute unless score " ++ score "separation" ++ " >= " ++ score "minimum_separation" ++ " run return 0",
                      op "threshold" "=" "center0",
                      op "threshold" "+=" "center1",
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
                 op "decoded" "=" "low_bit",
                 "execute if score " ++ score "value" ++ " > " ++ score "threshold" ++ " run " ++ op "decoded" "=" "high_bit",
                 "scoreboard players operation " ++ player ++ " signal.rx = " ++ score "decoded"
               ]
             )
           ]
