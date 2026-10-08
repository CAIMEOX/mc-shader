module Main (main) where

import Backrooms.Pack (generate)
import System.Environment (getArgs)

main :: IO ()
main = do
  args <- getArgs
  case args of
    ["build", root] -> generate root
    _ -> fail "Usage: backrooms-codegen build <backrooms-directory>"
