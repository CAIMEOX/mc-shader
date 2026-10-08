module Backrooms.WorldGen.Landmark
  ( Kind (..),
    Landmark (..),
    Point,
    name,
    bounds,
    inFootprint,
    minimumY,
    floorLevels,
    at,
    placements,
    requiredPoints,
    viewPoints,
    stairEndpoints,
    ladderRoutes,
    fallPoints,
    templates,
    templateDimensions,
    templateBlocks,
  )
where

import Backrooms.WorldGen.Block
import Backrooms.WorldGen.Materials (Surface (..), surfaceBlock)
import Data.List (nub, sort)

type Point = (Int, Int, Int)

data Kind = Shaft | Pitfalls | SplitAtrium deriving (Eq, Ord, Show)

data Landmark = Landmark {kind :: Kind, originX :: Int, originZ :: Int} deriving (Eq, Show)

templates :: [Landmark]
templates = [Landmark feature 4 4 | feature <- [Shaft, Pitfalls, SplitAtrium]]

templateDimensions :: Landmark -> (Int, Int, Int)
templateDimensions lm = let (_, _, c, d) = bounds lm in (c + 4, 24 - minimumY lm, d + 4)

-- Three circulation collars connect the landmark to the surrounding floors.
-- A backed ladder joins their landings; the upper interior is supplied by the
-- runtime room generator.
templateBlocks :: Landmark -> [(Point, BlockState)]
templateBlocks lm = [(p, state) | let (w, _, depth) = templateDimensions lm, x <- [0 .. w - 1], z <- [0 .. depth - 1], y <- [minimumY lm .. 23], let p = (x, y, z), Just state <- [voxel p]]
  where
    (a, b, c, d) = bounds lm
    voxel p@(x, y, z)
      | not (inFootprint lm (x, z)) = if y < -12 then Nothing else Just (collar p)
      | y == 12 || y == -12 && bodyMinimumY lm > -12 = Just (surface Carpet)
      | entrance x z && any (\f -> f >= bodyMinimumY lm && y >= f && y <= f + 3) [-12, 0] = Just (if y `elem` [-12, 0] then surface Carpet else air)
      | Just value <- at lm p = Just value
      | y >= 0 && y <= 11 = Just (if y == 0 then surface Carpet else if y >= 7 then surface Ceiling else surface Wallpaper)
      | otherwise = Nothing
    collar (x, y, z)
      | (x, z) == (2, 6) && y >= -11 && y <= 12 = BlockState "minecraft:ladder" [("facing", "east"), ("waterlogged", "false")]
      | (x, z) == (1, 6) && y >= -11 && y <= 12 = surface Wallpaper
      | h == 0 = surface Carpet
      | h == 4 && ((x == 2 || x == c + 1) && z `mod` 8 `elem` [2, 3, 4] || (z == 2 || z == d + 1) && x `mod` 8 `elem` [2, 3, 4]) = surface Luminaire
      | h >= 4 = surface Ceiling
      | otherwise = air
      where
        h = y `mod` 12
    entrance x z = ((x == a || x == c - 1) && abs (z - (b + d) `div` 2) <= 1) || ((z == b || z == d - 1) && abs (x - (a + c) `div` 2) <= 1)

name :: Kind -> String
name Shaft = "shaft"
name Pitfalls = "pitfalls"
name SplitAtrium = "split_atrium"

dimensions :: Landmark -> (Int, Int)
dimensions lm = case kind lm of Shaft -> (42, 38); Pitfalls -> (38, 34); SplitAtrium -> (40, 36)

bounds :: Landmark -> (Int, Int, Int, Int)
bounds lm = let (w, d) = dimensions lm in (originX lm, originZ lm, originX lm + w, originZ lm + d)

inFootprint :: Landmark -> (Int, Int) -> Bool
inFootprint lm (x, z) = let (a, b, c, d) = bounds lm in x >= a && x < c && z >= b && z < d

minimumY :: Landmark -> Int
minimumY lm = min (-12) (bodyMinimumY lm)

