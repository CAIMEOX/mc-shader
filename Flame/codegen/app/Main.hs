module Main (main) where

import Flame.Domain (standard)
import Flame.Pack (generate)
import System.Environment (getArgs)

main :: IO ()
main = do
  args <- getArgs
  case args of
    ["build", root] -> generate root standard
    _ -> fail "Usage: flame-codegen build <flame-directory>"
