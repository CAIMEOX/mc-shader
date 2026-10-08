module Backrooms.Pack (generate, metadata) where

import Backrooms.DataPack (dataPack)
import Backrooms.Domain
import Backrooms.Json
import Backrooms.Pipeline (compile)
import Backrooms.Program (pipeline)
import Backrooms.Protocol
import Backrooms.WorldGen (validateWorldGen, worldGenAssets, worldGenMetadata, worldGenTemplates)
import Backrooms.WorldGen.Materials qualified as Materials
import Control.Monad (forM_)
import Data.Aeson qualified as A
import Data.Aeson.Key qualified as K
import Data.Aeson.KeyMap qualified as KM
import Data.ByteString qualified as BS
import Data.Char (toUpper)
import Data.List (intercalate, isPrefixOf)
import System.Directory (copyFile, createDirectoryIfMissing, doesDirectoryExist, listDirectory)
import System.FilePath (takeDirectory, (</>))

vectorJson :: V3 -> Json
vectorJson = array . map number . components

vectorGlsl :: V3 -> String
vectorGlsl p = "vec3(" ++ intercalate "," (map show (components p)) ++ ")"

metadata :: Json
metadata =
  object
    [ ("minecraft", string "26.3"),
      ("period", int period),
      ("span", int spanLength),
      ("rooms", array [object [("name", string (roomName r)), ("origin", vectorJson (origin r)), ("width", int (width r)), ("height", int (height r)), ("depth", int (depth r)), ("boxes", array (map boxJson (boxes r)))] | rid <- [Corridor, Hall], let r = room rid]),
      ("portal", object [("source_x", number (sourceX portal)), ("target_x", number (targetX portal)), ("center_z", number (centerZ portal)), ("height", number (portalHeight portal)), ("half_width", number (halfWidth portal))]),
      ("rays", array [object [("room", int (fromEnum (rayRoom ray))), ("origin", vectorJson (rayOrigin ray)), ("direction", vectorJson (rayDirection ray)), ("expected", maybe (error "Reference ray missed") hitJson (referenceHit ray))] | ray <- rayFixtures]),
      ("collision_volumes", array [object [("lower", vectorJson (lower b)), ("upper", vectorJson (upper b)), ("block", string (blockName (material b)))] | b <- collisionVolumes Corridor ++ collisionVolumes Hall]),
      ("packet_words", int packetWords)
    ]
  where
    boxJson b = object [("lower", vectorJson (lower b)), ("upper", vectorJson (upper b)), ("material", int (materialId (material b)))]
    hitJson h = array [number (hitDistance h), int (materialId (hitMaterial h)), int (fromEnum (hitRoom h))]

settings :: String
settings =
  unlines
    ( ["#ifndef BACKROOMS_SETTINGS", "#define BACKROOMS_SETTINGS", "const int CAMERA_WORDS=" ++ show cameraWords ++ ";", "const int PACKET_WORDS=" ++ show packetWords ++ ";", "const ivec2 PACKET_SIZE=ivec2(" ++ show packetWords ++ ",1);", "const uint MAGIC=" ++ show magic ++ "u;", "const float ROOM_PERIOD=" ++ show (fromIntegral period :: Double) ++ ";"]
        ++ ["const int FIELD_" ++ map (\c -> if c == '.' then '_' else toUpper c) (fieldName f) ++ "=" ++ show offset ++ ";" | (offset, f) <- fieldOffsets]
        ++ ["#endif"]
    )

