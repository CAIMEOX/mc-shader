module Flame.Domain where

import Data.Bits (setBit, testBit)
import Data.List (elemIndex, nub, sort)
import Data.Maybe (fromMaybe)

data V3 a = V3 a a a deriving (Eq, Ord, Show)

components :: V3 a -> [a]
components (V3 x y z) = [x, y, z]

mapV3 :: (a -> b) -> V3 a -> V3 b
mapV3 f (V3 x y z) = V3 (f x) (f y) (f z)

volume :: (Num a) => V3 a -> a
volume (V3 x y z) = x * y * z

coordinates :: V3 Int -> [V3 Int]
coordinates (V3 nx ny nz) = [V3 x y z | z <- [0 .. nz - 1], y <- [0 .. ny - 1], x <- [0 .. nx - 1]]

linear :: V3 Int -> V3 Int -> Int
linear (V3 nx ny _) (V3 x y z) = x + nx * (y + ny * z)

unlinear :: V3 Int -> Int -> V3 Int
unlinear (V3 nx ny _) i = V3 (i `mod` nx) ((i `div` nx) `mod` ny) (i `div` (nx * ny))

data Half = Bottom | Top deriving (Eq, Ord, Show, Enum, Bounded)

data Facing = North | East | South | West deriving (Eq, Ord, Show, Enum, Bounded)

data Turn = Straight | InnerLeft | InnerRight | OuterLeft | OuterRight deriving (Eq, Ord, Show, Enum, Bounded)

data Stair = Stair Half Facing Turn deriving (Eq, Ord, Show)

allValues :: (Enum a, Bounded a) => [a]
allValues = [minBound .. maxBound]

stairs :: [Stair]
stairs = Stair <$> allValues <*> allValues <*> allValues

halfName :: Half -> String
halfName Bottom = "bottom"
halfName Top = "top"

facingName :: Facing -> String
facingName f = ["north", "east", "south", "west"] !! fromEnum f

turnName :: Turn -> String
turnName t = ["straight", "inner_left", "inner_right", "outer_left", "outer_right"] !! fromEnum t

stairMask :: Stair -> Int
stairMask (Stair half facing turn) = foldl mark 0 [0 .. 7]
  where
    side f i = case f `mod` 4 of
      0 -> not (testBit i 2)
      1 -> testBit i 0
      2 -> testBit i 2
      _ -> not (testBit i 0)
    mark mask i = if base || step then setBit mask i else mask
      where
        base = testBit i 1 == (half == Top)
        front = side (fromEnum facing) i
        left = side (fromEnum facing + 3) i
        right = side (fromEnum facing + 1) i
        step = case turn of
          Straight -> front
          InnerLeft -> front || left
          InnerRight -> front || right
          OuterLeft -> front && left
          OuterRight -> front && right

shapeMasks :: [Int]
shapeMasks = [0, 255, 51, 204] ++ sort (nub (map stairMask stairs))

shapeId :: Int -> Int
shapeId mask = fromMaybe (error "Collision shape absent from palette") (elemIndex mask shapeMasks)

unknownShape :: Int
unknownShape = length shapeMasks

data Config = Config
  { region :: V3 Int,
    grid :: V3 Int,
    pressureIterations :: Int,
    renderSize :: (Int, Int)
  }
  deriving (Eq, Show)

standard :: Config
standard = Config (V3 16 8 16) (V3 32 16 32) 24 (640, 360)

data Material = Inert | Wood | Foliage | Cloth deriving (Eq, Ord, Show, Enum, Bounded)

data FuelProfile = FuelProfile {fuelLoad :: Double, pyrolysisTemperature :: Double, pyrolysisRate :: Double}
  deriving (Eq, Show)

profile :: Material -> FuelProfile
profile Inert = FuelProfile 0 2000 0
profile Wood = FuelProfile 1 540 0.085
profile Foliage = FuelProfile 0.3 470 0.13
profile Cloth = FuelProfile 0.8 570 0.065