bodyMinimumY :: Landmark -> Int
bodyMinimumY lm = case kind lm of Shaft -> -49; Pitfalls -> -13; SplitAtrium -> -8

floorLevels :: Landmark -> [Int]
floorLevels lm = sort (nub ([-12, 0, 12] ++ case kind lm of Shaft -> [-48, -36, -24, -12, 0]; Pitfalls -> [-12, 0]; SplitAtrium -> [-8, -4, 0, 4]))

surface :: Surface -> BlockState
surface = plain . surfaceBlock

local :: Landmark -> Point -> Point
local lm (x, y, z) = (x - originX lm, y, z - originZ lm)

world :: Landmark -> Point -> Point
world lm (x, y, z) = (x + originX lm, y, z + originZ lm)

-- Nothing delegates to the sector. Explicit air excavates the noise foundation.
at :: Landmark -> Point -> Maybe BlockState
at lm p@(x, y, z)
  | not (inFootprint lm (x, z)) || y < bodyMinimumY lm || y > 11 = Nothing
  | y >= 0 && boundary = Nothing
  | otherwise = Just (case kind lm of Shaft -> shaft (u, y, v); Pitfalls -> pitfalls (u, y, v); SplitAtrium -> atrium (u, y, v))
  where
    (u, _, v) = local lm p
    (w, d) = dimensions lm
    boundary = u == 0 || v == 0 || u == w - 1 || v == d - 1

shaftHole :: Int -> Int -> Bool
shaftHole u v = u >= 11 && u < 35 && v >= 7 && v < 31

shaftRim :: Int -> Int -> Bool
shaftRim u v = ((u == 10 || u == 35) && v >= 6 && v <= 31) || ((v == 6 || v == 31) && u >= 10 && u <= 35)

shaft :: Point -> BlockState
shaft p@(u, y, v)
  | y == (-49) = surface Carpet
  | y == (-48) = if hole then water else surface Carpet
  | y >= 7 = if y == 7 && lamp then surface Luminaire else surface Ceiling
  | boundary = surface Wallpaper
  | Just step <- staircase 2 6 [0, -12, -24, -36] p = step
  | hole = air
  | y == 0 = surface Carpet
  | y > 0 = gallery 0
  | otherwise = gallery (12 * (y `div` 12))
  where
    hole = shaftHole u v
    boundary = u == 0 || u == 41 || v == 0 || v == 37
    lamp = (u `elem` [6, 7, 8, 37, 38, 39] && v `elem` [10, 22, 32]) || (v `elem` [3, 34] && u `elem` [15, 16, 17, 27, 28, 29])
    gallery floorLevel
      | y == floorLevel = surface Carpet
      | shaftRim u v && y <= floorLevel + (if floorLevel == 0 then 6 else 4) && floorLevel > (-48) && (u + v) `mod` 7 == 0 = surface Wallpaper
      | y == floorLevel + 1 && floorLevel > (-48) && shaftRim u v = fence shaftRim u v
      | y >= floorLevel + 5 && floorLevel < 0 = if y == floorLevel + 5 && lamp then surface Luminaire else surface Ceiling
      | otherwise = air

fence :: (Int -> Int -> Bool) -> Int -> Int -> BlockState
fence rail u v =
  BlockState
    "minecraft:oak_fence"
    [("east", flag (rail (u + 1) v)), ("north", flag (rail u (v - 1))), ("south", flag (rail u (v + 1))), ("west", flag (rail (u - 1) v)), ("waterlogged", "false")]
  where
    flag True = "true"; flag False = "false"

pitMouth :: Int -> Int -> Bool
pitMouth u v = any (\x -> u >= x && u < x + 3) [5, 11, 17, 23] && any (\z -> v >= z && v < z + 3) [4, 10, 16]

