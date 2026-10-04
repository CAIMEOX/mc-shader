module Main (main) where

import Control.Monad (forM_, unless)
import Data.Bits (shiftL, shiftR, (.&.))
import Data.Either (isLeft)
import Escher.Pipeline
import Escher.Program (pipeline)
import Escher.Protocol
import Escher.Scene
import Escher.Space
import FoldingSpec qualified
import SceneSpec qualified

main :: IO ()
main = do
  SceneSpec.checks
  FoldingSpec.checks
  either fail pure (validate pipeline)
  checkInvalidPipelines
  forM_ [Mapping 18 s t | s <- [0.5, 0.64, 0.95], t <- [0, 0.4, 1.1]] $ \m ->
    forM_ [(x, y, z) | x <- [-7, 0, 4], y <- [-4, 0, 5], z <- [-40, 0, 7, 18, 43]] $ \p@(x, y, z) -> do
      near "Coordinate inverse" p (pullback m (embed m p))
      near "Planar gluing" (embed m (x, y, z + period m)) (similarity m 1 (embed m p))
      forM_ [-5 .. 5 :: Int] $ \n -> do
        let q = (x, y, z + period m * fromIntegral n)
        near "Periodic collision geometry" (fst (sample gallery p), 0, 0) (fst (sample gallery q), 0, 0)
  forM_ [[x, y, z, 18, s, t, enabled, q, scene, amount, 1, 1, 0] | x <- [-30000000, 0, 30000000], y <- [-64, 70, 320], z <- [-12345, 56789], s <- [512, 655, 1004], t <- [-1000, 399, 1900], enabled <- [0, 1], q <- [0 .. 3], scene <- [0, 1], amount <- [0, 500, 1000]] $ \values ->
    case pack values of
      Left e -> fail e
      Right encoded -> do
        unless (unpack encoded == values && length encoded == headerWords) (fail "Region transport round-trip")
        let fragments =
              [ (wordIndex p, shiftL (shiftR (value + fieldBias f) (valueShift p) .&. (2 ^ pieceWidth p - 1)) (wordShift p))
              | ((offset, f), value) <- zip fieldOffsets values,
                p <- pieces offset (fieldWidth f)
              ]
            reconstructed = [sum [v | (j, v) <- fragments, j == i] | i <- [0 .. headerWords - 1]]
        unless (encoded == reconstructed) (fail "Command fragments implement the protocol layout")
  let smallest = map (negate . fieldBias) header
  unless (isLeft (pack (drop 1 smallest))) (fail "Field count is validated")
  forM_ (zip [0 ..] header) $ \(i, f) -> do
    let replace x = take i smallest ++ [x] ++ drop (i + 1) smallest
    unless (isLeft (pack (replace (-fieldBias f - 1))) && isLeft (pack (replace (2 ^ fieldWidth f - fieldBias f)))) (fail "Encoded field ranges are validated")
  forM_ [-1e9, -36.01, -0.001, 0, 35.999, 1e9] $ \z -> unless (wrap 18 z >= 0 && wrap 18 z < 18) (fail "Signed coordinate folding")
  unless (all (\x -> fst (sample gallery (x, -5.5, 4)) < 0) [-6 .. 6]) (fail "Continuous walkable floor")
  unless (all (\z -> fst (sample gallery (0, -3.38, z)) > 0) [0, 0.1 .. 36]) (fail "Walkway headroom")
  putStrLn "Passed: space, periodic geometry, walking clearance, protocol round trips, command fragments and pipeline references."
  where
    near name a b = unless (norm (subtractV a b) < 1e-7) (fail name)

checkInvalidPipelines :: IO ()
checkInvalidPipelines = do
  let target = Target "state"
      missing = Target "missing"
      spec = TargetSpec target (Fixed 8 1) True
      invalid =
        [ Pipeline [spec] [pass "copy" [Color "In" target] target],
          Pipeline [spec] [pass "copy" [Color "In" missing] target],
          Pipeline [spec, spec] [],
          Pipeline [TargetSpec target (Fixed 0 1) False] [],
          Pipeline [spec] [pass "copy" [Color "In" mainTarget, Color "In" mainTarget] target]
        ]
  forM_ invalid $ \p -> unless (isLeft (validate p)) (fail "Invalid render graph is rejected")
