module Signal.Pack (generate, generateWithLevels, carrier, pipelineWithState, pipelineWithShaders, writeAsset, iterationsPerPower) where

import Control.Monad (forM_, unless)
import Data.ByteString qualified as BS
import Data.List (intercalate)
import Signal.Json
import Signal.Protocol
import Signal.Rotate qualified as Rotate
import Signal.Water qualified as Water
import System.Directory (createDirectoryIfMissing)
import System.FilePath (takeDirectory, (</>))

type Asset = (FilePath, String)

iterationsPerPower :: Int
iterationsPerPower = 1024

writeAsset :: FilePath -> Asset -> IO ()
writeAsset root (path, contents) = do
  createDirectoryIfMissing True (takeDirectory (root </> path))
  writeFile (root </> path) (contents ++ "\n")

pipeline :: Json
pipeline = pipelineWithState "state"

pipelineWithState :: String -> Json
pipelineWithState stateShader = pipelineWithShaders stateShader "work" "composite"

pipelineWithShaders :: String -> String -> String -> Json
pipelineWithShaders stateShader workShader compositeShader =
  object
    [ ( "targets",
        object
          [ ("state", target 2 1 True),
            ("next", target 2 1 False),
            ("work", target 512 512 False),
            ("swap", object [])
          ]
      ),
      ( "passes",
        array
          [ stage stateShader [("Main", "minecraft:main"), ("Previous", "state")] "next",
            stage "copy" [("In", "next")] "state",
            stage workShader [("State", "state")] "work",
            stage compositeShader [("Main", "minecraft:main"), ("State", "state"), ("Work", "work")] "swap",
            stage "copy" [("In", "swap")] "minecraft:main"
          ]
      )
    ]
  where
    target w h persistent = object [("width", int (w :: Int)), ("height", int (h :: Int)), ("persistent", bool persistent)]
    stage shader inputs output =
      object
        [ ("vertex_shader", string "minecraft:core/screenquad"),
          ("fragment_shader", string ("signal:post/" ++ shader)),
          ("inputs", array [object [("sampler_name", string sampler), ("target", string source)] | (sampler, source) <- inputs]),
          ("output", string output)
        ]

carrier :: [Asset]
carrier =
  [ ( "assets/signal/models/carrier.json",
      render $
        object
          [ ("textures", object [("data", string "signal:block/carrier"), ("particle", string "signal:block/carrier")]),
            ("elements", array [element i | i <- [0, 1 :: Int]])
          ]
    ),
    ( "assets/signal/items/carrier.json",
      render $
        object
          [ ( "model",
              object
                [ ("type", string "minecraft:model"),
                  ("model", string "signal:carrier"),
                  ( "tints",
                    array
                      [ object
                          [ ("type", string "minecraft:custom_model_data"),
                            ("index", int (0 :: Int)),
                            ("default", int (1 :: Int))
                          ]
                      ]
                  )
                ]
            )
          ]
    )
  ]
  where
    element i =
      object
        [ ("from", array (map int [0 :: Int, 0, 0])),
          ("to", array (map int [16 :: Int, 16, 0])),
          ("shade_direction_override", string "up"),
          ( "faces",
            object
              [ ( "south",
                  object
                    [ ("texture", string "#data"),
                      ("uv", array (map int [2 + 8 * i, 4, 6 + 8 * i, 12])),
                      ("tintindex", int (0 :: Int))
                    ]
                )
              ]
          )
        ]

dataPack :: [Asset]
dataPack =
  [("data/signal/function/" ++ name ++ ".mcfunction", unlines commands) | (name, commands) <- functions]
    ++ [("data/minecraft/tags/function/" ++ name ++ ".json", render $ object [("values", array [string ("signal:" ++ name)])]) | name <- ["load", "tick"]]
  where
    functions =
      [ ( "load",
          [ "scoreboard objectives add signal dummy",
            "stopwatch create signal:clock",
            "scoreboard players set #collect signal 0",
            "function signal:water/load",
            "function signal:rotate/load"
          ]
        ),
        ( "start",
          [ "kill @e[tag=signal.carrier]",
            "summon minecraft:item_display 0 66 0 {Tags:[\"signal.carrier\"],width:0f,height:0f,view_range:4f,item:{id:\"minecraft:stone\",count:1,components:{\"minecraft:item_model\":\"signal:carrier\",\"minecraft:custom_model_data\":{colors:[1]}}}}"
          ]
        ),
        ("select", ["$data modify entity @e[type=minecraft:item_display,tag=signal.carrier,limit=1] item.components.\"minecraft:custom_model_data\".colors set value [$(word)]"]),
        ("tick", ["execute if score #collect signal matches 1 run function signal:sample"]),
        ( "measure/start",
          [ "data modify storage signal:measurement intervals set value []",
            "execute store result score #last signal run stopwatch query signal:clock 1000",
            "scoreboard players set #collect signal 1"
          ]
        ),
        ("measure/stop", ["scoreboard players set #collect signal 0"]),
        ( "sample",
          [ "execute store result score #now signal run stopwatch query signal:clock 1000",
            "scoreboard players operation #delta signal = #now signal",
            "scoreboard players operation #delta signal -= #last signal",
            "scoreboard players operation #last signal = #now signal",
            "execute store result storage signal:measurement delta int 1 run scoreboard players get #delta signal",
            "data modify storage signal:measurement intervals append from storage signal:measurement delta"
          ]
        )
      ]

