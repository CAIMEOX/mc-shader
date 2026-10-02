{-# LANGUAGE OverloadedStrings #-}

module Qwen.Operator (Operator (..), inputs, usesWeights, usesNorms, compileOperator) where

import Data.Char (toLower)
import Qwen.GLSL qualified as G
import System.FilePath ((</>))

data Operator
  = Embedding
  | SumSquares
  | RmsApply
  | Quantize
  | Gemv
  | Rope
  | CacheStore
  | Scores
  | SoftmaxStats
  | SoftmaxApply
  | Attention
  | Residual
  | SwiGlu
  | Copy
  | ArgmaxPartial
  | ArgmaxFinal
  | QuantScale
  deriving (Eq, Enum, Bounded, Show)

inputs :: Operator -> [String]
inputs op = case op of
  Embedding -> []
  RmsApply -> ["Input0", "Input1"]
  Quantize -> ["Input0", "Input1"]
  SoftmaxApply -> ["Input0", "Input1"]
  Residual -> ["Input0", "Input1"]
  SwiGlu -> ["Input0", "Input1"]
  Scores -> ["Input0", "Keys"]
  Attention -> ["Input0", "Values"]
  _ -> ["Input0"]

usesWeights, usesNorms :: Operator -> Bool
usesWeights op = op `elem` [Embedding, Gemv]
usesNorms op = op `elem` [RmsApply, Rope]

compileOperator :: FilePath -> Operator -> [String] -> [G.Statement] -> [G.ExternalDeclaration] -> Int -> IO G.Shader
compileOperator root op samplers setup reader count = do
  let path = root </> "operators" </> map toLower (show op) ++ ".glsl"
      helperPath = root </> "operators/weights.glsl"
  body <- either fail pure . G.parseBody path =<< readFile path
  G.TranslationUnit helper <-
    if op == Gemv
      then either fail pure . G.parseUnit helperPath =<< readFile helperPath
      else pure (G.TranslationUnit [])
  pure $
    G.Shader ["qwen:codec.glsl", "qwen:limits.glsl", "qwen:model.glsl"] $
      G.TranslationUnit $
        map G.samplerUniform samplers
          ++ [ G.Declaration (G.declaration [] G.IVec4 [("Params", Nothing), ("State", Nothing)]),
               G.Declaration (G.declaration [] G.UVec2 [("WeightBase", Nothing)]),
               G.Declaration
                 ( G.declaration
                     [G.TypeQualLay (G.Layout [G.LayoutQualId "location" (Just (G.int 0))]), G.TypeQualSto G.Out]
                     G.Vec4
                     [("fragColor", Nothing)]
                 )
             ]
          ++ reader
          ++ helper
          ++ [ G.function G.Void "main" [] $
                 setup
                   ++ [ G.local
                          G.Int
                          "i"
                          ( G.Binary
                              G.Add
                              (G.construct G.Int [G.field "gl_FragCoord" "x"])
                              (G.Binary G.Mul (G.construct G.Int [G.field "gl_FragCoord" "y"]) (G.field "Params" "w"))
                          ),
                        G.ifThen (G.Binary G.Gte (G.var "i") (G.int count)) [G.Discard],
                        G.local G.Int "n" (G.field "Params" "y"),
                        G.local G.Int "b" (G.field "Params" "z"),
                        G.local G.Float "outValue" (G.float 0)
                      ]
                   ++ body
                   ++ [G.set (G.var "fragColor") (G.call "packF" [G.var "outValue"])]
             ]
