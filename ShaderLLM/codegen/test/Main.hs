module Main (main) where

import Control.Monad (forM_, unless)
import Data.Either (isLeft)
import Qwen.GLSL qualified as G
import Qwen.Operator (compileOperator, inputs, usesNorms, usesWeights)
import Qwen.Shader qualified as Shader
import System.Directory (doesDirectoryExist, listDirectory)
import System.FilePath (takeExtension, (</>))

assert :: String -> Bool -> IO ()
assert label result = unless result (fail label)

roundTrip :: String -> G.TranslationUnit -> IO ()
roundTrip label ast = do
  parsed <- either fail pure (G.parseUnit label (G.renderUnit ast))
  assert (label ++ ": AST round-trip changed semantics") (parsed == ast)

main :: IO ()
main = do
  let expressions =
        [ G.uint (2214592512 :: Integer),
          G.uint (4294967295 :: Integer),
          G.int (-7),
          G.float 1.0e-6,
          G.Binary G.Sub (G.var "a") (G.Binary G.Sub (G.var "b") (G.var "c")),
          G.Binary G.Mul (G.Binary G.Add (G.var "a") (G.var "b")) (G.var "c"),
          G.arrayAt G.UInt (map G.uint ([0, 2147483648, 4294967295] :: [Integer])) (G.field "State" "z"),
          G.Selection (G.Binary G.And (G.var "a") (G.var "b")) (G.var "c") (G.var "d")
        ]
  forM_ expressions $ \expression ->
    roundTrip "expression" $
      G.TranslationUnit [G.function G.UInt "evaluate" [(G.Int, "i")] [G.Return (Just expression)]]
  roundTrip "constant arrays" (G.TranslationUnit [G.constantArray G.Int "ids" (map G.int ([0 .. 255] :: [Int]))])
  let program = G.TranslationUnit (map G.samplerUniform ["Control", "Weights0"])
  assert "bound sampler interface" (G.validateBindings ["Control", "Weights0"] [program] == Right ())
  assert "missing binding must fail" (isLeft (G.validateBindings ["Control"] [program]))
  assert "unused binding must fail" (isLeft (G.validateBindings ["Control", "Weights0", "Weights1"] [program]))
  assert "duplicate binding must fail" (isLeft (G.validateBindings ["Control", "Control", "Weights0"] [program]))
  forM_ [(phase, op, slot) | phase <- [1 .. 4], op <- [minBound .. maxBound], slot <- [0 .. 3]] $ \(phase, op, slot) -> do
    let G.Shader _ ast = Shader.vertex phase op slot
    roundTrip "vertex scheduling" ast
  root <- findShaders ["shaders", "../shaders"]
  forM_ [minBound .. maxBound] $ \op -> do
    let samplers = ["Control"] ++ inputs op ++ ["Norms" | usesNorms op] ++ ["Weights0" | usesWeights op]
    G.Shader _ ast <- compileOperator root op samplers (Shader.operatorSetup op 128 (G.int 0) 256 0) [] 128
    roundTrip (show op) ast
    assert (show op ++ ": sampler interface") (G.validateBindings samplers [ast] == Right ())
  files <- listDirectory root
  forM_ [root </> file | file <- files, takeExtension file `elem` [".vsh", ".fsh", ".glsl"]] $ \path -> do
    ast <- either fail pure . G.parseShader path =<< readFile path
    roundTrip path ast
  putStrLn "Shader AST round-trips, operator composition and binding checks passed."
  where
    findShaders [] = fail "Cannot find Qwen shader sources"
    findShaders (path : paths) = do
      exists <- doesDirectoryExist path
      if exists then pure path else findShaders paths
