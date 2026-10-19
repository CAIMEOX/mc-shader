module Manifold.Pack (generate) where

import Control.Monad (forM_, when)
import Data.ByteString qualified as BS
import Data.Char (toUpper)
import Data.List (isPrefixOf)
import Manifold.DataPack qualified as DataPack
import Manifold.Gravity qualified as Gravity
import Manifold.Joinery qualified as Joinery
import Manifold.Joinery.Render qualified as JoineryRender
import Manifold.Json
import Manifold.Messages qualified as Messages
import Manifold.Objects qualified as Objects
import Manifold.Pipeline
import Manifold.Program
import Manifold.Protocol
import Manifold.Scene qualified as Scene
import Manifold.Stage qualified as Stage
import Manifold.ThreeRings qualified as Rings
import System.Directory (copyFile, createDirectoryIfMissing, doesDirectoryExist, listDirectory, removeFile)
import System.FilePath (takeDirectory, (</>))

write :: FilePath -> (FilePath, String) -> IO ()
write root (path, content) = do
  createDirectoryIfMissing True (takeDirectory (root </> path))
  writeFile (root </> path) (content ++ "\n")

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
  either fail pure (Joinery.validateShapes Joinery.rods)
  either fail pure (Objects.validateDefinitions Rings.scene Rings.cubes)
  either fail pure (Scene.validateCircuits Rings.scene (map Objects.cubeId Rings.cubes) Rings.circuits)
  forM_ [(Play, "resourcepack"), (Diagnostic, "resourcepack-test")] $ \(profile, name) -> generateProfile root profile name

