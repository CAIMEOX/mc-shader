module Escher.Pack (generate) where

import Control.Monad (forM_)
import Data.ByteString qualified as BS
import Data.Char (toUpper)
import Data.List (intercalate, isPrefixOf)
import Escher.DataPack
import Escher.Folding qualified as F
import Escher.Folding.Scene qualified as Folding
import Escher.Json
import Escher.Pipeline
import Escher.Program (pipeline)
import Escher.Protocol
import Escher.Quality
import Escher.Scene
import System.Directory (copyFile, createDirectoryIfMissing, doesDirectoryExist, listDirectory)
import System.FilePath (takeDirectory, (</>))

settings :: String
settings =
  unlines $
    ["#ifndef ESCHER_SETTINGS", "#define ESCHER_SETTINGS", "const int PACKET_WORDS=" ++ show packetWords ++ ";", "const ivec2 PACKET_SIZE=ivec2(" ++ show packetWords ++ ",1);", "const uint MAGIC=0x455343u;"]
      ++ ["const int FIELD_" ++ map (\c -> if c == '.' then '_' else toUpper c) (fieldName f) ++ "=" ++ show offset ++ ";" | (offset, f) <- fieldOffsets]
      ++ ["#endif"]

assets :: [(FilePath, String)]
assets =
  [ ("assets/escher/models/carrier.json", render $ object [("textures", object [("data", string "escher:block/carrier"), ("particle", string "escher:block/carrier")]), ("elements", array elements)]),
    ("assets/escher/items/carrier.json", render $ object [("model", object [("type", string "minecraft:model"), ("model", string "escher:carrier"), ("tints", array tints)])])
  ]
  where
    elements =
      [ object
          [ ("from", array (map int [0 :: Int, 0, 0])),
            ("to", array (map int [16 :: Int, 16, 0])),
            ("shade_direction_override", string "up"),
            ("faces", object [("south", object [("texture", string "#data"), ("uv", array (map number [fromIntegral i + 0.25, 4, fromIntegral i + 0.75, 12])), ("tintindex", int (max 0 (i - 5)))])])
          ]
      | i <- [0 .. packetWords - 1]
      ]
    tints = [object [("type", string "minecraft:custom_model_data"), ("index", int i), ("default", int (0 :: Int))] | i <- [0 .. headerWords - 1]]

writeAsset :: FilePath -> (FilePath, String) -> IO ()
writeAsset root (path, contents) = do
  createDirectoryIfMissing True (takeDirectory (root </> path))
  writeFile (root </> path) (contents ++ "\n")

copyTree :: FilePath -> FilePath -> IO ()
copyTree source destination = do
  createDirectoryIfMissing True destination
  entries <- listDirectory source
  forM_ entries $ \name -> do
    directory <- doesDirectoryExist (source </> name)
    if directory then copyTree (source </> name) (destination </> name) else copyFile (source </> name) (destination </> name)

replaceMain :: String -> String -> Either String String
replaceMain patch = go
  where
    needle = "void main() {"
    go [] = Left "Core shader entry point was not found"
    go text@(x : xs)
      | needle `isPrefixOf` text = Right (patch ++ drop (length needle) text)
      | otherwise = (x :) <$> go xs

generate :: FilePath -> IO ()
generate root = do
  let output = root </> "build"; rp = output </> "resourcepack"; dp = output </> "datapack"
  compiled <- either fail pure (compile pipeline)
  forM_ ["include", "post"] $ \part -> copyTree (root </> "shaders" </> part) (rp </> "assets/escher/shaders" </> part)
  forM_
    ( assets
        ++ [ ("assets/minecraft/post_effect/end_of_frame.json", render compiled),
             ("assets/escher/shaders/include/settings.glsl", settings),
             ("assets/escher/shaders/include/scene.glsl", glsl gallery),
             ("assets/escher/shaders/include/folding_scene.glsl", glslNamed "foldingScene" Folding.building),
             ( "assets/escher/shaders/include/folding_settings.glsl",
               unlines
                 ( ["#ifndef ESCHER_FOLDING_SETTINGS", "#define ESCHER_FOLDING_SETTINGS"]
                     ++ [ "const float FOLD_" ++ name ++ "=" ++ show value ++ ";"
                        | (name, value) <-
                            [ ("RADIUS", F.radius),
                              ("HEIGHT", F.height),
                              ("WIDTH", F.width),
                              ("TURN", F.turn),
                              ("HALF_DEPTH", F.halfDepth),
                              ("BALL_RADIUS", F.ballRadius),
                              ("BALL_SPACING", F.ballSpacing),
                              ("BALL_SPEED", F.ballSpeed),
                              ("MORPH_SECONDS", F.morphSeconds)
                            ]
                        ]
                     ++ ["#endif"]
                 )
             )
           ]
    )
    (writeAsset rp)
  forM_ dataPack (writeAsset dp)
  writeAsset
    output
    ( "escher-build.json",
      render $
        object
          [ ("minecraft", string "26.3"),
            ("renderer", string "analytic gallery"),
            ("packet_pixels", int packetWords),
            ("payload_bits", int (sum (map fieldWidth header))),
            ("room_length", int (18 :: Int)),
            ("scenes", array [object [("name", string "gallery"), ("period", int (18 :: Int))], object [("name", string "folding"), ("period", int F.physicalPeriod)]]),
            ("collision_blocks_per_room", int (length voxels)),
            ("qualities", array [object [("name", string (qualityName q)), ("steps", int (traceSteps q)), ("extent", case renderExtent q of Fixed w h -> array [int w, int h]; Screen -> string "screen")] | q <- qualities]),
            ("fields", array [object [("name", string (fieldName f)), ("bits", int (fieldWidth f)), ("offset", int offset), ("bias", int (fieldBias f))] | (offset, f) <- fieldOffsets])
          ]
    )
  forM_ ["item", "entity", "block"] $ \name -> forM_ ["vsh", "fsh"] $ \ext -> do
    original <- readFile (output </> "vanilla" </> (name ++ "." ++ ext))
    patch <- readFile (root </> "shaders/core" </> ("carrier." ++ ext ++ ".inc"))
    combined <- either fail pure (replaceMain patch original)
    writeAsset rp ("assets/minecraft/shaders/core/" ++ name ++ "." ++ ext, combined)
  BS.writeFile (output </> "carrier.rgba") (BS.pack (concat [[fromIntegral (x `div` 4), 0, 239, 247] | _ <- [0 .. 3 :: Int], x <- [0 .. 63 :: Int]]))
  writeAsset output ("scene-summary.txt", intercalate "\n" ["Analytic planar gallery", "Collision blocks per room: " ++ show (length voxels)])
