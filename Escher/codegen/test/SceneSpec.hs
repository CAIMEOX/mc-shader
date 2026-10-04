module SceneSpec (checks) where

import Control.Monad (forM_, unless)
import Escher.Scene
import Escher.Space (norm, subtractV)

checks :: IO ()
checks = do
  forM_ [False, True] $ \alongZ -> do
    let orient (x, y, z) = if alongZ then (z, y, x) else (x, y, z)
        period = 4
        repeatShape = if alongZ then RepeatZ period else RepeatX period
        leaf at size = box (orient at) (orient size) Stone
        unit = Union [leaf (period / 2, 0, 0) (0.2, 0.8, 0.3), leaf (-1.2, 1.7, 0) (0.35, 0.2, 0.4)]
        repeated = repeatShape unit
    forM_ [(x, y, z) | x <- [-8, -6.001, -6, -5.999, -2.001, -2, -1.999, 0, 1.999, 2, 2.001, 5.999, 6, 6.001, 8], y <- [0, 0.5, 1.5, 2], z <- [0, 0.25]] $ \source -> do
      let p = orient source
          actual = fst (sample repeated p)
          expected = minimum [fst (sample unit (subtractV p (orient (fromIntegral n * period, 0, 0)))) | n <- [-4 .. 4 :: Int]]
          adjacent = zipV (+) p (orient (0.0001, 0, 0))
          after = fst (sample repeated adjacent)
      unless (abs (actual - expected) < 1e-9) (fail ("Periodic field equals the union of translated geometry: " ++ show (alongZ, p, actual, expected)))
      unless (abs (after - actual) <= norm (subtractV adjacent p) + 1e-9) (fail "Periodic field is continuous across cell boundaries")
  putStrLn "Passed: repeated geometry agrees with translated copies on X and Z."