generateProfile :: FilePath -> RenderProfile -> String -> IO ()
generateProfile root profile packName = do
  let output = root </> "build"; rp = output </> packName; dp = output </> "datapack"
  compiled <- either fail pure (compile (pipeline profile))
  forM_ Messages.resources (write rp)
  forM_ ["include", "post"] $ \part -> copyTree (root </> "shaders" </> part) (rp </> "assets/manifold/shaders" </> part)
  when (profile == Play) $ removeFile (rp </> "assets/manifold/shaders/post/probe.fsh")
  let settings =
        unlines $
          [ "#ifndef MANIFOLD_SETTINGS",
            "#define MANIFOLD_SETTINGS",
            "const int PACKET_WORDS=" ++ show packetWords ++ ";",
            "const int OBJECT_WORD_OFFSET=" ++ show (22 + headerWords) ++ ";",
            "const int OBJECT_COUNT=" ++ show (length Rings.cubes) ++ ";",
            "const int SOCKET_COUNT=" ++ show (length Rings.sockets) ++ ";",
            "const uint OBJECT_MAGIC=0x52494eu;",
            "const ivec2 PACKET_SIZE=ivec2(" ++ show packetWords ++ ",1);",
            "const uint MAGIC=0x4d414eu;"
          ]
            ++ ["const int FIELD_" ++ map (\c -> if c == '.' then '_' else toUpper c) (fieldName f) ++ "=" ++ show offset ++ ";" | (offset, f) <- fieldOffsets]
            ++ ["#endif"]
      elements indices firstTint =
        [ object
            [ ("from", array (map int [0 :: Int, 0, 0])),
              ("to", array (map int [16 :: Int, 16, 0])),
              ("shade_direction_override", string "up"),
              ( "faces",
                object
                  [ ( "south",
                      object
                        [ ("texture", string "#data"),
                          ("uv", array (map number [(fromIntegral i + 0.25) * 16 / fromIntegral packetWords, 4, (fromIntegral i + 0.75) * 16 / fromIntegral packetWords, 12])),
                          ("tintindex", int (max 0 (i - firstTint)))
                        ]
                    )
                  ]
              )
            ]
        | i <- indices
        ]
      tints count = [object [("type", string "minecraft:custom_model_data"), ("index", int i), ("default", int (0 :: Int))] | i <- [0 .. count - 1]]
  forM_
    [ ("assets/minecraft/post_effect/end_of_frame.json", render compiled),
      ("assets/manifold/shaders/include/settings.glsl", settings),
      ("assets/manifold/shaders/include/gravity_settings.glsl", Gravity.glslSettings),
      ("assets/manifold/shaders/include/stage_scene.glsl", Stage.glslScene),
      ("assets/manifold/shaders/include/rings_scene.glsl", Rings.glslScene),
      ("assets/manifold/shaders/include/joinery_scene.glsl", JoineryRender.glsl),
      ("assets/manifold/models/carrier.json", render $ object [("textures", object [("data", string "manifold:block/carrier"), ("particle", string "manifold:block/carrier")]), ("elements", array (elements [0 .. 21 + headerWords] 22))]),
      ("assets/manifold/items/carrier.json", render $ object [("model", object [("type", string "minecraft:model"), ("model", string "manifold:carrier"), ("tints", array (tints headerWords))])]),
      ("assets/manifold/models/object_bank.json", render $ object [("textures", object [("data", string "manifold:block/carrier"), ("particle", string "manifold:block/carrier")]), ("elements", array (elements [22 + headerWords .. packetWords - 1] (22 + headerWords)))]),
      ("assets/manifold/items/object_bank.json", render $ object [("model", object [("type", string "minecraft:model"), ("model", string "manifold:object_bank"), ("tints", array (tints objectWords))])])
    ]
    (write rp)
  when (profile == Play) $ forM_ DataPack.resources (write dp)
  forM_ ["item", "entity", "block"] $ \name -> forM_ ["vsh", "fsh"] $ \ext -> do
    original <- readFile (output </> "vanilla" </> (name ++ "." ++ ext))
    patch <- readFile (root </> "shaders/core" </> ("carrier." ++ ext ++ ".inc"))
    combined <- either fail pure (replaceMain patch original)
    write rp ("assets/minecraft/shaders/core/" ++ name ++ "." ++ ext, combined)
  when (profile == Play) $ BS.writeFile (output </> "carrier.rgba") (BS.pack (concat [[fromIntegral ((x `div` 4) `mod` 256), fromIntegral (x `div` 1024), 239, 247] | _ <- [0 .. 3 :: Int], x <- [0 .. 4 * packetWords - 1]]))
  write
    output
    ( "manifold-build.json",
      render $
        object
          [ ("minecraft", string "26.3"),
            ("renderer", string "periodic colonnade"),
            ("packet_pixels", int packetWords),
            ("payload_bits", int (sum (map fieldWidth header))),
            ("header_words", int headerWords),
            ("object_words", int objectWords),
            ("joinery_route", array [object [("rod", int (Joinery.slideRod step)), ("down", array (map int (Gravity.components (Joinery.slideDirection step))))] | step <- Joinery.assemblyRoute]),
            ("joinery_envelopes", array [object [("lo", array (map int (Gravity.components (Gravity.scale 4 lo)))), ("hi", array (map int (Gravity.components (Gravity.add (Gravity.scale 4 hi) (3, 3, 3)))))] | rod <- Joinery.rods, let (lo, hi) = Joinery.rodBounds rod]),
            ("joinery_initial", array [array (map int (Gravity.components p)) | p <- Joinery.initial]),
            ("joinery_solids", array [object [("rod", int (Joinery.rodId rod)), ("lo", array (map int (Gravity.components (Stage.boxLo b)))), ("hi", array (map int (Gravity.components (Stage.boxHi b))))] | rod <- Joinery.rods, b <- Joinery.boxes rod]),
            ("frames", array [array [array (map int (Gravity.components v)) | v <- [right, up, forward]] | (right, up, forward) <- Gravity.frames]),
            ("protocol_fields", array [object [("name", string (fieldName f)), ("offset", int offset), ("width", int (fieldWidth f)), ("bias", int (fieldBias f))] | (offset, f) <- fieldOffsets]),
            ("period", int (Gravity.period `div` Gravity.unit)),
            ("collision_primitives", int (length Gravity.beams)),
            ("rings_solids", array [object [("lo", array (map (number . subtract 0.5 . fromIntegral) (Gravity.components (Stage.boxLo box)))), ("hi", array (map (number . (+ 0.5) . fromIntegral) (Gravity.components (Stage.boxHi box)))), ("channel", int (maybe (-1) id (Scene.solidChannel solid)))] | solid <- Rings.solids, let box = Scene.solidBox solid])
          ]
    )
