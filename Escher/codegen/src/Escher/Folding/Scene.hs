module Escher.Folding.Scene (building, collisionBlocks) where

import Escher.Folding qualified as F
import Escher.Scene

building :: Shape
building = frame 0.08

frame :: Double -> Shape
frame floorDepth =
  Union $
    [box (0, -floorDepth / 2, lane) (10000, floorDepth / 2, half) Checker | (lane, half, _) <- halls]
      ++ [RepeatX (F.width / 4) (box (0, -floorDepth / 2, 0) (1.5 * grid, floorDepth / 2, F.halfDepth) Checker)]
      ++ [ Union $
             concat
               [ [ box (0, 0.10, z) (10000, 0.10, 0.10) Stone,
                   box (0, 0.86, z) (10000, 0.0375, 0.0375) Brass,
                   box (0, h, z) (10000, 0.09, 0.12) Stone,
                   box (0, h + 0.13, z) (10000, 0.035, 0.145) Green,
                   RepeatX (F.width / 48) (box (F.width / 96, 0.47, z) (0.0275, 0.43, 0.0275) Brass),
                   RepeatX
                     (F.width / 16)
                     ( Union
                         [ box (F.width / 32, h / 2, z) (0.095, h / 2, 0.095) Stone,
                           box (F.width / 32, 0.11, z) (0.16, 0.11, 0.16) Stone,
                           box (F.width / 32, h - 0.10, z) (0.15, 0.085, 0.15) Chalk
                         ]
                     )
                 ]
               | side <- [-1, 1],
                 let z = lane + side * half
               ]
               ++ [RepeatX (F.width / 16) (box (F.width / 32, h, lane) (0.095, 0.09, half + 0.2) Stone)]
         | (lane, half, h) <- halls
         ]
      ++ [ box (0, 0.065, 0) (10000, 0.035, 0.055) Brass,
           box (0, 2.78, 0) (10000, 0.0325, 0.04) Red,
           RepeatX
             (F.width / 4)
             ( Union
                 [ box (-0.44, 0.09, 0) (0.055, 0.09, F.halfDepth) Stone,
                   box (0.44, 0.09, 0) (0.055, 0.09, F.halfDepth) Stone,
                   box (0, 2.6, 0) (0.07, 0.07, F.halfDepth) Stone
                 ]
             ),
           RepeatX
             F.width
             ( Union
                 [ box (-F.width * 0.2, 0.26, 1.25) (0.37, 0.26, 0.37) Stone,
                   box (-F.width * 0.2, 0.57, 1.25) (0.435, 0.05, 0.435) Green,
                   Move (-F.width * 0.2, 1, 1.25) (Ball 0.38 Red)
                 ]
             )
         ]
  where
    grid = F.width / 128
    halls = [(0, 7.4 * grid, 2.6), (18 * grid, 2.4 * grid, 2.25), (-18 * grid, 2.4 * grid, 2.25)]

collisionBlocks :: [((Int, Int, Int), Material)]
collisionBlocks =
  [ ((x, y, z), material)
  | z <- [0 .. F.physicalPeriod - 1],
    y <- [-6 .. 0],
    x <- [-8 .. 7],
    let point = ((fromIntegral z + 0.5) / fromIntegral F.physicalPeriod * F.width - F.width / 2, fromIntegral y + 5.5, -fromIntegral x - 0.5),
    let (distance, material) = sample (frame 1) point,
    distance < -0.001,
    material /= Red
  ]