geometry :: String
geometry =
  unlines
    ( ["#ifndef BACKROOMS_GEOMETRY", "#define BACKROOMS_GEOMETRY", "const vec3 HALL_ORIGIN=" ++ vectorGlsl (origin (room Hall)) ++ ";", "const float FLOOR_Y=" ++ show (fromIntegral baseY :: Double) ++ ";"]
        ++ ["const float " ++ name ++ "=" ++ show value ++ ";" | (name, value) <- [("CORRIDOR_HALF_WIDTH", fromIntegral (width (room Corridor)) / 2), ("CORRIDOR_HEIGHT", fromIntegral (height (room Corridor))), ("HALL_HALF_WIDTH", fromIntegral (width (room Hall)) / 2), ("HALL_HALF_DEPTH", fromIntegral (depth (room Hall)) / 2), ("HALL_HEIGHT", fromIntegral (height (room Hall))), ("DOOR_HALF_WIDTH", halfWidth portal), ("DOOR_HEIGHT", portalHeight portal)]]
        ++ ["const vec3 PORTAL_SHIFT=" ++ vectorGlsl (targetX portal - sourceX portal, 0, -centerZ portal) ++ ";"]
        ++ concatMap roomGeometry [Corridor, Hall]
        ++ ["const int FIXTURE_COUNT=" ++ show (length rayFixtures) ++ ";", declaration "vec3" "FIXTURE_ORIGIN" (map (vectorGlsl . rayOrigin) rayFixtures), declaration "vec3" "FIXTURE_DIRECTION" (map (vectorGlsl . rayDirection) rayFixtures), declaration "int" "FIXTURE_ROOM" (map (show . fromEnum . rayRoom) rayFixtures), "#endif"]
    )
  where
    declaration ty name values = "const " ++ ty ++ " " ++ name ++ "[" ++ show (length values) ++ "]=" ++ ty ++ "[](" ++ intercalate "," values ++ ");"
    roomGeometry rid =
      let bs = boxes (room rid); prefix = if rid == Corridor then "CORRIDOR" else "HALL"
       in ["const int " ++ prefix ++ "_BOX_COUNT=" ++ show (length bs) ++ ";", declaration "vec3" (prefix ++ "_LOWER") (map (vectorGlsl . lower) bs), declaration "vec3" (prefix ++ "_UPPER") (map (vectorGlsl . upper) bs), declaration "int" (prefix ++ "_MATERIAL") (map (show . materialId . material) bs), "const int " ++ prefix ++ "_LIGHT_COUNT=" ++ show (length (lights rid)) ++ ";", declaration "vec3" (prefix ++ "_LIGHT_LOWER") (map (vectorGlsl . lower) (lights rid)), declaration "vec3" (prefix ++ "_LIGHT_UPPER") (map (vectorGlsl . upper) (lights rid))]

carrierAssets :: [(FilePath, String)]
carrierAssets =
  [ ("assets/backrooms/models/carrier.json", render (object [("textures", object [("data", string "backrooms:block/carrier"), ("particle", string "backrooms:block/carrier")]), ("elements", array elements)])),
    ("assets/backrooms/items/carrier.json", render (object [("model", object [("type", string "minecraft:model"), ("model", string "backrooms:carrier"), ("tints", array [object [("type", string "minecraft:custom_model_data"), ("index", int i), ("default", int (0 :: Int))] | i <- [0 .. headerWords - 1]])])]))
  ]
  where
    elements = [object [("from", array (map int [0, 0, 0 :: Int])), ("to", array (map int [16, 16, 0 :: Int])), ("shade_direction_override", string "up"), ("faces", object [("south", object [("texture", string "#data"), ("uv", array (map number [fromIntegral i + 0.25, 4, fromIntegral i + 0.75, 12])), ("tintindex", int (max 0 (i - cameraWords)))])])] | i <- [0 .. packetWords - 1]]

writeAsset :: FilePath -> (FilePath, String) -> IO ()
writeAsset root (path, contents) = do
  createDirectoryIfMissing True (takeDirectory (root </> path))
  writeFile (root </> path) (contents ++ "\n")

copyTree :: FilePath -> FilePath -> IO ()
copyTree source destination = do
  createDirectoryIfMissing True destination
  entries <- listDirectory source
  forM_ entries $ \name -> do
    dir <- doesDirectoryExist (source </> name)
    if dir then copyTree (source </> name) (destination </> name) else copyFile (source </> name) (destination </> name)

replace :: String -> String -> String -> String
replace old new = go
  where
    go [] = []
    go text@(x : xs)
      | old `isPrefixOf` text = new ++ go (drop (length old) text)
      | otherwise = x : go xs

shaderSource :: FilePath -> FilePath -> IO String
shaderSource root path = readFile (root </> "shaders" </> path)

