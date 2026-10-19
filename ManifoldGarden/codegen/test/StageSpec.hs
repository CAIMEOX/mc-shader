module StageSpec (checks) where

import Control.Monad (forM_, unless)
import Manifold.Gravity qualified as G
import Manifold.Stage

checks :: IO ()
checks = do
  forM_ G.frames $ \frame -> do
    forM_ [(0, 0, 0), (8, 3, 2), (-2, 17, 33), (31, -70, 4096)] $ \p ->
      ensure "Cube frames preserve logical block centres through the native inverse" (G.apply frame (transformBlock frame p) == p)
    let box = Box (-2, 1, 4) (3, 2, 7) "minecraft:quartz_block"
        transformed = transformBox frame box
    ensure "Rotated bounds preserve voxel volume" (volume box == volume transformed)
    ensure "Rotated bounds contain exactly the rotated solid" (all (containsBlock transformed . transformBlock frame) (voxels box))
    let envelope = cacheEnvelope (Just frame)
    ensure "A cached room clears every projected block in its orientation" (all (containsBlock envelope . transformBlock frame) [(x, y, z) | x <- [-6, 37], y <- [-6, 37], z <- [-6, 37]])
    ensure "The bounded cache fits inside the initialization envelope" (all (containsBlock (cacheEnvelope Nothing)) [boxLo envelope, boxHi envelope])
    ensure "Known room clearing stays within one hundred thousand block visits" (volume envelope < 100000)
  -- Integer centres distinguish occupied voxels without depending on emitted
  -- command layout or floating-point values directly on a surface.
  let samples = [(x, y, z) | x <- [-2 .. 33], y <- [-2 .. 33], z <- [-2 .. 33]]
  forM_ samples $ \p -> do
    ensure "Distance geometry and native block occupancy agree" ((stageDistance (point p) < 0) == solid p)
    ensure "Scene distance repeats in all three coordinates" (near (stageDistance (point p)) (stageDistance (point (G.add p (32, -64, 96)))))
    ensure "The native lattice matches gravity beam collision" (solid p == G.inside (G.scale G.unit p) (0, 0, 0))

  let coordinates = [-0.00001, 0.25, 1.5, 2.75, 8, 16, 30.25, 31.99999, 32.25]
      distanceSamples = [(x, y, z) | x <- coordinates, y <- coordinates, z <- coordinates]
      seamPoint axis value a b = case axis of
        0 -> (value, a, b)
        1 -> (a, value, b)
        _ -> (a, b, value)
      epsilon = 0.00001
  forM_ distanceSamples $ \p ->
    ensure "Analytic distance chooses the nearest periodic solid image" (near (stageDistance p) (referenceDistance p))
  forM_ [0 :: Int .. 2] $ \axis ->
    forM_ [(a, b) | a <- coordinates, b <- coordinates] $ \(a, b) -> do
      let before = stageDistance (seamPoint axis (32 - epsilon) a b)
          after = stageDistance (seamPoint axis (32 + epsilon) a b)
      ensure "A cell crossing preserves the distance field Lipschitz bound" (abs (before - after) <= 2 * epsilon + 1e-9)
  putStrLn "Passed: stage rotations, native room solids, periodic distance images, and seam continuity."
  where
    ensure message condition = unless condition (fail message)
    point (x, y, z) = (fromIntegral x, fromIntegral y, fromIntegral z)
    solid p = any (`containsBlock` p) stageBoxes
    near a b = abs (a - b) < 1e-9
    volume box = product (zipWith (\low high -> high - low + 1) (G.components (boxLo box)) (G.components (boxHi box)))
    voxels box = [(x, y, z) | let (lx, ly, lz) = boxLo box, let (hx, hy, hz) = boxHi box, x <- [lx .. hx], y <- [ly .. hy], z <- [lz .. hz]]

-- An independent finite search over neighbouring native-room images provides
-- a geometric reference for the analytic nearest-image calculation.
referenceDistance :: (Double, Double, Double) -> Double
referenceDistance (x, y, z) =
  minimum
    [ distance box [x + dx, y + dy, z + dz]
    | box <- stageBoxes,
      dx <- [-32, 0, 32],
      dy <- [-32, 0, 32],
      dz <- [-32, 0, 32]
    ]
  where
    distance box p =
      let q = zipWith3 (\a low high -> max (fromIntegral low - 0.5 - a) (a - fromIntegral high - 0.5)) p (G.components (boxLo box)) (G.components (boxHi box))
       in sqrt (sum [max 0 a * max 0 a | a <- q]) + min 0 (maximum q)
