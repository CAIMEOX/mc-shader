module Main (main) where

import Signal.Fall qualified as Fall
import Signal.Pack (generate, generateWithLevels)
import Signal.PingPong qualified as PingPong
import Signal.RotateStream qualified as RotateStream
import System.Environment (getArgs)
import Text.Read (readMaybe)

main :: IO ()
main = do
  args <- getArgs
  case args of
    [root, "fall", seed] | Just value <- readMaybe seed -> Fall.generate root value
    [root, "rotate-stream", seed] | Just value <- readMaybe seed -> RotateStream.generate root value
    [root, "pingpong", message] -> PingPong.generate root message
    [root] -> generate root 1000 [200, 500, 1000, 2000]
    [root, start, rates]
      | Just first <- readMaybe start,
        Just targets <- traverse readMaybe (words (map (\c -> if c == ',' then ' ' else c) rates)) ->
          generate root first targets
    [root, start, rates, levels]
      | Just first <- readMaybe start,
        Just targets <- integers rates,
        Just powers <- integers levels ->
          generateWithLevels root first targets powers
    _ -> fail "Usage: signal-codegen <signal-directory> [payload-start rates-comma-separated [four-powers-comma-separated] | pingpong message | fall seed | rotate-stream seed]"
  where
    integers = traverse readMaybe . words . map (\c -> if c == ',' then ' ' else c)