generate :: FilePath -> Int -> [Int] -> IO ()
generate root payloadStart rates = generateWithLevels root payloadStart rates [0, 20, 32, 48]

generateWithLevels :: FilePath -> Int -> [Int] -> [Int] -> IO ()
generateWithLevels root payloadStart rates levels = do
  unless (length levels == 4 && all (\p -> p >= 0 && p <= 63) levels && and (zipWith (<) levels (drop 1 levels))) (fail "Four workload powers must be increasing values in 0..63")
  unless (not (null rates) && all (\r -> r >= 1 && r <= 10000) rates) (fail "Tick rates must be in 1..10000")
  payload <- either fail pure (balancedPayload payloadStart)
  fourPayload <- either fail pure (balancedFourPayload payloadStart)
  speedCases <-
    mapM
      speedCase
      [ (continuous, milliseconds, offset)
      | (continuous, base) <- [(False, 256), (True, 1024)],
        (milliseconds, offset) <- zip [500, 400, 300 :: Int] [base, base + 256 ..]
      ]
  let output = root </> "build"
  forM_ (carrier ++ [("assets/minecraft/post_effect/end_of_frame.json", render pipeline)]) (writeAsset (output </> "resourcepack"))
  writeAsset
    (output </> "resourcepack")
    ( "assets/signal/shaders/include/settings.glsl",
      unlines
        [ "const int ITERATIONS_PER_POWER = " ++ show iterationsPerPower ++ ";",
          "const int FOUR_POWERS[4] = int[4](" ++ intercalate ", " (map show levels) ++ ");"
        ]
    )
  forM_ (dataPack ++ Water.assets ++ Rotate.assets) (writeAsset (output </> "datapack"))
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
            ("framebuffer", array (map int [1280 :: Int, 720])),
            ("frame_limit", int (120 :: Int)),
            ("tick_rates", array (map int rates)),
            ("payload_start", int payloadStart),
            ("training_windows", int (16 :: Int)),
            ("window_seconds", number 1.5),
            ("settle_seconds", number 0.4),
            ("water_settle_seconds", number 0.8),
            ("water_window_seconds", number Water.windowSeconds),
            ("target_frame_ms", int (80 :: Int)),
            ("work_size", array (map int [512 :: Int, 512])),
            ("pilot_powers", array (map int [1 :: Int, 2, 4, 8, 16, 32, 63])),
            ("iterations_per_power", int iterationsPerPower),
            ("payload", payloadJson payload),
            ("speed_cases", array speedCases),
            ("speed_calibration_ms", int (1000 :: Int)),
            ("speed_guard_ms", int (50 :: Int)),
            ("speed_block_symbols", int (4 :: Int)),
            ("scan_window_ms", int (1000 :: Int)),
            ("scan_repetitions", int (4 :: Int)),
            ("scan_powers", array (map int [0 :: Int, 8, 12, 16, 20, 24, 28, 32, 40, 48, 63])),
            ("four_powers", array (map int levels)),
            ( "four_payload",
              array
                [ object
                    [ ("sequence", int (sequenceId request)),
                      ("digest", int (digest (sequenceId request))),
                      ("symbol", int (resultSymbol request))
                    ]
                | request <- fourPayload
                ]
            )
          ]
    )
  where
    payloadJson requests =
      array
        [ object
            [ ("sequence", int (sequenceId request)),
              ("digest", int (digest (sequenceId request))),
              ("bit", int (resultBit request))
            ]
        | request <- requests
        ]
    speedCase (continuous, milliseconds, offset) = do
      requests <- either fail pure (balancedPayload (1 + (payloadStart + offset - 1) `mod` 64000))
      pure $
        object
          [ ("continuous", bool continuous),
            ("window_ms", int milliseconds),
            ("payload", payloadJson requests)
          ]
