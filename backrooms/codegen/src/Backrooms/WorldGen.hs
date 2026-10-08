module Backrooms.WorldGen
  ( densities,
    validateWorldGen,
    worldGenAssets,
    worldGenMetadata,
    worldGenTemplates,
    sampleDensity,
  )
where

import Backrooms.Json
import Backrooms.Structure.Nbt
import Backrooms.WorldGen.Block qualified as B
import Backrooms.WorldGen.Density
import Backrooms.WorldGen.Floors qualified as Floors
import Backrooms.WorldGen.Landmark qualified as L
import Backrooms.WorldGen.Materials (Surface (..), surfaceBlock)
import Backrooms.WorldGen.Runtime qualified as R
import Backrooms.WorldGen.Vertical qualified as V
import Data.ByteString qualified as BS
import Data.List (nub, sort)
import Data.Map.Strict qualified as M

densities :: [(String, Density)]
densities = R.rules

sampleDensity :: NoiseSource -> (Double, Double, Double) -> String -> Double
sampleDensity = R.sample

validateWorldGen :: Either String ()
validateWorldGen = R.validate

worldGenMetadata :: Json
worldGenMetadata =
  object
    [ ("dimension", string "backrooms:interior"),
      ("architecture", string "runtime density partitions"),
      ("layout_profile", string "runtime_level0"),
      ("region_size", int R.regionSize),
      ("floor_y", int (64 :: Int)),
      ("walk_levels", array (map int Floors.walkLevels)),
      ("floor_pitch", int Floors.pitch),
      ("landmark_spacing", int V.landmarkSpacing),
      ("density_count", int (length densities)),
      ("room_families", array [object [("id", int index), ("name", string name)] | (index, name) <- R.furnitureKinds]),
      ("layout_kinds", array [object [("id", int index), ("name", string name)] | (index, name) <- R.layoutKinds]),
      ("material_masks", array [object [("mask", string key), ("state", blockState material)] | (key, material) <- R.materialMasks]),
      ("vertical_cores", array [object [("id", int index), ("name", string name), ("size", int (V.size kind)), ("stair_path", array (map point (V.stairPath kind))), ("ladder", maybe (object []) connection (V.ladderRoute kind))] | (index, name) <- V.kindNames, let kind = toEnum index]),
      ("template_count", int (length L.templates)),
      ("palette", object [("id", string "level0"), ("wall", string (surfaceBlock Wallpaper)), ("floor", string (surfaceBlock Carpet)), ("ceiling", string (surfaceBlock Ceiling)), ("light", string (surfaceBlock Luminaire))]),
      ("landmarks", array (map landmarkJson L.templates))
    ]
  where
    point (x, y, z) = array (map int [x, y, z])
    connection (lower@(x, _, z), upper@(a, _, b)) = object [("lower", point lower), ("upper", point upper), ("yaw", number (atan2 (fromIntegral (x - a)) (fromIntegral (b - z)) * 180 / pi))]
    landmarkJson lm =
      let (a, b, c, d) = L.bounds lm
       in object
            [ ("id", string ("backrooms:interior/" ++ L.name (L.kind lm))),
              ("kind", string (L.name (L.kind lm))),
              ("size", point (L.templateDimensions lm)),
              ("bounds", array (map int [a, b, c, d])),
              ("minimum_y", int (L.minimumY lm)),
              ("maximum_floor_y", int (maximum (L.floorLevels lm))),
              ("floor_offset", int (negate (L.minimumY lm))),
              ("required", array (map point (L.requiredPoints lm))),
              ("views", array [object [("name", string label), ("point", point p), ("yaw", number yaw), ("pitch", number pitch)] | (label, p, yaw, pitch) <- L.viewPoints lm]),
              ("stairs", array (map connection (L.stairEndpoints lm))),
              ("ladders", array (map connection (L.ladderRoutes lm))),
              ("falls", array (map point (L.fallPoints lm)))
            ]

