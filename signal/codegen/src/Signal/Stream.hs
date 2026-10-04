module Signal.Stream (generate, Pattern (..), payloadLength, payloadBits, Gap (..), classifyGap, Receiver (..), receiverAssets) where

import Control.Monad (forM_, unless)
import Data.Bits ((.&.))
import Data.ByteString qualified as BS
import Signal.Json
import Signal.Pack (carrier, iterationsPerPower, pipelineWithShaders, writeAsset)
import Signal.Protocol (digest)
import System.FilePath ((</>))

data Pattern = Zeroes | Ones | Alternating | DigestBits deriving (Eq, Show, Enum, Bounded)

data Gap = Burst | Bit Int | Delimiter deriving (Eq, Show)

payloadLength :: Int
payloadLength = 64

payloadBits :: Int -> Pattern -> [Int]
payloadBits seed pattern = [bit i | i <- [0 .. payloadLength - 1]]
  where
    bit i = case pattern of
      Zeroes -> 0
      Ones -> 1
      Alternating -> i `mod` 2
      DigestBits -> fromIntegral (digest (seed + i) .&. 1)

classifyGap :: Int -> Int -> Int -> Gap
classifyGap threshold sync ticks
  | ticks < 4 = Burst
  | ticks >= sync = Delimiter
  | otherwise = Bit (if ticks >= threshold then 1 else 0)

generate :: FilePath -> String -> String -> Int -> [(FilePath, String)] -> IO ()
generate root key experiment seed assets = do
  unless (seed >= 1 && seed <= 64000) (fail "Stream seed must be in 1..64000")
  let output = root </> "build"
      resource = output </> "resourcepack"
      shaders = pipelineWithShaders "stream_state" "stream_work" "stream_composite"
  forM_ (carrier ++ [("assets/signal/post_effect/" ++ key ++ ".json", render shaders)]) (writeAsset resource)
  writeAsset
    resource
    ( "assets/signal/shaders/include/stream_settings.glsl",
      unlines
        [ "const uint STREAM_SEED = " ++ show seed ++ "u;",
          "const uint STREAM_BITS = " ++ show payloadLength ++ "u;",
          "const uint STREAM_WARMUP = 8u;",
          "const int ITERATIONS_PER_POWER = " ++ show iterationsPerPower ++ ";"
        ]
    )
  forM_ assets (writeAsset (output </> "datapack"))
  BS.writeFile (output </> "carrier.rgba") $
    BS.pack
      [ component
      | _y <- [0 .. 3 :: Int],
        x <- [0 .. 7 :: Int],
        component <- [fromIntegral (x `div` 4), 0, 239, 247]
      ]
  writeAsset
    output
    ( "experiment.json",
      render $
        object
          [ ("minecraft", string "26.3"),
            ("experiment", string experiment),
            ("frame_limit", int (120 :: Int)),
            ("tick_rate", int (200 :: Int)),
            ("seed", int seed),
            ("payload_bits", int payloadLength),
            ("pilot_powers", array (map int [0 :: Int, 8, 12, 16, 20, 24, 28, 32, 40, 63])),
            ( "patterns",
              array
                [ object
                    [ ("name", string (show pattern)),
                      ("id", int (fromEnum pattern)),
                      ("expected_bits", array (map int (payloadBits seed pattern)))
                    ]
                | pattern <- [minBound .. maxBound]
                ]
            )
          ]
    )

data Receiver = Receiver
  { receiverKey :: String,
    onLoad :: [String],
    onSetup :: [String],
    onStart :: [String],
    onPoll :: [String],
    eventFields :: [(String, String)],
    onStop :: [String],
    extraFunctions :: [(String, [String])]
  }

