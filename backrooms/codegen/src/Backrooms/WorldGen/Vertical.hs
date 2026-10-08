module Backrooms.WorldGen.Vertical
  ( Kind (..),
    kindNames,
    size,
    landmarkSpacing,
    Vertical,
    compile,
    rules,
    active,
    owned,
    solid,
    localBounds,
    materialMasks,
    stairPath,
    ladderRoute,
  )
where

import Backrooms.WorldGen.Block qualified as B
import Backrooms.WorldGen.Coordinates qualified as C
import Backrooms.WorldGen.Density
import Backrooms.WorldGen.Floors qualified as F
import Backrooms.WorldGen.Geometry qualified as G
import Backrooms.WorldGen.Materials (Surface (..), surfaceBlock)
import Data.List (nub)

data Kind = LadderRoom | Switchback | Spiral deriving (Eq, Show, Enum, Bounded)

kindNames :: [(Int, String)]
kindNames = [(fromEnum k, case k of LadderRoom -> "ladder_room"; Switchback -> "switchback"; Spiral -> "spiral") | k <- [minBound .. maxBound]]

size :: Kind -> Int
size LadderRoom = 9
size Switchback = 17
size Spiral = 11

-- Landmark pieces fit within 64 blocks of these candidate origins. Cores and
-- their approach collars occupy the central [64,128) square of each period.
landmarkSpacing :: Int
landmarkSpacing = 192

data Vertical = Vertical
  { rules :: [(String, Density)],
    active :: Density,
    owned :: Density,
    solid :: Density,
    localBounds :: G.Bounds,
    materialMasks :: [(String, B.BlockState)]
  }

compile :: C.Region -> Vertical
compile region = Vertical definitions present ownership (ref "solid") orientedBounds bindings
  where
    c = Constant
    ref key = Ref ("vertical/" ++ key)
    x = ref "x"
    z = ref "z"
    y = C.y region
    u = ref "u"
    v = ref "v"
    side = ref "size"
    lx = ref "lo_x"
    lz = ref "lo_z"
    transpose = ref "transpose"
    present = ref "active"
    ownership = ref "owned"
    bounds = G.Bounds lx (lx .+. side) lz (lz .+. side)
    orientedBounds = G.Bounds (select (C.transposed region) lz lx) (select (C.transposed region) (lz .+. side) (lx .+. side)) (select (C.transposed region) lx lz) (select (C.transposed region) (lx .+. side) (lz .+. side))
    roll key = Noise ("vertical/" ++ key) (c 24 .-. C.rawX region) (c 24 .-. C.rawZ region)
    chosen k = band (ref "kind") (fromIntegral (fromEnum k)) (fromIntegral (fromEnum k + 1))
    footprint = intersection [between (C.rawX region) (G.loX bounds) (G.hiX bounds), between (C.rawZ region) (G.loZ bounds) (G.hiZ bounds)]
    parts = [(state, select ownership (select (chosen k) geometry (c 0)) (c 0)) | k <- [minBound .. maxBound], (state, geometry) <- components k u y v transpose]
    palette = nub (map fst parts)
    bindings = [("vertical/material_" ++ show i, state) | (i, state) <- zip [0 :: Int ..] palette]
    definitions =
      [ ("vertical/x", Floor (Gradient X 0 landmarkSpacing 0 (fromIntegral landmarkSpacing) True .+. c 0.5)),
        ("vertical/z", Floor (Gradient Z 0 landmarkSpacing 0 (fromIntegral landmarkSpacing) True .+. c 0.5)),
        ("vertical/active", intersection [band x 48 144, band z 48 144]),
        ("vertical/kind", quantileChoice (length kindNames) (Cache (roll "kind"))),
        ("vertical/transpose", band (roll "orientation") 0 1000),
        ("vertical/lo_x", select (band x 0 96) (c 19) (c 8) .+. choice 3 (roll "x")),
        ("vertical/lo_z", select (band z 0 96) (c 19) (c 8) .+. choice 3 (roll "z")),
        ("vertical/size", pick [fromIntegral (size k) | k <- [minBound .. maxBound]] (ref "kind")),
        ("vertical/u", select transpose (C.rawZ region .-. lz) (C.rawX region .-. lx)),
        ("vertical/v", select transpose (C.rawX region .-. lx) (C.rawZ region .-. lz)),
        ("vertical/owned", intersection [present, footprint, band y (fromIntegral (F.lowestY - 1)) (fromIntegral (F.highestY + 7))]),
        ("vertical/solid", union [mask | (_, mask) <- parts])
      ]
        ++ [(key, union [mask | (paint, mask) <- parts, paint == state]) | (key, state) <- bindings]

data Facing = East | South | West | North deriving (Eq, Show)

type Point = (Int, Int, Int)

data Flight = Flight Point Facing Int Int

facingName :: Facing -> String
facingName direction = case direction of East -> "east"; South -> "south"; West -> "west"; North -> "north"

transposeFacing :: Facing -> Facing
transposeFacing direction = case direction of East -> South; South -> East; West -> North; North -> West

flights :: Kind -> [Flight]
flights kind = concatMap at [F.lowestY, F.lowestY + F.pitch .. F.highestY - F.pitch]
  where
    at y = case kind of
      LadderRoom -> []
      Switchback -> [Flight (5, y, 5) South 6 2, Flight (10, y + 6, 10) North 6 2]
      Spiral -> [Flight (4, y, 1) East 3 2, Flight (8, y + 3, 4) South 3 2, Flight (6, y + 6, 8) West 3 2, Flight (1, y + 9, 6) North 3 2]