pitfalls :: Point -> BlockState
pitfalls p@(u, y, v)
  | y == (-13) = surface Carpet
  | y == (-12) = if pitMouth u v then water else surface Carpet
  | y >= 7 = if y == 7 && lamp then surface Luminaire else surface Ceiling
  | boundary = surface Wallpaper
  | Just step <- staircase 30 4 [0] p = step
  | y == 0 = if bridge then plain "minecraft:oak_planks" else if pitMouth u v then air else surface Carpet
  | y > 0 = air
  | pitMouth u v = air
  | y >= (-8) = if y == (-8) && lamp then surface Luminaire else if y == (-8) then surface Ceiling else surface Carpet
  | u `elem` [9, 15, 21, 27] && v `elem` [8, 14, 20] = surface Wallpaper
  | otherwise = air
  where
    boundary = u == 0 || u == 37 || v == 0 || v == 33
    bridge = u >= 17 && u < 20 && v == 11
    lamp = (u `mod` 6 `elem` [2, 3, 4]) && v `elem` [2, 8, 14, 20, 28]

-- Each tuple describes a west-facing ladder and its east-side backing wall.
-- The top opens onto a deck so forward movement completes the climb.
atriumLadders :: [(Int, Int, Int, Int)]
atriumLadders = [(16, 1, 6, 4), (28, -7, 19, 4)]

atrium :: Point -> BlockState
atrium (u, y, v)
  | y == 11 = if ceilingLamp then surface Luminaire else surface Ceiling
  | u == 0 || u == 39 || v == 0 || v == 35 = surface Wallpaper
  | ladderCell = BlockState "minecraft:ladder" [("facing", "west"), ("waterlogged", "false")]
  | solidWall y u v = surface Wallpaper
  | y == terrain && northSteps = stair "north"
  | y == terrain && westSteps = stair "west"
  | y <= terrain = if retainingLamp then surface Luminaire else if y == terrain then surface Carpet else surface Wallpaper
  | (y == 0 || y == 4) && floating y u v = surface Carpet
  | (y == 1 || y == 5) && railing (y - 1) u v = fence (\x z -> railing (y - 1) x z || solidWall y x z) u v
  | otherwise = air
  where
    inside a b c d x z = x >= a && x < c && z >= b && z < d
    northSteps = inside 7 7 10 11 u v
    westSteps = inside 11 22 15 25 u v
    terrain
      | northSteps = 7 - v
      | westSteps = 7 - u
      | inside 6 8 12 28 u v || inside 12 8 18 12 u v = -4
      | inside 6 8 32 28 u v = -8
      | otherwise = 0
    floating level x z
      | level == 0 = inside 26 13 33 17 x z
      | otherwise = inside 16 4 38 8 x z || inside 32 8 38 30 x z || inside 26 17 33 23 x z
    deck level x z = floating level x z || level == 0 && not (inside 6 8 32 28 x z)
    railing level x z =
      deck level x z
        && any (\(a, b) -> not (deck level a b)) [(x - 1, z), (x + 1, z), (x, z - 1), (x, z + 1)]
        && not (level == 0 && inside 7 7 10 8 x z)
        && not (level == 4 && (x, z) == (16, 6))
    wall x z = x == 29 && z >= 12 && z < 26
    opening h z = (h >= 1 && h <= 3 && z >= 14 && z <= 15) || (h >= 5 && h <= 7 && z >= 18 && z <= 20)
    backing h x z = any (\(a, b, c, d) -> x == a + 1 && z == c && h >= b && h <= d) atriumLadders
    solidWall h x z = wall x z && not (opening h z) || backing h x z
    ladderCell = any (\(a, b, c, d) -> u == a && v == c && y >= b && y <= d) atriumLadders
    ceilingLamp = u `mod` 8 `elem` [3, 4, 5] && v `elem` [5, 15, 25, 32]
    retainingLamp = y == -5 && ((v == 28 && u `elem` [15, 16, 17, 23, 24, 25]) || (u == 32 && v `elem` [10, 11, 24, 25]))

stair :: String -> BlockState
stair facing = BlockState "minecraft:smooth_sandstone_stairs" [("facing", facing), ("half", "bottom"), ("shape", "straight"), ("waterlogged", "false")]

