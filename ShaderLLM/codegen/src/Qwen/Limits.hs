module Qwen.Limits where

import Qwen.GLSL qualified as G
import Qwen.Layout (cacheExtent)
import Qwen.Model

contextSize, maxGeneration, outputBytes, layersPerFrame :: Int
contextSize = 1024
maxGeneration = 256
outputBytes = 8192
layersPerFrame = 4

shaderLimits :: String
shaderLimits =
  G.renderUnit $
    G.TranslationUnit
      [ G.constant G.Int key (G.int value)
      | (key, value) <-
          [ ("CONTEXT_SIZE", contextSize),
            ("OUTPUT_BYTES", outputBytes),
            ("MAX_GENERATION", maxGeneration),
            ("LAYERS_PER_FRAME", layersPerFrame)
          ]
      ]

modelConstants :: Config -> Either String String
modelConstants c = do
  (cw, ch) <- cacheExtent c contextSize
  pure $
    G.renderUnit $
      G.TranslationUnit $
        [ G.constant G.Int key (G.int value)
        | (key, value) <-
            [ ("HIDDEN_SIZE", hidden_size c),
              ("FFN_SIZE", intermediate_size c),
              ("LAYER_COUNT", num_hidden_layers c),
              ("QUERY_HEADS", num_attention_heads c),
              ("KV_HEADS", num_key_value_heads c),
              ("HEAD_DIM", head_dim c),
              ("QUERY_SIZE", querySize c),
              ("KV_SIZE", kvSize c),
              ("KV_MULTIPLIER", kvMultiplier c),
              ("VOCAB_SIZE", vocab_size c),
              ("CACHE_WIDTH", cw),
              ("CACHE_HEIGHT", ch),
              ("CACHE_ROWS_PER_LINE", cw `div` kvSize c)
            ]
        ]
          ++ [ G.constant G.Float "RMS_EPS" (G.float (rms_norm_eps c)),
               G.constant G.Float "ROPE_THETA" (G.float (rope_theta c))
             ]