stairPath :: Kind -> [Point]
stairPath LadderRoom = []
stairPath Switchback = (5, F.lowestY, 4) : concat [[(5, f + 6, 11), (10, f + 6, 11), (10, f + 12, 4)] ++ concat [[(10, f + 12, 2), (5, f + 12, 2), (5, f + 12, 4)] | f + F.pitch < F.highestY] | f <- filter (< F.highestY) F.walkLevels]
stairPath Spiral = (2, F.lowestY, 2) : concat [[(8, f + 3, 2), (8, f + 6, 8), (2, f + 9, 8), (2, f + 12, 2)] | f <- filter (< F.highestY) F.walkLevels]

ladderRoute :: Kind -> Maybe (Point, Point)
ladderRoute LadderRoom = Just ((3, F.lowestY, 4), (5, F.highestY, 4))
ladderRoute _ = Nothing

components :: Kind -> Density -> Density -> Density -> Density -> [(B.BlockState, Density)]
components kind u y v transpose =
  [(surface Luminaire, lamps), (surface Ceiling, roof)]
    ++ oriented "minecraft:ladder" West [("waterlogged", "false")] ladder
    ++ concatMap staircase (flights kind)
    ++ [(surface Carpet, floors), (surface Wallpaper, union [walls, pillar, guards])]
  where
    c :: Int -> Density
    c = Constant . fromIntegral
    n = size kind
    surface = B.plain . surfaceBlock
    rect :: Int -> Int -> Int -> Int -> Density
    rect a b w d = intersection [band u (fromIntegral a) (fromIntegral (a + w)), band v (fromIntegral b) (fromIntegral (b + d))]
    atY h = near y (c h) 0
    slab h mask = intersection [atY h, mask]
    floorBand = union [band y (fromIntegral h) (fromIntegral (h + 3)) | h <- F.walkLevels]
    edge = union [near u (c 0) 0, near u (c (n - 1)) 0, near v (c 0) 0, near v (c (n - 1)) 0]
    portals = case kind of
      Spiral -> union [intersection [near v (c 0) 0, band u 1 4], intersection [near u (c 0) 0, band v 1 4]]
      _ -> union [intersection [union [near u (c 0) 0, near u (c (n - 1)) 0], near v (c (n `div` 2)) 1], intersection [union [near v (c 0) 0, near v (c (n - 1)) 0], near u (c (n `div` 2)) 1]]
    walls = intersection [edge, inverse (intersection [portals, floorBand])]
    roof = inverse (less y (c (F.highestY + 4)))
    lamps = intersection [edge, union [atY (h + 3) | h <- F.walkLevels], union [near u (c (n `div` 2)) 1, near v (c (n `div` 2)) 1]]
    ladder = if kind == LadderRoom then intersection [rect 3 4 1 1, band y (fromIntegral F.lowestY) (fromIntegral F.highestY)] else Constant 0
    pillar = case kind of
      LadderRoom -> intersection [rect 4 4 1 1, less y (c F.highestY)]
      Spiral -> rect 3 3 5 5
      Switchback -> Constant 0
    floors =
      union
        ( slab (F.lowestY - 1) (Constant 1) : case kind of
            LadderRoom -> [slab (f - 1) (inverse (rect 3 4 1 1)) | f <- drop 1 F.walkLevels]
            Switchback -> [slab (f - 1) (inverse (rect 4 5 9 9)) | f <- drop 1 F.walkLevels] ++ [slab (f + 5) (rect 5 11 7 3) | f <- filter (< F.highestY) F.walkLevels]
            Spiral -> [slab (f - 1) (rect 1 1 3 3) | f <- drop 1 F.walkLevels] ++ concat [[slab (f + 2) (rect 7 1 3 3), slab (f + 5) (rect 7 7 3 3), slab (f + 8) (rect 1 7 3 3)] | f <- filter (< F.highestY) F.walkLevels]
        )
    guards = if kind == Switchback then union [slab f (union [rect 3 5 1 9, rect 13 5 1 9, rect 3 14 11 1, intersection [rect 4 4 9 1, inverse (union ([rect 10 4 2 1] ++ [rect 5 4 2 1 | f < F.highestY]))]]) | f <- drop 1 F.walkLevels] else Constant 0
    oriented block direction properties mask =
      [(B.BlockState block (("facing", facingName face) : properties), intersection [mask, flag]) | (face, flag) <- [(direction, inverse transpose), (transposeFacing direction, transpose)]]
    staircase (Flight (x0, y0, z0) direction count width) = oriented "minecraft:smooth_sandstone_stairs" direction [("half", "bottom"), ("shape", "straight"), ("waterlogged", "false")] mask
      where
        (along, start, cross, other, forward) = case direction of
          East -> (u, x0, v, z0, True)
          West -> (u, x0, v, z0, False)
          South -> (v, z0, u, x0, True)
          North -> (v, z0, u, x0, False)
        step = if forward then along .-. c start else c start .-. along
        mask = intersection [band step 0 (fromIntegral count), band cross (fromIntegral other) (fromIntegral (other + width)), near y (c y0 .+. step) 0]