worldGenAssets :: Json -> Json -> [(FilePath, String)]
worldGenAssets dimensionType biome =
  map
    (\(name, value) -> ("data/backrooms/" ++ name ++ ".json", render value))
    ( [ ("dimension/interior", dimension),
        ("dimension_type/interior", dimensionType),
        ("dimension/lobby", dimension),
        ("dimension_type/lobby", dimensionType),
        ("worldgen/biome/interior", biome),
        ("worldgen/noise_settings/interior", settings),
        ("worldgen/material_rule/interior", materials),
        ("worldgen/structure/interior", structure),
        ("worldgen/structure_set/interior", placement),
        ("worldgen/template_pool/interior/landmarks", pool)
      ]
        ++ [("worldgen/density_function/interior/" ++ key, encodeDensity value) | (key, value) <- densities]
        ++ [("worldgen/noise/interior/" ++ name, object [("base_octave", int (-4 :: Int)), ("octave_count", int (1 :: Int)), ("base_amplitude", number 1), ("normalize", bool True)]) | name <- R.noiseNames]
    )
  where
    dimension = object [("type", string "backrooms:interior"), ("generator", object [("type", string "minecraft:noise"), ("settings", string "backrooms:interior"), ("biome_source", object [("type", string "minecraft:fixed"), ("biome", string "backrooms:interior")])])]
    settings =
      object
        [ ("noise", object [("min_y", int (0 :: Int)), ("height", int (128 :: Int))]),
          ("default_block", string "minecraft:stone"),
          ("default_fluid", string "minecraft:air"),
          ("sea_level", int (0 :: Int)),
          ("disable_mob_generation", bool True),
          ("legacy_random_source", bool False),
          ("spawn_target", array []),
          ("noise_router", object ([(name, int (0 :: Int)) | name <- ["temperature", "vegetation", "continents", "erosion", "depth", "ridges"]] ++ [("chunk_surface_level", int (Floors.highestY + 10)), ("final_density", encodeDensity (Ref "solid"))])),
          ("material_rule", string "backrooms:interior")
        ]
    block name = object [("type", string "minecraft:block"), ("result_state", string name)]
    -- Boolean density masks make this native rule select a single material.
    -- All three outcomes use the same block; density zero falls through.
    masked key material = object [("type", string "minecraft:ore_vein"), ("ore_block", blockState material), ("raw_ore_block", blockState material), ("filler_block", blockState material), ("raw_ore_chance", number 0), ("density", encodeDensity (Ref key)), ("richness", number 0), ("filler_gap", number 1)]
    materials =
      object
        [ ("type", string "minecraft:sequence"),
          ( "sequence",
            array
              ( map (uncurry masked) R.materialMasks
                  ++ [block "minecraft:stone"]
              )
          )
        ]
    structure = object [("type", string "minecraft:jigsaw"), ("biomes", string "backrooms:interior"), ("step", string "surface_structures"), ("spawn_overrides", object []), ("terrain_adaptation", string "none"), ("start_pool", string "backrooms:interior/landmarks"), ("start_jigsaw_name", string "backrooms:landmark_anchor"), ("size", int (1 :: Int)), ("start_height", object [("type", string "minecraft:constant"), ("value", object [("absolute", int (64 :: Int))])]), ("use_expansion_hack", bool False), ("max_distance_from_center", int (80 :: Int))]
    placement = object [("structures", array [object [("structure", string "backrooms:interior"), ("weight", int (1 :: Int))]]), ("placement", object [("type", string "minecraft:random_spread"), ("spacing", int (V.landmarkSpacing `div` 16)), ("separation", int (V.landmarkSpacing `div` 16 - 1)), ("salt", int (20261007 :: Int))])]
    pool =
      object
        [ ("fallback", string "minecraft:empty"),
          ( "elements",
            array
              ( object [("weight", int (4 :: Int)), ("element", object [("element_type", string "minecraft:empty_pool_element")])]
                  : [object [("weight", int (1 :: Int)), ("element", object [("element_type", string "minecraft:single_pool_element"), ("location", string ("backrooms:interior/" ++ L.name (L.kind lm))), ("processors", string "minecraft:empty"), ("projection", string "rigid")])] | lm <- L.templates]
              )
          )
        ]

blockState :: B.BlockState -> Json
blockState state
  | null (B.properties state) = string (B.blockName state)
  | otherwise = object [("id", string (B.blockName state)), ("properties", object [(key, string value) | (key, value) <- B.properties state])]

worldGenTemplates :: [(FilePath, BS.ByteString)]
worldGenTemplates = [("data/backrooms/structure/interior/" ++ L.name (L.kind lm) ++ ".nbt.raw", encodeRoot (template lm)) | lm <- L.templates]
  where
    ints :: [Int] -> Tag
    ints values = ListTag 3 (map (IntTag . fromIntegral) values)
    template lm =
      let entries = L.templateBlocks lm
          anchorState = B.BlockState "minecraft:jigsaw" [("orientation", "north_up")]
          palette = sort (nub (anchorState : map snd entries))
          states = M.fromList (zip palette [0 :: Int ..])
          paletteTag state = CompoundTag (("id", StringTag (B.blockName state)) : [("properties", CompoundTag [(key, StringTag value) | (key, value) <- B.properties state]) | not (null (B.properties state))])
          anchor = CompoundTag [("id", StringTag "minecraft:jigsaw"), ("name", StringTag "backrooms:landmark_anchor"), ("target", StringTag "minecraft:empty"), ("pool", StringTag "minecraft:empty"), ("joint", StringTag "aligned"), ("final_state", StringTag "minecraft:brown_wool")]
          voxel ((x, y, z), state) =
            let isAnchor = (x, y, z) == (2, 0, 2); placed = if isAnchor then anchorState else state
             in CompoundTag ([("pos", ints [x, y - L.minimumY lm, z]), ("state", IntTag (fromIntegral (states M.! placed)))] ++ [("nbt", anchor) | isAnchor])
          (w, h, d) = L.templateDimensions lm
       in CompoundTag [("DataVersion", IntTag 5023), ("size", ints [w, h, d]), ("entities", ListTag 10 []), ("palette", ListTag 10 (map paletteTag palette)), ("blocks", ListTag 10 (map voxel entries))]
