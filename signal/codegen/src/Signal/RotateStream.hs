module Signal.RotateStream (generate) where

import Signal.Stream (Receiver (..), receiverAssets)
import Signal.Stream qualified as Stream

generate :: FilePath -> Int -> IO ()
generate root seed = Stream.generate root "rstream" "rotate_stream" seed (receiverAssets receiver)

receiver :: Receiver
receiver =
  Receiver
    { receiverKey = "rstream",
      onLoad = [set "winding" 0, set "waiting" 0, set "skips" 0],
      onSetup =
        [ "fill -32 64 -32 32 70 32 minecraft:air strict",
          "fill -32 63 -32 32 63 32 minecraft:polished_andesite strict",
          "gamemode survival " ++ player,
          "tp " ++ player ++ " 0.5 64 0.5 -90 0"
        ],
      onStart = [set "waiting" 0, set "skips" 0, "execute as " ++ player ++ " at @s run " ++ call "arm"],
      onPoll = ["execute as " ++ player ++ " at @s run " ++ call "sample"],
      eventFields = [("armed_yaw", "armed_yaw"), ("reply_yaw", "yaw"), ("delay_ticks", "delay_ticks")],
      onStop = ["execute as " ++ player ++ " at @s run " ++ call "unwind"],
      extraFunctions =
        [ ( "sample",
            [ sampleYaw,
              "execute if score " ++ score "waiting" ++ " matches 1 if score " ++ score "yaw" ++ " matches -180000000..179999999 run " ++ call "reply",
              "execute if score " ++ score "active" ++ " matches 1 if score " ++ score "waiting" ++ " matches 0 run " ++ call "arm"
            ]
          ),
          ( "arm",
            [ sampleYaw,
              set "turn" 0,
              "execute if score " ++ score "yaw" ++ " matches -180000000..-10000 run " ++ set "turn" 360,
              "execute if score " ++ score "yaw" ++ " matches 10000..179999999 run " ++ set "turn" (-360),
              "execute if score " ++ score "turn" ++ " matches 0 run return run scoreboard players add " ++ score "skips" ++ " 1",
              "execute if score " ++ score "turn" ++ " matches 360 run rotate @s ~360 ~",
              "execute if score " ++ score "turn" ++ " matches -360 run rotate @s ~-360 ~",
              op "winding" "+=" "turn",
              sampleYaw,
              op "armed_yaw" "=" "yaw",
              op "armed_tick" "=" "ticks",
              set "waiting" 1
            ]
          ),
          ( "reply",
            [ op "delay_ticks" "=" "ticks",
              op "delay_ticks" "-=" "armed_tick",
              set "waiting" 0,
              call "observe"
            ]
          ),
          ( "unwind",
            [ set "waiting" 0,
              "execute if score " ++ score "winding" ++ " matches 0 run return 0",
              set "undo" 0,
              op "undo" "-=" "winding",
              "execute store result storage signal:rstream unwind.turn int 1 run scoreboard players get " ++ score "undo",
              "function signal:rstream/unwind_apply with storage signal:rstream unwind",
              set "winding" 0
            ]
          ),
          ("unwind_apply", ["$rotate @s ~$(turn) ~"])
        ]
    }
  where
    player = "@a[tag=signal.rstream.owner,limit=1]"
    score name = "#rstream_" ++ name ++ " signal"
    set name value = "scoreboard players set " ++ score name ++ " " ++ show (value :: Int)
    op dst operator src = "scoreboard players operation " ++ score dst ++ " " ++ operator ++ " " ++ score src
    call name = "function signal:rstream/" ++ name
    sampleYaw = "execute store result score " ++ score "yaw" ++ " run data get entity @s Rotation[0] 1000000"