-- Stacked straight flights connect each gallery to the next one below it.
-- Landings open sideways; solid end walls close unused floor-level openings.
staircase :: Int -> Int -> [Int] -> Point -> Maybe BlockState
staircase sx sz floors (u, y, v)
  | u < sx - 1 || u > sx + 2 || v < sz - 2 || v > sz + 13 = Nothing
  | u >= sx && u <= sx + 1 && v >= sz && v < sz + 12 && any (\f -> y == f - (v - sz)) floors = Just (stair "north")
  | northPad && y < lowest || v >= sz && v < sz + 12 && y < lowest - (v - sz) = Just (surface Wallpaper)
  | any (\f -> y == f && northPad) floors || any (\f -> y == f - 12 && southPad) floors = Just (surface Carpet)
  | shell = Just (if any (\f -> northPad && y >= f + 1 && y <= f + 3) floors || any (\f -> southPad && y >= f - 11 && y <= f - 9) floors then air else surface Wallpaper)
  | otherwise = Just air
  where
    lowest = minimum floors
    northPad = v < sz
    southPad = v >= sz + 12
    shell = u == sx - 1 || u == sx + 2 || v == sz - 2 || v == sz + 13

placements :: Landmark -> [(Point, BlockState)]
placements lm = [(p, state) | let (a, b, c, d) = bounds lm, x <- [a .. c - 1], z <- [b .. d - 1], y <- [minimumY lm .. (-1)], let p = (x, y, z), Just state <- [at lm p]]

requiredPoints :: Landmark -> [Point]
requiredPoints lm =
  [(0, f + 1, 6) | f <- [-12, 0, 12]]
    ++ map
      (world lm)
      ( case kind lm of
          Shaft -> [(7, f + 1, 5) | f <- [0, -12, -24, -36, -48]] ++ [(38, f + 1, 18) | f <- [0, -12, -24, -36, -48]]
          Pitfalls -> [(2, 1, 2), (35, 1, 28), (2, -11, 2), (28, -11, 18), (6, -12, 5)]
          SplitAtrium -> [(4, 1, 17), (9, -3, 17), (20, -7, 20), (27, 1, 14), (29, 1, 14), (27, 5, 20), (29, 5, 19), (35, 5, 27), (19, 5, 6)]
      )

viewPoints :: Landmark -> [(String, Point, Double, Double)]
viewPoints lm =
  [ (label, world lm p, yaw, pitch)
  | (label, p, yaw, pitch) <- case kind lm of
      Shaft -> [("shaft-overlook", (9, 1, 16), -90, 25), ("shaft-gallery", (38, -23, 18), 90, -10), ("shaft-base", (10, -47, 18), -90, -55)]
      Pitfalls -> [("pitfalls-room", (3, 1, 2), -30, 20), ("pitfalls-lower", (27, -11, 20), 135, 0)]
      SplitAtrium -> [("atrium-overlook", (4, 1, 17), -90, -5), ("atrium-court", (20, -7, 25), -140, -25), ("atrium-gallery", (35, 5, 24), 100, 20), ("atrium-raised-opening", (28, -7, 17), -30, -70)]
  ]

stairEndpoints :: Landmark -> [(Point, Point)]
stairEndpoints lm =
  [ (world lm lower, world lm upper)
  | (lower, upper) <- case kind lm of
      Shaft -> flights 2 6 [-36, -24, -12, 0]
      Pitfalls -> flights 30 4 [0]
      SplitAtrium -> [((8, -3, 11), (8, 1, 6)), ((15, -7, 23), (10, -3, 23))]
  ]
  where
    flights sx sz floors = [((sx, f - 11, sz + 12), (sx, f + 1, sz - 1)) | f <- floors]

ladderRoutes :: Landmark -> [(Point, Point)]
ladderRoutes lm = [((2, -11, 6), (0, 13, 6))] ++ [(world lm (x, bottom, z), world lm (x + 2, top + 1, z)) | kind lm == SplitAtrium, (x, bottom, z, top) <- atriumLadders]

fallPoints :: Landmark -> [Point]
fallPoints lm = map (world lm) $ case kind lm of Shaft -> [(22, 1, 19)]; Pitfalls -> [(6, 1, 5)]; SplitAtrium -> []
