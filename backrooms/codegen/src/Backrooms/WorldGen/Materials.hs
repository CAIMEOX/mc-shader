module Backrooms.WorldGen.Materials
  ( Surface (..),
    surfaceBlock,
    Texture (..),
    textures,
  )
where

import Data.Word (Word8)

data Surface = Wallpaper | Carpet | Ceiling | Luminaire deriving (Eq, Ord, Enum, Bounded, Show)

surfaceBlock :: Surface -> String
surfaceBlock surface =
  "minecraft:" ++ case surface of
    Wallpaper -> "end_stone"
    Carpet -> "brown_wool"
    Ceiling -> "white_concrete"
    Luminaire -> "sea_lantern"

data Texture = Texture
  { textureName :: String,
    textureWidth :: Int,
    textureHeight :: Int,
    pixels :: [Word8]
  }
  deriving (Eq, Show)

textures :: [Texture]
textures =
  [ texture "end_stone" wallpaper,
    texture "brown_wool" carpet,
    texture "white_concrete" ceilingTile,
    texture "sea_lantern" luminaire
  ]
  where
    texture name paint = Texture name 64 64 (concat [paint x y ++ [255] | y <- [0 .. 63], x <- [0 .. 63]])
    grain x y = (x * 73 + y * 151 + x * y * 19) `mod` 9 - 4
    rgb :: (Int, Int, Int) -> Int -> [Word8]
    rgb (r, g, b) shade = map (fromIntegral . max 0 . min 255 . (+ shade)) [r, g, b]
    wallpaper x y =
      let u = x `mod` 16 - 8
          v = y `mod` 32 - 16
          stem = abs u <= 0
          leaf = abs (abs u * 3 + abs (abs v - 7) - 10) <= 1 && abs u >= 2 && abs v <= 13
          weave = if x `mod` 2 == y `mod` 2 then 1 else 0
          ink = if stem || leaf then -12 else 0
       in rgb (204, 190, 125) (grain x y `div` 2 + ink + weave)
    carpet x y =
      let tuft = (x * 17 + y * 43 + (x `div` 4) * (y `div` 3) * 11) `mod` 15 - 7
          fiber = if (x + 2 * y) `mod` 5 == 0 then 4 else 0
       in rgb (139, 124, 82) (tuft + fiber)
    ceilingTile x y =
      let seam = x < 1 || y < 1
          fleck = if (x * 11 + y * 31) `mod` 47 < 2 then -9 else 0
       in rgb (208, 206, 187) (if seam then -23 else grain x y `div` 3 + fleck)
    luminaire x y
      | x < 3 || x > 60 || y < 3 || y > 60 = rgb (121, 122, 106) (grain x y `div` 2)
      | y `mod` 16 < 1 = rgb (219, 220, 201) 0
      | otherwise = rgb (245, 244, 218) (grain x y `div` 4)
