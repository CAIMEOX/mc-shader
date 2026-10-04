module Main (main) where

import Escher.Pack (generate)
import System.Environment (getArgs)

main :: IO ()
main = do
  args <- getArgs
  case args of
    ["build", root] -> generate root
    _ -> fail "Usage: escher-codegen build <escher-directory>"