receiverAssets :: Receiver -> [(FilePath, String)]
receiverAssets receiver =
  [("data/signal/function/" ++ key ++ "/" ++ name ++ ".mcfunction", unlines body) | (name, body) <- functions ++ extraFunctions receiver]
    ++ [("data/minecraft/tags/function/load.json", render $ object [("values", array [string ("signal:" ++ key ++ "/load")])])]
  where
    key = receiverKey receiver
    player = "@a[tag=signal." ++ key ++ ".owner,limit=1]"
    score name = "#" ++ key ++ "_" ++ name ++ " signal"
    set name value = "scoreboard players set " ++ score name ++ " " ++ show (value :: Int)
    op dst operator src = "scoreboard players operation " ++ score dst ++ " " ++ operator ++ " " ++ score src
    save path name = "execute store result storage signal:" ++ key ++ " " ++ path ++ " int 1 run scoreboard players get " ++ score name
    put path value = "data modify storage signal:" ++ key ++ " " ++ path ++ " set value " ++ value
    append list entry = "data modify storage signal:" ++ key ++ " " ++ list ++ " append from storage signal:" ++ key ++ " " ++ entry
    call name = "function signal:" ++ key ++ "/" ++ name
    status value = put "status" (quote value)
    fields path entries = [save (path ++ "." ++ field) name | (field, name) <- entries]
    rawTimes = [("time_ms", "now"), ("tick", "ticks"), ("gap_ms", "gap_ms"), ("gap_ticks", "gap_ticks")]
    functions =
      [ ( "load",
          [ "scoreboard objectives add signal dummy",
            "scoreboard objectives add signal.rx dummy",
            "stopwatch create signal:" ++ key ++ "/window",
            set "active" 0,
            set "threshold" 16,
            set "sync" 32,
            set "duration" 2000,
            set "stream" 0,
            set "min_gap" 4,
            "schedule clear signal:" ++ key ++ "/poll",
            status "idle"
          ]
            ++ onLoad receiver
        ),
        ( "setup",
          [ call "stop",
            "posteffect remove " ++ player ++ " signal:" ++ key,
            "kill @e[tag=signal." ++ key ++ ".carrier]"
          ]
            ++ onSetup receiver
            ++ [ "execute at " ++ player ++ " run summon minecraft:item_display ~ ~1.5 ~ {Tags:[\"signal." ++ key ++ ".carrier\"],width:0f,height:0f,view_range:16f,item:{id:\"minecraft:stone\",count:1,components:{\"minecraft:item_model\":\"signal:carrier\",\"minecraft:custom_model_data\":{colors:[0]}}}}",
                 "posteffect add " ++ player ++ " signal:" ++ key
               ]
        ),
        ("send", ["$data modify entity @e[tag=signal." ++ key ++ ".carrier,limit=1] item.components.\"minecraft:custom_model_data\".colors set value [$(word)]"]),
        ( "start",
          [ "stopwatch restart signal:" ++ key ++ "/window",
            status "measuring",
            put "events" "[]",
            put "intervals" "[]",
            put "bits" "[]",
            "scoreboard players set " ++ player ++ " signal.rx -1"
          ]
            ++ [ set name 0
               | name <-
                   [ "ticks",
                     "phase",
                     "changes",
                     "groups",
                     "ground_polls",
                     "upward",
                     "last_change",
                     "group_time",
                     "group_tick",
                     "last_tick",
                     "started_ms",
                     "ended_ms",
                     "bit_count"
                   ]
               ]
            ++ [set "active" 1]
            ++ onStart receiver
            ++ ["schedule function signal:" ++ key ++ "/poll 1t replace"]
        ),
        ( "poll",
          [ "execute unless score " ++ score "active" ++ " matches 1 run return 0",
            "scoreboard players add " ++ score "ticks" ++ " 1",
            "execute store result score " ++ score "now" ++ " run stopwatch query signal:" ++ key ++ "/window 1000",
            "execute if score " ++ score "now" ++ " >= " ++ score "duration" ++ " run return run " ++ call "timeout",
            "execute if entity @a[tag=signal." ++ key ++ ".owner,limit=1,nbt={OnGround:true}] run scoreboard players add " ++ score "ground_polls" ++ " 1"
          ]
            ++ onPoll receiver
            ++ ["execute if score " ++ score "active" ++ " matches 1 run schedule function signal:" ++ key ++ "/poll 1t replace"]
        ),
        ( "observe",
          [ op "gap_ms" "=" "now",
            op "gap_ms" "-=" "last_change",
            op "gap_ticks" "=" "ticks",
            op "gap_ticks" "-=" "last_tick"
          ]
            ++ fields "event" (rawTimes ++ eventFields receiver)
            ++ [ append "events" "event",
                 "execute if score " ++ score "groups" ++ " matches 0 run " ++ call "first_group",
                 "execute if score " ++ score "changes" ++ " matches 1.. if score " ++ score "gap_ticks" ++ " >= " ++ score "min_gap" ++ " run " ++ call "group",
                 "scoreboard players add " ++ score "changes" ++ " 1",
                 op "last_change" "=" "now",
                 op "last_tick" "=" "ticks"
               ]
        ),
        ("first_group", [set "groups" 1, op "group_time" "=" "now", op "group_tick" "=" "ticks"]),
        ( "group",
          [ op "delta_ms" "=" "now",
            op "delta_ms" "-=" "group_time",
            op "delta_ticks" "=" "ticks",
            op "delta_ticks" "-=" "group_tick"
          ]
            ++ fields
              "interval"
              [ ("time_ms", "now"),
                ("tick", "ticks"),
                ("gap_ms", "delta_ms"),
                ("gap_ticks", "delta_ticks")
              ]
            ++ [ append "intervals" "interval",
                 "scoreboard players add " ++ score "groups" ++ " 1",
                 "execute if score " ++ score "stream" ++ " matches 1 run " ++ call "decode",
                 op "group_time" "=" "now",
                 op "group_tick" "=" "ticks"
               ]
        ),
        ( "decode",
          [ "execute if score " ++ score "delta_ticks" ++ " >= " ++ score "sync" ++ " run return run " ++ call "delimiter",
            "execute if score " ++ score "phase" ++ " matches 1 run " ++ call "bit"
          ]
        ),
        ( "delimiter",
          [ "execute if score " ++ score "phase" ++ " matches 1 run return run " ++ call "complete",
            set "phase" 1,
            op "started_ms" "=" "now",
            status "receiving"
          ]
        ),
        ( "bit",
          [ set "bit" 0,
            "execute if score " ++ score "delta_ticks" ++ " >= " ++ score "threshold" ++ " run " ++ set "bit" 1,
            "scoreboard players operation " ++ player ++ " signal.rx = " ++ score "bit",
            save "bit" "bit",
            append "bits" "bit",
            "scoreboard players add " ++ score "bit_count" ++ " 1"
          ]
        ),
        ("complete", [set "phase" 2, set "active" 0, op "ended_ms" "=" "now", status "complete"] ++ onStop receiver),
        ( "timeout",
          [ set "active" 0,
            op "ended_ms" "=" "now",
            status "complete",
            "execute if score " ++ score "stream" ++ " matches 1 run " ++ status "timeout"
          ]
            ++ onStop receiver
        ),
        ("stop", [set "active" 0, "schedule clear signal:" ++ key ++ "/poll"] ++ onStop receiver)
      ]
