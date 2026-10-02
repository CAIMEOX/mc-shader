module Flame.Pack (generate) where

import Control.Monad (forM_)
import Data.Bits (shiftR, (.&.))
import Data.ByteString qualified as BS
import Data.Char (toUpper)
import Data.List (intercalate, isPrefixOf)
import Flame.DataPack (dataPack)
import Flame.Domain
import Flame.Json
import Flame.Pipeline
import Flame.Program (makePipeline)
import Flame.Protocol
import System.Directory (copyFile, createDirectoryIfMissing, doesDirectoryExist, listDirectory)
import System.FilePath (takeDirectory, (</>))

type Asset = (FilePath, String)

metadata :: Config -> Json
metadata c =
  object
    [ ("minecraft", string "26.3"),
      ("region", array (map int (components (region c)))),
      ("grid", array (map int (components (grid c)))),
      ("cell_width", number 0.5),
      ("volume_size", let (w, h) = renderSize c in array [int w, int h]),
      ("fuel_profiles", array [object [("id", int (fromEnum m)), ("load", number (fuelLoad (profile m))), ("pyrolysis_temperature", number (pyrolysisTemperature (profile m))), ("pyrolysis_rate", number (pyrolysisRate (profile m)))] | m <- [minBound .. maxBound]]),
      ("shape_masks", array (map int shapeMasks)),
      ("unknown_shape", int unknownShape),
      ("terrain_words", int (terrainWords c)),
      ("header_words", int headerWords),
      ("packet_words", int (packetWords c)),
      ("packet_size", let (w, h) = packetDimensions c in array [int w, int h]),
      ("pressure_iterations", int (pressureIterations c)),
      ("stairs", array [object [("half", string (halfName h)), ("facing", string (facingName f)), ("shape", string (turnName turn)), ("id", int (shapeId (stairMask stair))), ("mask", int (stairMask stair))] | stair@(Stair h f turn) <- stairs])
    ]

settings :: Config -> String
settings c =
  unlines $
    [ "#ifndef FLAME_SETTINGS",
      "#define FLAME_SETTINGS",
      "const ivec3 REGION=ivec3(" ++ csv (components (region c)) ++ ");",
      "const ivec3 GRID=ivec3(" ++ csv (components (grid c)) ++ ");",
      "const ivec3 COARSE=ivec3(" ++ csv (map (\n -> (n + 3) `div` 4) (components (grid c))) ++ ");",
      "const int CELLS=" ++ show (volume (grid c)) ++ ";",
      "const int HEADER_WORDS=" ++ show headerWords ++ ";",
      "const int PACKET_WORDS=" ++ show (packetWords c) ++ ";",
      "const ivec2 PACKET_SIZE=ivec2(" ++ show pw ++ "," ++ show ph ++ ");",
      "const uint MAGIC=0x464c4du;",
      "const float CELL_SIZE=0.5;",
      "const float DT=1.0/30.0;",
      "const float AMBIENT=293.0;",
      "const float FUEL_LOAD[4]=float[](" ++ floats fuelLoad ++ ");",
      "const float PYROLYSIS_T[4]=float[](" ++ floats pyrolysisTemperature ++ ");",
      "const float PYROLYSIS_RATE[4]=float[](" ++ floats pyrolysisRate ++ ");",
      "const int SHAPE_MASKS[" ++ show (length shapeMasks) ++ "]=int[](" ++ csv shapeMasks ++ ");"
    ]
      ++ ["const int FIELD_" ++ upper (fieldName f) ++ "=" ++ show offset ++ ";" | (offset, f) <- fieldOffsets header]
      ++ ["#endif"]
  where
    csv = intercalate "," . map show
    upper = map (\x -> if x == '.' then '_' else toUpper x)
    floats f = intercalate "," [show (f (profile m)) | m <- [minBound .. maxBound]]
    (pw, ph) = packetDimensions c

carrierAssets :: Config -> [Asset]
carrierAssets c =
  [ ("assets/flame/models/carrier.json", render $ object [("textures", object [("data", string "flame:block/carrier"), ("particle", string "flame:block/carrier")]), ("elements", array elements)]),
    ("assets/flame/items/carrier.json", render $ object [("model", object [("type", string "minecraft:model"), ("model", string "flame:carrier"), ("tints", array tints)])])
  ]
  where
    elements =
      [ object
          [ ("from", array (map int [0 :: Int, 0, 0])),
            ("to", array (map int [16 :: Int, 16, 0])),
            ("shade_direction_override", string "up"),
            ("faces", object [("south", object [("texture", string "#data"), ("uv", array (map number (uv i))), ("tintindex", int (max 0 (i - 5)))])])
          ]
      | i <- [0 .. packetWords c - 1]
      ]
    uv i =
      let x = fromIntegral (i `mod` 32) * 4
          y = fromIntegral (i `div` 32) * 4
       in [(x + 1) / 8, (y + 1) / 8, (x + 3) / 8, (y + 3) / 8]
    tints = [object [("type", string "minecraft:custom_model_data"), ("index", int i), ("default", int (0 :: Int))] | i <- [0 .. dataWords c - 1]]

writeAsset :: FilePath -> Asset -> IO ()
writeAsset root (path, contents) = do
  createDirectoryIfMissing True (takeDirectory (root </> path))
  writeFile (root </> path) (contents ++ "\n")

copyTree :: FilePath -> FilePath -> IO ()
copyTree source destination = do
  createDirectoryIfMissing True destination
  files <- listDirectory source
  forM_ files $ \name -> do
    directory <- doesDirectoryExist (source </> name)
    if directory then copyTree (source </> name) (destination </> name) else copyFile (source </> name) (destination </> name)

replaceMain :: String -> String -> Either String String
replaceMain patch source = go source
  where
    needle = "void main() {"
    go [] = Left "Core shader entry point was not found"
    go text@(x : xs)
      | needle `isPrefixOf` text = Right (patch ++ drop (length needle) text)
      | otherwise = (x :) <$> go xs

generate :: FilePath -> Config -> IO ()
generate root c = do
  let output = root </> "build"
      rp = output </> "resourcepack"
      dp = output </> "datapack"
  compiled <- either fail pure (compile (makePipeline c))
  copyTree (root </> "shaders/include") (rp </> "assets/flame/shaders/include")
  copyTree (root </> "shaders/post") (rp </> "assets/flame/shaders/post")
  forM_ (carrierAssets c ++ [("assets/minecraft/post_effect/end_of_frame.json", render compiled), ("assets/flame/shaders/include/settings.glsl", settings c)]) (writeAsset rp)
  forM_ (dataPack c) (writeAsset dp)
  writeAsset output ("flame-build.json", render (metadata c))
  forM_ ["item", "entity", "block"] $ \name -> forM_ ["vsh", "fsh"] $ \ext -> do
    original <- readFile (output </> "vanilla" </> (name ++ "." ++ ext))
    patch <- readFile (root </> "shaders/core" </> ("carrier." ++ ext ++ ".inc"))
    combined <- either fail pure (replaceMain patch original)
    writeAsset rp ("assets/minecraft/shaders/core/" ++ name ++ "." ++ ext, combined)
  let pixels = concat [[fromIntegral (index .&. 255), fromIntegral (shiftR index 8), 239, 247] | y <- [0 .. 127 :: Int], x <- [0 .. 127 :: Int], let index = (y `div` 4) * 32 + x `div` 4]
  BS.writeFile (output </> "carrier.rgba") (BS.pack pixels)
