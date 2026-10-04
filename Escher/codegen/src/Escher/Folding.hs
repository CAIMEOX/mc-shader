module Escher.Folding where

import Escher.Space (V3, norm, subtractV)

radius, ratio, height, width, turn, halfDepth, ballRadius, ballSpacing, ballSpeed, morphSeconds :: Double
radius = 7
ratio = 0.62
height = radius * log (1 / ratio)
width = 2 * pi * radius
turn = pi * 0.2
halfDepth = width * 21 / 128
ballRadius = 0.28
ballSpacing = width / 4
ballSpeed = width / 18
morphSeconds = 18

physicalPeriod :: Int
physicalPeriod = 44

sinc, exprel, log1p :: Double -> Double
sinc x
  | abs x < 1e-4 = 1 - x * x / 6 + x * x * x * x / 120
  | otherwise = sin x / x
exprel x
  | abs x < 1e-5 = 1 + x / 2 + x * x / 6 + x * x * x / 24
  | otherwise = (exp x - 1) / x
log1p x
  | abs x < 1e-5 = x - x * x / 2 + x * x * x / 3 - x * x * x * x / 4
  | otherwise = log (1 + x)

foldPoint :: Double -> V3 -> V3
foldPoint 0 p = p
foldPoint t (x, y, z) =
  ( q * cos b * (x + radius * t * turn * mixCoordinate) * sinc a,
    radialHeight * exprel u + radius * q * loss / t,
    q * z * sinc b
  )
  where
    radialHeight = y - t * height * x / width
    u = t * radialHeight / radius
    q = exp u
    mixCoordinate = y / height - x / width
    a = t * x / radius + t * t * turn * mixCoordinate
    b = t * z / radius
    loss = -2 * sin (b / 2) ^ (2 :: Int) - 2 * cos b * sin (a / 2) ^ (2 :: Int)

-- The reference chooses a continuous longitude branch of the covering space.
unfoldNear :: Double -> V3 -> V3 -> V3
unfoldNear 0 _ p = p
unfoldNear t (reference, _, _) (x, y, z) = (sourceX, radialHeight + t * height * sourceX / width, asin (max (-1) (min 1 (k * z / q))) / k)
  where
    k = t / radius
    radialHeight = 0.5 * log1p (k * (2 * y + k * (x * x + y * y + z * z))) / k
    q = exp (k * radialHeight)
    determinant = 1 + (t * t - t) * radius * turn / width
    longitude = atan2 (k * x) (1 + k * y) - t * t * turn * radialHeight / height
    base = atan2 (sin longitude) (cos longitude) / k / determinant
    period = width / (t * determinant)
    sourceX = base + fromIntegral (round ((reference - base) / period) :: Integer) * period

localScale :: Double -> V3 -> Double
localScale t (x, y, _) = exp (t * (y - t * height * x / width) / radius)

type Matrix3 = (V3, V3, V3)

jacobian :: Double -> V3 -> Matrix3
jacobian t p@(x, y, z) =
  ( add (scale (q * cos b * (1 - t * radius * turn / width)) east) (scale (-q * t * height / width) radial),
    add (scale q radial) (scale (q * cos b * radius * t * turn / height) east),
    scale q north
  )
  where
    a = t * x / radius + t * t * turn * (y / height - x / width)
    b = t * z / radius
    q = localScale t p
    radial = (cos b * sin a, cos b * cos a, sin b)
    east = (cos a, -sin a, 0)
    north = (-sin b * sin a, -sin b * cos a, cos b)

apply :: Matrix3 -> V3 -> V3
apply (a, b, c) (x, y, z) = add (scale x a) (add (scale y b) (scale z c))

add, cross :: V3 -> V3 -> V3
add (x, y, z) (a, b, c) = (x + a, y + b, z + c)
cross (x, y, z) (a, b, c) = (y * c - z * b, z * a - x * c, x * b - y * a)

scale :: Double -> V3 -> V3
scale k (x, y, z) = (k * x, k * y, k * z)

unit :: V3 -> V3
unit v = scale (1 / norm v) v

-- Source +X is forward, source +Z is the transverse direction.
frame :: Double -> V3 -> Matrix3
frame t p = (unit dx, up, unit (cross (unit dx) up))
  where
    (dx, _, dz) = jacobian t p
    up = unit (cross dz dx)

segment :: Int -> Double -> V3 -> V3
segment steps 0 p = add p (fromIntegral steps * width, 0, 0)
segment steps t p = add translation (scale q (rotateZ a p))
  where
    n = fromIntegral steps
    a = n * (-2 * pi * t + t * t * turn)
    u = log ratio * t * t * n
    q = exp u
    translation =
      ( q * n * (width - radius * t * turn) * sinc a,
        -height * t * n * exprel u - 2 * radius / t * q * sin (a / 2) ^ (2 :: Int),
        0
      )

rotateZ :: Double -> V3 -> V3
rotateZ a (x, y, z) = (cos a * x - sin a * y, sin a * x + cos a * y, z)

ballCenter :: Double -> Double -> Double -> V3
ballCenter t x lane = add (foldPoint t p) (scale (ballRadius * localScale t p) up)
  where
    p = (x, if lane == 0 then 0.10 else 0, lane)
    (_, up, _) = frame t p

-- Express a displacement in the orthonormal camera frame, in local scale units.
viewPoint :: Double -> V3 -> V3 -> V3
viewPoint t camera point = scale (1 / localScale t camera) (dot right d, dot up d, dot forward d)
  where
    (forward, up, right) = frame t camera
    d = subtractV (foldPoint t point) (foldPoint t camera)
    dot (x, y, z) (a, b, c) = x * a + y * b + z * c
