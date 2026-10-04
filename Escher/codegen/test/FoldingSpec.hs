module FoldingSpec (checks) where

import Control.Monad (forM_, unless)
import Escher.Folding qualified as F
import Escher.Folding.Scene qualified as Scene
import Escher.Scene (sample)
import Escher.Space (V3, norm, subtractV)

checks :: IO ()
checks = do
  forM_ [0 .. 15 :: Int] $ \column -> do
    let center = -F.width / 2 + (fromIntegral column + 0.5) * F.width / 16
        side = 7.4 * F.width / 128
        distances = [fst (sample Scene.building (center + dx, 1.3, side)) | dx <- [-0.08, -0.0001, 0.0001, 0.08]]
    unless (all (< 0) distances) (fail ("Folding column has its full cross-section: " ++ show (column, distances)))
    unless (abs (distances !! 1 - distances !! 2) < 0.000201) (fail "Folding column field remains continuous at its center")
  forM_ [(x, y, z) | x <- [-20, 0, 19], y <- [0, 1.62, F.height], z <- [-7, 0, 7]] $ \p -> do
    near "Folding identity" p (F.foldPoint 0 p)
    near "Folding translation limit" p (F.foldPoint 1e-8 p)
    forM_ [0, 1e-8, 0.001, 0.2, 0.5, 0.9, 1] $ \t -> do
      near "Folding inverse chart" p (F.unfoldNear t p (F.foldPoint t p))
      forM_ [(1, 0, 0), (0, 1, 0), (0, 0, 1)] $ \axis -> do
        let epsilon = 1e-4
            derivative = F.scale (1 / (2 * epsilon)) (subtractV (F.foldPoint t (F.add p (F.scale epsilon axis))) (F.foldPoint t (F.add p (F.scale (-epsilon) axis))))
        near "Analytic folding differential" derivative (F.apply (F.jacobian t p) axis)
      forM_ [-5, -1, 1, 5] $ \n -> do
        let offset = (fromIntegral n * F.width, 0, 0)
        near "Folding segment continuation" (F.foldPoint t (F.add p offset)) (F.segment n t (F.foldPoint t p))
        near "Folding camera chart" (F.viewPoint t p (F.add p (3, 0.2, 0.4))) (F.viewPoint t (F.add p offset) (F.add p (F.add offset (3, 0.2, 0.4))))
    near "Folding scale and circuit coupling" (F.foldPoint 1 (F.add p (F.width, 0, 0))) (F.foldPoint 1 (F.add p (0, -F.height, 0)))
  forM_ [0, 0.25, 0.5, 0.999999, 1] $ \t -> forM_ [-F.width / 2, 0, F.width / 2] $ \x ->
    near "Rolling sphere continuation" (F.ballCenter t (x + F.width) 0) (F.segment 1 t (F.ballCenter t x 0))
  forM_ [-F.width / 2, -3, 0, 8, F.width / 2] $ \x -> do
    let point = (x, 1.62, 0)
    unless (fst (sample Scene.building point) > 0.2) (fail "Folding walkway has standing clearance")
    near "Periodic folding architecture" (fst (sample Scene.building point), 0, 0) (fst (sample Scene.building (F.add point (F.width, 0, 0))), 0, 0)
  unless (all (\z -> any ((== (0, -6, z)) . fst) Scene.collisionBlocks) [0 .. F.physicalPeriod - 1]) (fail "Folding collision floor reaches both boundaries")
  putStrLn "Passed: Folding identity, inverse branches, Jacobian, camera and sphere continuity, collision floor."

near :: String -> V3 -> V3 -> IO ()
near label a b = unless (norm (subtractV a b) < 1e-6 * max 1 (max (norm a) (norm b))) (fail (label ++ ": " ++ show (a, b)))
