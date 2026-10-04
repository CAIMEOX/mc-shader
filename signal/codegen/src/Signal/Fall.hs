module Signal.Fall (generate) where

import Signal.Stream (Receiver (..), receiverAssets)
import Signal.Stream qualified as Stream

generate :: FilePath -> Int -> IO ()
generate root seed = Stream.generate root "fall" "fall" seed (receiverAssets receiver)

receiver :: Receiver
receiver =
  Receiver
    { receiverKey = "fall",
      onLoad = [],
      onSetup = ["gamemode adventure " ++ player, "tp " ++ player ++ " 0.5 1024 0.5 -90 35"],
      onStart = ["execute as " ++ player ++ " store result score #fall_last_y signal run data get entity @s Pos[1] 100000"],
      onPoll =
        [ "execute as " ++ player ++ " store result score #fall_y signal run data get entity @s Pos[1] 100000",
          "scoreboard players operation #fall_dy signal = #fall_y signal",
          "scoreboard players operation #fall_dy signal -= #fall_last_y signal",
          "execute if score #fall_dy signal matches 1.. run scoreboard players add #fall_upward signal 1",
          "execute unless score #fall_dy signal matches 0 run function signal:fall/observe",
          "scoreboard players operation #fall_last_y signal = #fall_y signal"
        ],
      eventFields = [("y", "y"), ("dy", "dy")],
      onStop = [],
      extraFunctions = []
    }
  where
    player = "@a[tag=signal.fall.owner,limit=1]"
