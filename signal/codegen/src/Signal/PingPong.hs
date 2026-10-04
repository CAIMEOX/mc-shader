module Signal.PingPong (generate) where

import Control.Monad (forM_)
import Data.ByteString qualified as BS
import Data.Char (chr)
import Data.List (intercalate)
import Data.Word (Word8)
import Signal.Frame
import Signal.Json
import Signal.Pack (carrier, iterationsPerPower, pipelineWithState, writeAsset)
import Signal.Rotate qualified as Rotate
import System.FilePath ((</>))

data Phase = Warmup | CalibrationWait | CalibrationRead | PayloadWait | PayloadRead deriving (Enum)

owner :: String
owner = "@a[tag=signal.ping.owner,limit=1]"

generate :: FilePath -> String -> IO ()
generate root message = do
  frame <- either fail pure (encodeFrame message)
  let output = root </> "build"
      resource = output </> "resourcepack"
  forM_ (carrier ++ [("assets/signal/post_effect/ping.json", render (pipelineWithState "ping_state"))]) (writeAsset resource)
  writeAsset
    resource
    ( "assets/signal/shaders/include/settings.glsl",
      unlines
        [ "const int ITERATIONS_PER_POWER = " ++ show iterationsPerPower ++ ";",
          "const int FOUR_POWERS[4] = int[4](0, 20, 32, 48);"
        ]
    )
  writeAsset
    resource
    ( "assets/signal/shaders/include/message.glsl",
      unlines
        [ "const uint MESSAGE_FRAME[" ++ show (length frame) ++ "] = uint[" ++ show (length frame) ++ "](" ++ intercalate ", " [show byte ++ "u" | byte <- frame] ++ ");",
          "uint messageBit(uint index) {",
          "  if (index >= " ++ show (length frame * 8) ++ "u) return 0u;",
          "  return (MESSAGE_FRAME[index / 8u] >> (7u - index % 8u)) & 1u;",
          "}"
        ]
    )
  writeAsset resource ("assets/signal/lang/en_us.json", render $ object [("signal.ping." ++ key, string value) | (key, value) <- translations])
  forM_ (assets ++ Rotate.receiverAssets owner) (writeAsset (output </> "datapack"))
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
            ("experiment", string "pingpong"),
            ("frame_limit", int (120 :: Int)),
            ("expected_message", string message),
            ("expected_frame", array (map int frame)),
            ("expected_bits", array (map int (frameBits frame))),
            ("tick_rate", int (200 :: Int)),
            ("power", int (4 :: Int)),
            ("window_ms", int (500 :: Int)),
            ("guard_ms", int (100 :: Int))
          ]
    )

translations :: [(String, String)]
translations =
  [ ("start", "[ping] Post effect started. Calibrating the reply channel..."),
    ("busy", "[ping] A receiver is already active."),
    ("heading", "[ping] Turn slightly away from zero yaw, then start again."),
    ("calibrated", "[ping] Calibrated: light=%s, heavy=%s, threshold=%s (mean microseconds). Receiving..."),
    ("bit", "[ping] bit %s = %s"),
    ("length", "[ping] Frame length: %s bytes"),
    ("character", "[ping] char %s = '%s' (ASCII %s)"),
    ("complete", "[ping] EOF, CRC verified (%2$s bytes): %1$s"),
    ("retry_bit", "[ping] Retrying bit %s (retry %s)."),
    ("retry_frame", "[ping] Frame check failed; recalibrating for attempt %s."),
    ("error", "[ping] Receive failed: %s"),
    ("cancelled", "[ping] Reception cancelled.")
  ]

