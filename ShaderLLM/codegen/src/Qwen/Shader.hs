module Qwen.Shader (vertex, weightSetup, weightReader, operatorSetup) where

import Qwen.GLSL qualified as G
import Qwen.Layout qualified as L
import Qwen.Operator (Operator (..))

control :: Int -> G.Expr
control n = G.call "integer" [G.sampler "Control", G.int n]

vertex :: Int -> Operator -> Int -> G.Shader
vertex phase op slot =
  G.Shader ["qwen:codec.glsl", "qwen:limits.glsl", "qwen:model.glsl"] $
    G.TranslationUnit [G.samplerUniform "Control", G.function G.Void "main" [] statements]
  where
    statements =
      [ G.local G.Int "phase" (G.construct G.Int [control 0]),
        G.local G.UInt "layer" (G.Binary G.Add (control 3) (G.uint slot)),
        G.local
          G.Vec2
          "p"
          ( G.construct
              G.Vec2
              [ G.Binary G.BitAnd (G.Binary G.LeftShift (G.var "gl_VertexIndex") (G.int 1)) (G.int 2),
                G.Binary G.BitAnd (G.var "gl_VertexIndex") (G.int 2)
              ]
          )
      ]
        ++ rectangle
        ++ [ G.set
               (G.var "gl_Position")
               ( G.Selection
                   active
                   (G.construct G.Vec4 [G.Binary G.Sub (G.Binary G.Mul (G.var "p") (G.float 2)) (G.float 1), G.int 0, G.int 1])
                   (G.construct G.Vec4 (map G.int ([2, 2, 2, 1] :: [Int])))
               )
           ]
    active =
      if phase == 3
        then G.Binary G.And phaseMatch (G.Binary G.Lt (G.var "layer") (G.construct G.UInt [G.var "LAYER_COUNT"]))
        else phaseMatch
    phaseMatch = G.Binary G.Equ (G.var "phase") (G.int phase)
    rectangle
      | op == CacheStore =
          [ G.local G.UInt "row" (G.Binary G.Add (G.Binary G.Mul (G.var "layer") (G.construct G.UInt [G.var "CONTEXT_SIZE"])) (control 2)),
            coordinate "x" G.Mod "CACHE_ROWS_PER_LINE",
            coordinate "y" G.Div "CACHE_HEIGHT"
          ]
      | op `elem` [Scores, SoftmaxApply] =
          [ G.ExpressionStatement
              ( Just
                  ( G.Binary
                      G.MulAssign
                      (G.field "p" "x")
                      ( G.Binary
                          G.Div
                          (G.construct G.Float [G.Binary G.Add (control 2) (G.uint (1 :: Int))])
                          (G.construct G.Float [G.var "CONTEXT_SIZE"])
                      )
                  )
              )
          ]
      | otherwise = []
    coordinate axis operation denominator =
      G.set (G.field "p" axis) $
        G.Binary
          G.Div
          ( G.Binary
              G.Add
              (G.construct G.Float [G.Binary operation (G.var "row") (G.construct G.UInt [G.var "CACHE_ROWS_PER_LINE"])])
              (G.field "p" axis)
          )
          (G.construct G.Float [G.var denominator])

-- Split the potentially 64-bit global address before constructing GLSL uints.
weightSetup :: L.ModelLayout -> [L.Matrix] -> [G.Statement]
weightSetup _ [] = []
weightSetup layout weights = [G.set (G.var "WeightBase") (G.construct G.UVec2 [select pages, select offsets])]
  where
    capacity = toInteger (L.page_width layout) * toInteger (L.page_height layout)
    first = toInteger (minimum (L.pageWindow capacity weights))
    pages = [L.base m `div` capacity - first | m <- weights]
    offsets = [L.base m `mod` capacity | m <- weights]
    select [x] = G.uint x
    select xs = G.arrayAt G.UInt (map G.uint xs) (G.field "State" "z")

weightReader :: L.ModelLayout -> [L.Matrix] -> [G.ExternalDeclaration]
weightReader _ [] = []
weightReader layout weights =
  [ G.function G.Vec4 "weight" [(G.UInt, "i")] $
      [ G.local G.UInt "local" (G.Binary G.Add (G.field "WeightBase" "y") (G.var "i")),
        G.local G.UInt "page" (G.Binary G.Add (G.field "WeightBase" "x") (G.Binary G.Div (G.var "local") (G.uint capacity))),
        G.local G.UInt "offset" (G.Binary G.Mod (G.var "local") (G.uint capacity)),
        G.local
          G.IVec2
          "xy"
          ( G.construct
              G.IVec2
              [G.Binary G.Mod (G.var "offset") (G.uint (L.page_width layout)), G.Binary G.Div (G.var "offset") (G.uint (L.page_width layout))]
          )
      ]
        ++ [ G.ifThen
               (G.Binary G.Equ (G.var "page") (G.uint index))
               [G.Return (Just (G.call "texelFetch" [G.sampler ("Weights" ++ show index), G.var "xy", G.int 0]))]
           | index <- [0 .. length (L.pageWindow capacity weights) - 1]
           ]
        ++ [G.Return (Just (G.construct G.Vec4 [G.int 0]))]
  ]
  where
    capacity = toInteger (L.page_width layout) * toInteger (L.page_height layout)

operatorSetup :: Operator -> Int -> G.Expr -> Int -> Int -> [G.Statement]
operatorSetup op columns offset width slot =
  [ G.set (G.var "State") (G.construct G.IVec4 [control 4, control 2, G.Binary G.Add (control 3) (G.uint slot), G.uint (0 :: Int)]),
    G.set (G.var "Params") (G.construct G.IVec4 [G.int (fromEnum op), G.int columns, offset, G.int width])
  ]
