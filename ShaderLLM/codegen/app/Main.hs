module Main (main) where

import Qwen.Constants (compileConstants)
import Qwen.Datapack (compileDatapack)
import Qwen.Font (compileFonts)
import Qwen.Pipeline (compilePipeline)
import Qwen.Tokenizer (compileTokenizer)
import Qwen.Weights (compileWeights, compileWeightsWithPageSide, configureContext)
import System.Environment (getArgs)
import Text.Read (readMaybe)

main :: IO ()
main = do
  args <- getArgs
  case args of
    ["weights", source, output] -> compileWeights source output
    ["weights-page", source, output, size] -> case readMaybe size of Just n -> compileWeightsWithPageSide n source output; Nothing -> fail "Page size must be an integer"
    ["context", output] -> configureContext output
    ["tokenizer", source, output] -> compileTokenizer source output
    ["fonts", source, output] -> compileFonts source output
    ["constants", tokenizer, chat, output] -> compileConstants tokenizer chat output
    ["pipeline", model, shaders, output] -> compilePipeline model shaders output
    ["datapack", output] -> compileDatapack output
    _ -> fail "Commands: weights MODEL OUTPUT; tokenizer MODEL OUTPUT; fonts MODEL OUTPUT; constants TOKENIZER CHAT OUTPUT; pipeline MODEL SHADERS OUTPUT; datapack OUTPUT"
