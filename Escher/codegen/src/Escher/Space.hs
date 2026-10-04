module Escher.Space where

type V3 = (Double, Double, Double)

data Mapping = Mapping {period :: Double, ratio :: Double, turn :: Double} deriving (Show)

standard :: Mapping
standard = Mapping 18 (655 / 1024) (399 / 1024)

rotate :: Double -> (Double, Double) -> (Double, Double)
rotate a (x, y) = (cos a * x - sin a * y, sin a * x + cos a * y)

-- A smooth covering coordinate: translating by one room is a similarity.
embed :: Mapping -> V3 -> V3
embed m (x, y, z) = (h * a, h * b, focus * (1 - h))
  where
    u = z / period m
    h = ratio m ** u
    focus = -period m / log (ratio m)
    (a, b) = rotate (turn m * u) (x, y)

pullback :: Mapping -> V3 -> V3
pullback m (x, y, z) = (a / h, b / h, u * period m)
  where
    focus = -period m / log (ratio m)
    h = 1 - z / focus
    u = log h / log (ratio m)
    (a, b) = rotate (-turn m * u) (x, y)

similarity :: Mapping -> Double -> V3 -> V3
similarity m level (x, y, z) = (h * a, h * b, h * z + focus * (1 - h))
  where
    h = ratio m ** level
    focus = -period m / log (ratio m)
    (a, b) = rotate (turn m * level) (x, y)

wrap :: Double -> Double -> Double
wrap p z = z - p * fromIntegral (floor (z / p) :: Integer)

subtractV :: V3 -> V3 -> V3
subtractV (x, y, z) (a, b, c) = (x - a, y - b, z - c)

norm :: V3 -> Double
norm (x, y, z) = sqrt (x * x + y * y + z * z)