assets :: [(FilePath, String)]
assets =
  [("data/signal/function/ping/" ++ name ++ ".mcfunction", unlines commands) | (name, commands) <- functions]
    ++ [("data/minecraft/tags/function/" ++ name ++ ".json", render $ object [("values", array [string ("signal:ping/" ++ name)])]) | name <- ["load", "tick"]]
  where
    score name = "#ping_" ++ name ++ " signal"
    set name value = "scoreboard players set " ++ score name ++ " " ++ show (value :: Int)
    add name value = "scoreboard players add " ++ score name ++ " " ++ show (value :: Int)
    op dst operator src = "scoreboard players operation " ++ score dst ++ " " ++ operator ++ " " ++ score src
    fromRotate dst src = "scoreboard players operation " ++ score dst ++ " = #rotate_" ++ src ++ " signal"
    call name = "function signal:ping/" ++ name
    phase value = set "phase" (fromEnum value)
    save path name = "execute store result storage signal:ping " ++ path ++ " int 1 run scoreboard players get " ++ score name
    put path value = "data modify storage signal:ping " ++ path ++ " set value " ++ value
    status = put "status" . quote
    scored prefix name = object [("score", object [("name", string (prefix ++ name)), ("objective", string "signal")])]
    sc = scored "#ping_"
    rc = scored "#rotate_"
    nbt path =
      object
        [ ("nbt", string path),
          ("storage", string "signal:ping"),
          ("interpret", bool True),
          ("separator", string "")
        ]
    chat target key args = "tellraw " ++ target ++ " " ++ render (object [("translate", string ("signal.ping." ++ key)), ("with", array args)])
    say = chat owner
    restartTimer = "stopwatch restart signal:ping/wait"
    functions =
      [ ( "load",
          [ "scoreboard objectives add signal dummy",
            "scoreboard objectives add signal.rx dummy",
            "scoreboard objectives add signal.ping trigger",
            "execute if score " ++ score "active" ++ " matches 1 run " ++ call "cleanup",
            "stopwatch create signal:clock",
            "stopwatch create signal:ping/wait",
            "stopwatch create signal:ping/session",
            "function signal:rotate/load",
            set "active" 0,
            status "idle",
            "schedule clear signal:ping/step",
            put "alphabet" (render $ array [string (if code >= 32 && code <= 126 then [chr code] else "") | code <- [0 .. 127]]),
            put "crc_table" (render $ array [int (crc8 [byte]) | byte <- [0 .. 255 :: Word8]])
          ]
        ),
        ( "tick",
          [ "scoreboard players enable @a signal.ping",
            "execute as @a[scores={signal.ping=1..}] at @s run " ++ call "start"
          ]
        ),
        ( "start",
          [ "execute unless entity @s[type=minecraft:player] run return 0",
            "scoreboard players set @s signal.ping 0",
            "execute if score " ++ score "active" ++ " matches 1 run return run " ++ chat "@s" "busy" [],
            "execute store result score " ++ score "yaw" ++ " run data get entity @s Rotation[0] 1000000",
            "execute if score " ++ score "yaw" ++ " matches -9999..9999 run return run " ++ chat "@s" "heading" [],
            "tag @a remove signal.ping.owner",
            "tag @s add signal.ping.owner",
            set "active" 1,
            set "power" 4,
            set "power_scale" 262144,
            set "mode_scale" 65536,
            set "two" 2,
            set "ten" 10,
            set "frame_retries" 0,
            set "total_bit_retries" 0,
            set "bit_retries" 0,
            set "frame_number" 1,
            "kill @e[tag=signal.ping.carrier]",
            "kill @e[tag=signal.carrier]",
            "execute at @s run summon minecraft:item_display ~ ~1.5 ~ {Tags:[\"signal.carrier\",\"signal.ping.carrier\"],width:0f,height:0f,view_range:4f,item:{id:\"minecraft:stone\",count:1,components:{\"minecraft:item_model\":\"signal:carrier\",\"minecraft:custom_model_data\":{colors:[1]}}}}",
            "posteffect add @s signal:ping",
            "stopwatch restart signal:ping/session",
            restartTimer,
            phase Warmup,
            status "starting",
            put "events" "[]",
            put "bits" "[]",
            put "bytes" "[]",
            put "chars" "[]",
            put "error" (quote ""),
            put "elapsed_ms" "0",
            put "transfer_ms" "0",
            chat "@s" "start" [],
            "schedule function signal:ping/step 1t replace"
          ]
        ),
        ( "step",
          [ "execute unless score " ++ score "active" ++ " matches 1 run return 0",
            "execute unless entity " ++ owner ++ " run return run " ++ call "fail/disconnected",
            "execute store result score " ++ score "session_ms" ++ " run stopwatch query signal:ping/session 1000",
            "execute if score " ++ score "session_ms" ++ " matches 600000.. run return run " ++ call "fail/timeout",
            "execute store result score " ++ score "wait_ms" ++ " run stopwatch query signal:ping/wait 1000",
            call "dispatch",
            "execute if score " ++ score "active" ++ " matches 1 run schedule function signal:ping/step 1t replace"
          ]
        ),
        ( "dispatch",
          [ "execute if score " ++ score "phase" ++ " matches " ++ show (fromEnum state) ++ " run return run " ++ call target
          | (state, target) <-
              [ (Warmup, "warmup"),
                (CalibrationWait, "calibration/wait"),
                (CalibrationRead, "calibration/read"),
                (PayloadWait, "payload/wait"),
                (PayloadRead, "payload/read")
              ]
          ]
        ),
        ("warmup", ["execute if score " ++ score "wait_ms" ++ " matches 1000.. run " ++ call "calibration/start"]),
        ( "calibration/start",
          [ status "calibrating",
            set "cal_index" 0,
            set "bit_retries" 0,
            "function signal:rotate/training/reset",
            call "calibration/request"
          ]
        ),
        ( "calibration/request",
          [ op "mode" "=" "cal_index",
            op "mode" "%=" "two",
            op "slot" "=" "cal_index",
            add "slot" 1,
            phase CalibrationWait,
            call "request"
          ]
        ),
        ( "request",
          [ op "word" "=" "power",
            op "word" "*=" "power_scale",
            op "mode_word" "=" "mode",
            op "mode_word" "*=" "mode_scale",
            op "word" "+=" "mode_word",
            op "word" "+=" "slot",
            save "command.word" "word",
            "execute at " ++ owner ++ " run tp @e[tag=signal.ping.carrier,limit=1] ~ ~1.5 ~",
            "function signal:ping/send with storage signal:ping command",
            restartTimer
          ]
        ),
        ("send", ["$data modify entity @e[tag=signal.ping.carrier,limit=1] item.components.\"minecraft:custom_model_data\".colors set value [$(word)]"]),
        ("calibration/wait", ["execute if score " ++ score "wait_ms" ++ " matches 100.. run " ++ call "calibration/begin"]),
        ( "calibration/begin",
          [ phase CalibrationRead,
            "scoreboard players set #rotate_duration signal 500",
            "scoreboard players set #rotate_enabled signal 1",
            "function signal:rotate/start"
          ]
        ),
        ( "calibration/read",
          [ "execute if score #rotate_collect signal matches 1 run return 0",
            "execute unless score #rotate_valid signal matches 1 run return run " ++ call "calibration/retry",
            "execute if score " ++ score "mode" ++ " matches 0 run function signal:rotate/training/0",
            "execute if score " ++ score "mode" ++ " matches 1 run function signal:rotate/training/1",
            add "cal_index" 1,
            set "bit_retries" 0,
            "execute if score " ++ score "cal_index" ++ " matches ..15 run return run " ++ call "calibration/request",
            "function signal:rotate/model",
            "execute unless score #rotate_ready signal matches 1 run return run " ++ call "fail/calibration",
            fromRotate "margin" "separation",
            op "margin" "/=" "ten",
            say "calibrated" [rc "center0", rc "center1", rc "threshold"],
            call "frame/start"
          ]
        ),
        ( "calibration/retry",
          [ "execute if score " ++ score "bit_retries" ++ " matches 3.. run return run " ++ call "fail/observations",
            add "bit_retries" 1,
            call "calibration/request"
          ]
        ),
        ( "frame/start",
          [status "receiving", put "bits" "[]", put "bytes" "[]", put "chars" "[]", op "frame_started" "=" "session_ms"]
            ++ [set name 0 | name <- ["index", "byte", "bit_count", "kind", "length", "chars", "crc", "bit_retries"]]
            ++ [call "payload/request"]
        ),
        ("payload/request", [set "mode" 2, op "slot" "=" "index", add "slot" 1, phase PayloadWait, call "request"]),
        ("payload/wait", ["execute if score " ++ score "wait_ms" ++ " matches 100.. run " ++ call "payload/begin"]),
        ("payload/begin", [phase PayloadRead, "function signal:rotate/start"]),
        ( "payload/read",
          [ "execute if score #rotate_collect signal matches 1 run return 0",
            "execute unless score #rotate_valid signal matches 1 run return run " ++ call "payload/retry",
            "execute unless score #rotate_decoded signal matches 0..1 run return run " ++ call "payload/retry",
            fromRotate "distance" "value",
            "scoreboard players operation " ++ score "distance" ++ " -= #rotate_threshold signal",
            "execute if score " ++ score "distance" ++ " matches ..-1 run scoreboard players operation " ++ score "distance" ++ " *= #rotate_negative signal",
            "execute if score " ++ score "distance" ++ " < " ++ score "margin" ++ " run return run " ++ call "payload/retry",
            call "payload/accept"
          ]
        ),
        ( "payload/retry",
          [ "execute if score " ++ score "bit_retries" ++ " matches 3.. run return run " ++ call "fail/observations",
            add "bit_retries" 1,
            add "total_bit_retries" 1,
            say "retry_bit" [sc "index", sc "bit_retries"],
            call "payload/request"
          ]
        ),
        ( "payload/accept",
          [ fromRotate "bit" "decoded",
            save "event.bit" "bit",
            save "event.index" "index",
            save "event.frame" "frame_number",
            put "event.kind" (quote "bit"),
            "data modify storage signal:ping events append from storage signal:ping event",
            "data modify storage signal:ping bits append from storage signal:ping event.bit",
            say "bit" [sc "index", sc "bit"],
            op "byte" "*=" "two",
            op "byte" "+=" "bit",
            add "bit_count" 1,
            add "index" 1,
            set "bit_retries" 0,
            "execute if score " ++ score "bit_count" ++ " matches 8 run " ++ call "byte/accept",
            "execute if score " ++ score "active" ++ " matches 1 if score " ++ score "phase" ++ " matches " ++ show (fromEnum PayloadRead) ++ " run " ++ call "payload/request"
          ]
        ),
        ( "byte/accept",
          [ save "byte" "byte",
            "data modify storage signal:ping bytes append from storage signal:ping byte",
            call "byte/dispatch",
            set "byte" 0,
            set "bit_count" 0
          ]
        ),
        ( "byte/dispatch",
          [ "execute if score " ++ score "kind" ++ " matches 0 run return run " ++ call "byte/length",
            "execute if score " ++ score "kind" ++ " matches 1 run return run " ++ call "byte/character",
            call "byte/checksum"
          ]
        ),
        ( "byte/length",
          [ "execute unless score " ++ score "byte" ++ " matches 1..64 run return run " ++ call "frame/retry",
            op "length" "=" "byte",
            save "length" "length",
            call "crc/update",
            say "length" [sc "length"],
            set "kind" 1
          ]
        ),
        ( "byte/character",
          [ "execute unless score " ++ score "byte" ++ " matches 32..126 run return run " ++ call "frame/retry",
            save "lookup.byte" "byte",
            "function signal:ping/byte/lookup with storage signal:ping lookup",
            "data modify storage signal:ping chars append from storage signal:ping character",
            say "character" [sc "chars", nbt "character", sc "byte"],
            add "chars" 1,
            call "crc/update",
            "execute if score " ++ score "chars" ++ " >= " ++ score "length" ++ " run " ++ set "kind" 2
          ]
        ),
        ("byte/lookup", ["$data modify storage signal:ping character set from storage signal:ping alphabet[$(byte)]"]),
        ( "byte/checksum",
          [ save "crc_received" "byte",
            save "crc_expected" "crc",
            "execute unless score " ++ score "byte" ++ " = " ++ score "crc" ++ " run return run " ++ call "frame/retry",
            status "complete",
            save "elapsed_ms" "session_ms",
            op "transfer_ms" "=" "session_ms",
            op "transfer_ms" "-=" "frame_started",
            save "transfer_ms" "transfer_ms",
            say "complete" [nbt "chars[]", sc "length"],
            call "cleanup"
          ]
        ),
        ( "crc/update",
          [ op "xor_left" "=" "crc",
            op "xor_right" "=" "byte",
            set "xor_value" 0,
            set "xor_weight" 1,
            set "xor_count" 0,
            call "crc/xor",
            save "lookup.index" "xor_value",
            "function signal:ping/crc/lookup with storage signal:ping lookup"
          ]
        ),
        ( "crc/xor",
          [ op "xor_a" "=" "xor_left",
            op "xor_a" "%=" "two",
            op "xor_b" "=" "xor_right",
            op "xor_b" "%=" "two",
            op "xor_a" "+=" "xor_b",
            op "xor_a" "%=" "two",
            op "xor_a" "*=" "xor_weight",
            op "xor_value" "+=" "xor_a",
            op "xor_left" "/=" "two",
            op "xor_right" "/=" "two",
            op "xor_weight" "*=" "two",
            add "xor_count" 1,
            "execute if score " ++ score "xor_count" ++ " matches ..7 run " ++ call "crc/xor"
          ]
        ),
        ("crc/lookup", ["$execute store result score " ++ score "crc" ++ " run data get storage signal:ping crc_table[$(index)]"]),
        ( "frame/retry",
          [ "execute if score " ++ score "frame_retries" ++ " matches 2.. run return run " ++ call "fail/frame",
            add "frame_retries" 1,
            add "frame_number" 1,
            say "retry_frame" [sc "frame_number"],
            call "calibration/start"
          ]
        ),
        ( "cancel",
          [ "execute unless score " ++ score "active" ++ " matches 1 run return 0",
            status "cancelled",
            say "cancelled" [],
            call "cleanup"
          ]
        ),
        ( "cleanup",
          [ set "active" 0,
            "schedule clear signal:ping/step",
            "function signal:rotate/stop",
            "kill @e[tag=signal.ping.carrier]",
            "execute as " ++ owner ++ " run posteffect remove @s signal:ping",
            "tag @a remove signal.ping.owner",
            save "total_bit_retries" "total_bit_retries",
            save "frame_retries" "frame_retries"
          ]
        )
      ]
        ++ [ ( "fail/" ++ name,
               [ status "error",
                 put "error" (quote reason),
                 say "error" [string reason],
                 call "cleanup"
               ]
             )
           | (name, reason) <-
               [ ("disconnected", "Receiver disconnected"),
                 ("timeout", "Session timed out"),
                 ("calibration", "Workloads did not separate"),
                 ("observations", "Insufficient or ambiguous replies; turn slightly and retry"),
                 ("frame", "Frame validation failed repeatedly")
               ]
           ]
