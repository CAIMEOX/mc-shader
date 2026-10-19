module Main (main) where

import Manifold.Pack (generate)
import System.Environment (getArgs)

main :: IO ()
main = do
  args <- getArgs
  case args of
    ["build", root] -> generate root
    _ -> fail "Usage: manifold-codegen build PROJECT_ROOT"
