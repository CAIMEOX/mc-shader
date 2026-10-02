module Main (main) where

import Control.Monad (unless)
import Data.Bits (popCount, shiftL, shiftR, (.&.))
import Data.Either (isLeft)
import Data.List (nub)
import Flame.Domain
import Flame.Pipeline
import Flame.Program (makePipeline)
import Flame.Protocol

main :: IO ()
main = do
  assert "28 canonical collision shapes" (length shapeMasks == 28 && length (nub shapeMasks) == 28)
  assert "40 stair block states" (length stairs == 40)
  mapM_ checkStair stairs
  let positions = coordinates (grid standard)
  assert "Grid addressing round trip" (all (\p -> unlinear (grid standard) (linear (grid standard) p) == p) positions)
  mapM_ checkPacking [1, 4, 5, 24, 256, 2048]
  let headerValues = zipWith (\f x -> (fieldWidth f, x)) header [999, 33554432 + 30000000, 2048 - 64, 33554432 - 30000000, 10237, 511, 2]
  encoded <- either fail pure (packValues headerValues)
  assert "Header field round trip" (unpackValues (map fst headerValues) encoded == map snd headerValues)
  assert "Field range validation" (isLeft (packValues [(5, 32)]))
  either fail pure (validate (makePipeline standard))
  let target = Target "state"
      bad = Pipeline [TargetSpec target (Fixed 8 1) True] [pass "copy" [Color "In" target] target]
  assert "Pipeline rejects read/write aliasing" (isLeft (validate bad))
  putStrLn "Haskell checks passed: collision shapes, grid addressing, bit packing, header ranges, pipeline references"
  where
    assert label ok = unless ok (fail label)
    checkStair stair@(Stair _ _ turn) =
      let expected = case turn of
            Straight -> 6
            InnerLeft -> 7
            InnerRight -> 7
            OuterLeft -> 5
            OuterRight -> 5
       in assert "Stair volume" (popCount (stairMask stair) == expected)
    checkPacking n = do
      let values = take n (cycle [s + 32 * m | m <- [0 .. 3], s <- [0 .. 28]])
          fields = map (7,) values
      encoded <- either fail pure (packValues fields)
      assert "Shape and material payload round trip" (unpackValues (replicate n 7) encoded == values)
      let piecesByWord = [(wordIndex p, shiftL (shiftR value (valueShift p) .&. (2 ^ pieceWidth p - 1)) (wordShift p)) | (i, value) <- zip [0 ..] values, p <- pieces (7 * i) 7]
          reconstructed = [sum [v | (j, v) <- piecesByWord, j == i] | i <- [0 .. length encoded - 1]]
      assert "Command fragments implement the same bit layout" (encoded == reconstructed)
