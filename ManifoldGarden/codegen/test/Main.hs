module Main (main) where

import Control.Monad (foldM, forM_, unless)
import Data.Bits (shiftL, shiftR, (.&.))
import Data.Either (isLeft)
import Data.Maybe (fromMaybe)
import GravitySpec qualified
import JoinerySpec qualified
import Manifold.Pipeline
import Manifold.Program
import Manifold.Protocol
import ObjectsSpec qualified
import StageCollisionSpec qualified
import StageSpec qualified
import System.Environment (getArgs)

main :: IO ()
main = do
  args <- getArgs
  if args == ["joinery"] then JoinerySpec.checks else allChecks

allChecks :: IO ()
allChecks = do
  JoinerySpec.checks
  ObjectsSpec.run
  GravitySpec.checks
  StageSpec.checks
  StageCollisionSpec.checks
  forM_ [Play, Diagnostic] $ \profile -> either fail pure (validate (pipeline profile))
  let smallest = map (negate . fieldBias) header
      largest = map (\f -> 2 ^ fieldWidth f - fieldBias f - 1) header
      examples =
        [smallest, largest]
          ++ [ [fromMaybe (-fieldBias field) (lookup (fieldName field) values) | field <- header]
             | q <- [0 .. 3],
               x <- [0, 1, 131071],
               f <- [0 .. 23],
               seqNo <- [0, 1, 31, 32, 65535],
               fly <- [0, 1],
               let values = [("enabled", 1), ("quality", q), ("period", 64), ("g.x", x), ("g.y", 32768), ("g.z", 262143), ("g.frame", f), ("g.seq", seqNo), ("g.epoch", 1), ("g.fly", fly), ("h.mode", 3), ("h.slot", 1), ("h.level", 2), ("r.window0", f `mod` 8), ("r.window1", (f + 3) `mod` 8)]
             ]
  forM_ examples $ \values -> do
    encoded <- either fail pure (pack values)
    unless (unpack encoded == values) (fail "Controller transport round trip")
    let fragments =
          [ (wordIndex p, shiftL (shiftR (value + fieldBias f) (valueShift p) .&. (2 ^ pieceWidth p - 1)) (wordShift p))
          | ((offset, f), value) <- zip fieldOffsets values,
            p <- pieces offset (fieldWidth f)
          ]
    unless (encoded == [sum [v | (j, v) <- fragments, j == i] | i <- [0 .. headerWords - 1]]) (fail "Command fragments implement the transport layout")
  unless (isLeft (pack (drop 1 smallest))) (fail "Protocol field count is checked")
  forM_ (zip [0 ..] header) $ \(i, f) -> do
    let replace x = take i smallest ++ [x] ++ drop (i + 1) smallest
    unless (isLeft (pack (replace (-fieldBias f - 1))) && isLeft (pack (replace (2 ^ fieldWidth f - fieldBias f)))) (fail "Protocol bounds are checked")
  _ <-
    foldM
      ( \previous values -> do
          expected <- either fail pure (pack values)
          (cache, dirty) <- either fail pure (updatePacket previous values)
          let changed = maybe [0 .. headerWords - 1] (\old -> [i | (i, (a, b)) <- zip [0 ..] (zip (cachedWords old) expected), a /= b]) previous
          unless (cachedWords cache == expected && dirty == changed) (fail "Incremental transport preserves the payload and updates exactly the changed words")
          pure (Just cache)
      )
      Nothing
      (concatMap (\values -> [values, values]) examples)
  let target = Target "state"
      spec = TargetSpec target (Fixed 32 1) True
  unless (isLeft (validate (Pipeline [spec] [pass "copy" [Color "In" target] target]))) (fail "Render passes cannot read and write the same target")
  putStrLn "Passed: controller protocol, command encoding and render graph."
