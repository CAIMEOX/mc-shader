module Backrooms.WorldGen.Coordinates (Region (..), region, onPlane, rules, noiseAt) where

import Backrooms.WorldGen.Density

-- A repeated coordinate frame shared by partitions and regional connections.
data Region = Region
  { size :: Int,
    height :: Int,
    rawX :: Density,
    rawZ :: Density,
    x :: Density,
    z :: Density,
    y :: Density,
    transposed :: Density,
    noisePlane :: Density
  }
  deriving (Eq, Show)

region :: Int -> Int -> Region
region spanXZ spanY = Region spanXZ spanY (Ref "coordinate_x") (Ref "coordinate_z") (Ref "local_x") (Ref "local_z") (Ref "y") (Ref "transpose") (Constant 0)

onPlane :: Density -> Region -> Region
onPlane plane frame = frame {noisePlane = plane}

rules :: Region -> [(String, Density)]
rules frame =
  [ ("coordinate_x", coordinate X),
    ("coordinate_z", coordinate Z),
    ("transpose", band (NoiseAt "orientation" (centre .-. rawX frame) (noisePlane frame) (centre .-. rawZ frame)) 0 2),
    ("local_x", select (transposed frame) (rawZ frame) (rawX frame)),
    ("local_z", select (transposed frame) (rawX frame) (rawZ frame)),
    ("y", Gradient Y 0 (height frame) 0 (fromIntegral (height frame)) False)
  ]
  where
    coordinate axis = Floor (Gradient axis 0 (size frame) 0 (fromIntegral (size frame)) True .+. Constant 0.5)
    centre = Constant (fromIntegral (size frame) * 0.5)

-- A local point is mapped back to world space before noise is sampled.
noiseAt :: Region -> String -> Density -> Density -> Density
noiseAt frame name localX localZ =
  NoiseAt
    name
    (select (transposed frame) localZ localX .-. rawX frame)
    (noisePlane frame)
    (select (transposed frame) localX localZ .-. rawZ frame)