generate :: FilePath -> IO ()
generate root = do
  let out = root </> "build"; rp = out </> "resourcepack"; dp = out </> "datapack"; finishes = out </> "materialpack"
  compiled <- either fail pure (compile pipeline)
  either fail pure validateWorldGen
  forM_ ["include", "post"] $ \part -> copyTree (root </> "shaders" </> part) (rp </> "assets/backrooms/shaders" </> part)
  forM_ ["include/codec.glsl", "include/rotation.glsl", "post/copy.fsh"] $ \part -> shaderSource root part >>= \contents -> writeAsset rp ("assets/backrooms/shaders/" ++ part, contents)
  forM_ (carrierAssets ++ [("assets/backrooms/shaders/include/settings.glsl", settings), ("assets/backrooms/shaders/include/geometry.glsl", geometry), ("assets/minecraft/post_effect/end_of_frame.json", render compiled)]) (writeAsset rp)
  forM_ dataPack (writeAsset dp)
  writeAsset out ("scene.json", render metadata)
  vanillaType <- readJson (out </> "vanilla/dimension_type.json")
  vanillaBiome <- readJson (out </> "vanilla/biome.json")
  let attribute key resource = case resource of A.Object xs -> maybe (object []) id (KM.lookup (K.fromString key) xs); _ -> object []
      typeAttributes = modifyObject [("minecraft:visual/fog_color", string "#aca373"), ("minecraft:visual/sky_color", string "#aca373")] (attribute "attributes" vanillaType)
      dimensionType = modifyObject [("min_y", int (0 :: Int)), ("height", int (128 :: Int)), ("logical_height", int (128 :: Int)), ("has_skylight", bool False), ("has_ceiling", bool True), ("ambient_light", number 0.35), ("attributes", typeAttributes)] vanillaType
      spawns = object [("modifier", string "overlay"), ("argument", object [("spawn_costs", object []), ("spawns_by_category", object [])])]
      biomeAttributes = modifyObject [("minecraft:gameplay/natural_mob_spawns", spawns)] (attribute "attributes" vanillaBiome)
      biome = modifyObject [("has_precipitation", bool False), ("carvers", array []), ("features", array (replicate 11 (array []))), ("attributes", biomeAttributes)] vanillaBiome
      layer :: String -> Int -> Json
      layer block n = object [("block", string block), ("height", int n)]
      dimension = object [("type", string "backrooms:level0"), ("generator", object [("type", string "minecraft:flat"), ("settings", object [("biome", string "backrooms:level0"), ("features", bool False), ("lakes", bool False), ("structure_overrides", array []), ("layers", array [layer "minecraft:bedrock" 1, layer "minecraft:stone" (baseY - 2), layer "minecraft:brown_wool" 1, layer "minecraft:air" (128 - baseY)])])])]
  forM_ [("data/backrooms/dimension_type/level0.json", render dimensionType), ("data/backrooms/worldgen/biome/level0.json", render biome), ("data/backrooms/dimension/level0.json", render dimension)] (writeAsset dp)
  forM_ (worldGenAssets dimensionType biome) (writeAsset dp)
  forM_ worldGenTemplates $ \(path, contents) -> do
    createDirectoryIfMissing True (takeDirectory (dp </> path))
    BS.writeFile (dp </> path) contents
  writeAsset out ("worldgen.json", render worldGenMetadata)
  forM_ Materials.textures $ \texture -> do
    createDirectoryIfMissing True (out </> "materials")
    BS.writeFile (out </> "materials" </> (Materials.textureName texture ++ ".rgba")) (BS.pack (Materials.pixels texture))
  writeAsset out ("materials.json", render (array [object [("source", string ("materials/" ++ Materials.textureName texture ++ ".rgba")), ("asset", string ("assets/minecraft/textures/block/" ++ Materials.textureName texture ++ ".png")), ("width", int (Materials.textureWidth texture)), ("height", int (Materials.textureHeight texture))] | texture <- Materials.textures]))
  writeAsset finishes ("assets/minecraft/textures/block/sea_lantern.png.mcmeta", render (object [("animation", object [("frames", array [int (0 :: Int)]), ("frametime", int (1 :: Int))])]))
  forM_ ["item", "entity", "block"] $ \name -> forM_ ["vsh", "fsh"] $ \ext -> do
    original <- readFile (out </> "vanilla" </> (name ++ "." ++ ext))
    core <- shaderSource root ("core/carrier." ++ ext ++ ".inc")
    let cameraExtra = unlines ["if(index==5)BackroomsWord=wordRgb(encodeFloat24(ProjMat[3][2]));", "if(index==6){", "#ifdef RENDERPEARL_DEPTH_IS_ZERO_TO_ONE", "BackroomsWord=wordRgb(1u);", "#else", "BackroomsWord=wordRgb(0u);", "#endif", "}"]
        patch = if ext == "vsh" then replace "const vec2 corners[4]" (cameraExtra ++ "const vec2 corners[4]") core else core
    writeAsset rp ("assets/minecraft/shaders/core/" ++ name ++ "." ++ ext, replace "void main() {" patch original)
  BS.writeFile (out </> "carrier.rgba") (BS.pack (concat [[fromIntegral (x `div` 4), 0, 239, 247] | _ <- [0 .. 3 :: Int], x <- [0 .. 63 :: Int]]))
