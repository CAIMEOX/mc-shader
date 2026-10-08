module Backrooms.WorldGen.Floors
  ( Floors,
    compile,
    rules,
    index,
    walkY,
    localY,
    active,
    noisePlane,
    walkLevels,
    pitch,
    entranceY,
    lowestY,
    highestY,
  )
where

import Backrooms.WorldGen.Density

entranceY, pitch, lowestY, highestY :: Int
entranceY = 64
pitch = 12
lowestY = 52
highestY = 76

walkLevels :: [Int]
walkLevels = [lowestY, lowestY + pitch .. highestY]

-- A slab starts with its floor block, so the supporting block and the room
-- above it share one identity and one deterministic noise plane.
data Floors = Floors
  { rules :: [(String, Density)],
    index :: Density,
    walkY :: Density,
    localY :: Density,
    active :: Density,
    noisePlane :: Density
  }

compile :: Density -> Floors
compile y = Floors definitions (ref "index") (ref "y") (ref "local_y") (ref "active") (ref "noise_y")
  where
    ref key = Ref ("floor/" ++ key)
    definitions =
      [ ("floor/index", Floor ((y .-. Constant (fromIntegral (entranceY - 1))) .*. Constant (1 / fromIntegral pitch))),
        ("floor/y", Constant (fromIntegral entranceY) .+. ref "index" .*. Constant (fromIntegral pitch)),
        ("floor/local_y", y .-. ref "y"),
        ("floor/active", band y (fromIntegral (lowestY - 1)) (fromIntegral (highestY + pitch - 1))),
        ("floor/noise_y", ref "index" .*. Constant 64)
      ]
