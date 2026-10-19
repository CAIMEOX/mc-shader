module Manifold.Scene where

import Data.List (nub)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as M
import Manifold.Gravity qualified as G
import Manifold.Stage (Box (..))

data Solid = Solid {solidBox :: Box, solidChannel :: Maybe Int} deriving (Eq, Show)

data Scene = Scene {scenePeriod :: Int, sceneSolids :: [Solid], sceneBuckets :: Map G.V [Int]} deriving (Eq, Show)

bucketSize, windowSize, halo :: Int
bucketSize = 16
windowSize = 32
halo = 6

compileScene :: Int -> [Solid] -> Either String Scene
compileScene size authored
  | size < windowSize || size `mod` bucketSize /= 0 = Left "Scene period must contain whole spatial buckets and a native window"
  | any (maybe False (\i -> i < 0 || i >= 16) . solidChannel) authored = Left "Scene channels are numbered from zero through fifteen"
  | any invalid authored = Left "Solid bounds must be ordered and fit within one period"
  | otherwise = Right (Scene size solids index)
  where
    apertures = [solidBox solid | solid <- authored, solidChannel solid /= Nothing]
    solids = concatMap carve authored
    carve solid = case solidChannel solid of
      Just _ -> [solid]
      Nothing -> [solid {solidBox = box} | box <- foldl (\pieces cut -> concatMap (`subtractBox` cut) pieces) [solidBox solid] apertures]
    invalid (Solid (Box lo hi _) _) = or (zipWith (>) (G.components lo) (G.components hi)) || any (>= size) (zipWith (-) (G.components hi) (G.components lo))
    index = M.fromListWith (++) [(key, [i]) | (i, solid) <- zip [0 ..] solids, key <- keys (solidBox solid)]
    keys (Box lo hi _) = nub [G.vector (map (`mod` (size `div` bucketSize)) [x, y, z]) | x <- range 0, y <- range 1, z <- range 2]
      where
        range axis = [G.component axis lo `div` bucketSize .. G.component axis hi `div` bucketSize]

-- Static masonry is split around authored door apertures once, before all backends.
subtractBox :: Box -> Box -> [Box]
subtractBox box cut
  | or (zipWith (>) (G.components low) (G.components high)) = [box]
  | otherwise = [Box a b (boxMaterial box) | (a, b) <- pieces, and (zipWith (<=) (G.components a) (G.components b))]
  where
    low@(lx, ly, lz) = G.vector (zipWith max (G.components (boxLo box)) (G.components (boxLo cut)))
    high@(hx, hy, hz) = G.vector (zipWith min (G.components (boxHi box)) (G.components (boxHi cut)))
    (ax, ay, az) = boxLo box
    (bx, by, bz) = boxHi box
    pieces = [((ax, ay, az), (lx - 1, by, bz)), ((hx + 1, ay, az), (bx, by, bz)), ((lx, ay, az), (hx, ly - 1, bz)), ((lx, hy + 1, az), (hx, by, bz)), ((lx, ly, az), (hx, hy, lz - 1)), ((lx, ly, hz + 1), (hx, hy, bz))]

canonical :: Scene -> G.V -> G.V
canonical scene = G.vector . map (`mod` scenePeriod scene) . G.components

bucket :: Scene -> G.V -> G.V
bucket scene = G.vector . map (`div` bucketSize) . G.components . canonical scene

enabled :: [Bool] -> Solid -> Bool
enabled channels solid = maybe True (\i -> not (channels !! i)) (solidChannel solid)

containsCell :: Scene -> Box -> G.V -> Bool
containsCell scene box p = any contains (images scene box)
  where
    q = canonical scene p
    contains image = and [G.component axis q >= G.component axis (boxLo image) && G.component axis q <= G.component axis (boxHi image) | axis <- [0 .. 2]]

solidAt :: Scene -> [Bool] -> G.V -> Bool
solidAt scene channels p = any hit (M.findWithDefault [] (bucket scene p) (sceneBuckets scene))
  where
    hit i = let solid = sceneSolids scene !! i in enabled channels solid && containsCell scene (solidBox solid) p

images :: Scene -> Box -> [Box]
images scene box = [box {boxLo = G.add (boxLo box) delta, boxHi = G.add (boxHi box) delta} | x <- shifts, y <- shifts, z <- shifts, let delta = (x, y, z)]
  where
    shifts = [-scenePeriod scene, 0, scenePeriod scene]

-- Periodic ray traversal consumes complete solids clipped to one lattice cell.
canonicalSolids :: Scene -> [Solid]
canonicalSolids scene =
  [ solid {solidBox = image {boxLo = lo, boxHi = hi}}
  | solid <- sceneSolids scene,
    image <- images scene (solidBox solid),
    let lo = G.vector (map (max 0) (G.components (boxLo image))),
    let hi = G.vector (map (min (scenePeriod scene - 1)) (G.components (boxHi image))),
    and (zipWith (<=) (G.components lo) (G.components hi))
  ]

-- The swept envelope includes the body and every point traversed in the tick.
candidates :: Scene -> G.V -> G.V -> G.V -> [Int]
candidates scene position displacement extent = nub [i | x <- spanAxis 0, y <- spanAxis 1, z <- spanAxis 2, i <- M.findWithDefault [] (bucket scene (x, y, z)) (sceneBuckets scene)]
  where
    spanAxis axis = [low .. high]
      where
        a = G.component axis position
        b = a + G.component axis displacement
        h = G.component axis extent
        low = (min a b - h + G.unit `div` 2) `div` G.unit
        high = (max a b + h + G.unit `div` 2) `div` G.unit

windowOrigin :: Scene -> G.V -> G.V
windowOrigin scene = G.vector . map (\x -> x `div` windowSize * windowSize) . G.components . canonical scene

project :: Scene -> G.V -> [Bool] -> [Box]
project scene origin channels = nub [image {boxLo = lo, boxHi = hi} | solid <- sceneSolids scene, enabled channels solid, image <- images scene (solidBox solid), let lo = G.vector (zipWith max (G.components (boxLo image)) (G.components (G.add origin (-halo, -halo, -halo)))), let hi = G.vector (zipWith min (G.components (boxHi image)) (G.components (G.add origin (windowSize + halo - 1, windowSize + halo - 1, windowSize + halo - 1)))), and (zipWith (<=) (G.components lo) (G.components hi))]

data Circuit = Circuit {circuitInputs :: [(Int, G.V)], circuitOutput :: Int} deriving (Eq, Show)

validateCircuits :: Scene -> [Int] -> [Circuit] -> Either String ()
validateCircuits scene identities circuits
  | length outputs /= length (nub outputs) || any (\i -> i < 0 || i >= 16) outputs = Left "Circuit outputs must be unique channels from zero through fifteen"
  | any (\(ident, cell) -> ident `notElem` identities || canonical scene cell /= cell) inputs = Left "Circuit inputs require a registered cube and a canonical cell"
  | otherwise = Right ()
  where
    outputs = map circuitOutput circuits; inputs = concatMap circuitInputs circuits

affectedCircuits :: [Circuit] -> Int -> [Int]
affectedCircuits circuits object = [circuitOutput c | c <- circuits, any ((== object) . fst) (circuitInputs c)]
