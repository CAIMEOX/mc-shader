{-# LANGUAGE OverloadedStrings #-}

module Qwen.Pipeline (compilePipeline) where

import Control.Monad (forM_, unless)
import Data.Aeson
import Data.Aeson.Key qualified as Key
import Data.Aeson.KeyMap qualified as K
import Data.ByteString.Lazy qualified as B
import Data.List (nub)
import Data.Map.Strict qualified as M
import Qwen.GLSL qualified as G
import Qwen.Layout qualified as L
import Qwen.Limits
import Qwen.Model hiding (matrices, norms)
import Qwen.Operator
import Qwen.Shader qualified as Shader
import System.Directory (createDirectoryIfMissing, doesFileExist)
import System.FilePath (takeBaseName, (</>))

-- Logical element count is distinct from the physical target extent.
data Stage = Stage String Operator Int Int Int Int G.Expr [(String, String)] [L.Matrix] Int deriving (Show)

data Input = TargetInput String String | TextureInput String String Int Int

inputName :: Input -> String
inputName (TargetInput name _) = name
inputName (TextureInput name _ _ _) = name

instance ToJSON Input where
  toJSON (TargetInput name target) = object ["sampler_name" .= name, "target" .= target]
  toJSON (TextureInput name file w h) =
    object
      ["sampler_name" .= name, "location" .= ("qwen:" ++ file), "width" .= w, "height" .= h, "bilinear" .= False]

data Pass = Pass String String [Input] String

instance ToJSON Pass where
  toJSON (Pass fragment vertex ins target) =
    object
      ["vertex_shader" .= ("qwen:" ++ vertex), "fragment_shader" .= ("qwen:" ++ fragment), "inputs" .= ins, "output" .= target]

compilePipeline :: FilePath -> FilePath -> FilePath -> IO ()
compilePipeline model shaders output = do
  layout <- either fail pure . eitherDecode =<< B.readFile (model </> "weights.json")
  either fail pure (L.validateLayout layout)
  let c = L.config layout
  (cacheWidth, cacheHeight) <- either fail pure (L.cacheExtent c contextSize)
  constants <- either fail pure (modelConstants c)
  let matrices = M.fromList [(L.name m, m) | m <- L.matrices layout]
      normBases = M.fromList [(L.normName n, L.normBase n) | n <- L.norms layout]
      d = hidden_size c
      ff = intermediate_size c
      q = querySize c
      kv = kvSize c
      heads = num_attention_heads c
      layerKeys field = [layerName l field | l <- [0 .. num_hidden_layers c - 1]]
      matrixGroup field = [matrices M.! key | key <- layerKeys field]
      norm field = G.arrayAt G.Int [G.int (normBases M.! key) | key <- layerKeys field] (G.field "State" "z")
      embedding = [matrices M.! "model.embed_tokens.weight"]
      classifier = if tie_word_embeddings c then embedding else [matrices M.! "lm_head.weight"]
      input t = [("Input0", t)]
      pair a b = [("Input0", a), ("Input1", b)]
      s name op columns count phase offset ins weights =
        let (w, h) = L.vectorExtent count in Stage name op columns w h phase offset ins weights count
      extent w h (Stage name op columns _ _ phase offset ins weights count) = Stage name op columns w h phase offset ins weights count
      rms name source base phase = [s (name ++ "_ss") SumSquares d (d `div` 32) phase (G.int 0) (input source) [], s name RmsApply d d phase base (pair source (name ++ "_ss")) []]
      quant name source n phase = [s (name ++ "_scale") QuantScale n (n `div` 64) phase (G.int 0) (input source) [], s name Quantize n (n `div` 64 * 17) phase (G.int 0) (pair source (name ++ "_scale")) []]
      mm name source field columns count = s name Gemv columns count 3 (G.int 0) (input source) (matrixGroup field)
      stages =
        concat
          [ [s "embedding" Embedding d d 2 (G.int 0) [] embedding, s "embed_x" Copy d d 2 (G.int 0) (input "embedding") []],
            rms "norm_att" "x" (norm "input_layernorm.weight") 3,
            quant "aq" "norm_att" d 3,
            [ mm "q_proj" "aq" "self_attn.q_proj.weight" d q,
              mm "k_proj" "aq" "self_attn.k_proj.weight" d kv,
              mm "v_proj" "aq" "self_attn.v_proj.weight" d kv,
              s "q_rope" Rope 0 q 3 (norm "self_attn.q_norm.weight") (input "q_proj") [],
              s "k_rope" Rope 0 kv 3 (norm "self_attn.k_norm.weight") (input "k_proj") [],
              extent cacheWidth cacheHeight (s "keys" CacheStore 0 (cacheWidth * cacheHeight) 3 (G.int 0) (input "k_rope") []),
              extent cacheWidth cacheHeight (s "values" CacheStore 0 (cacheWidth * cacheHeight) 3 (G.int 0) (input "v_proj") []),
              extent contextSize heads (s "scores" Scores 0 (contextSize * heads) 3 (G.int 0) (input "q_rope") []),
              s "stats" SoftmaxStats 0 (heads * 2) 3 (G.int 0) (input "scores") [],
              extent contextSize heads (s "softmax" SoftmaxApply 0 (contextSize * heads) 3 (G.int 0) (pair "scores" "stats") []),
              s "attention" Attention 0 q 3 (G.int 0) (input "softmax") []
            ],
            quant "joinedq" "attention" q 3,
            [mm "o_proj" "joinedq" "self_attn.o_proj.weight" q d, s "res_att" Residual 0 d 3 (G.int 0) (pair "x" "o_proj") []],
            rms "norm_ff" "res_att" (norm "post_attention_layernorm.weight") 3,
            quant "fq" "norm_ff" d 3,
            [mm "gate" "fq" "mlp.gate_proj.weight" d ff, mm "up" "fq" "mlp.up_proj.weight" d ff, s "swiglu" SwiGlu 0 ff 3 (G.int 0) (pair "gate" "up") []],
            quant "hq" "swiglu" ff 3,
            [mm "down" "hq" "mlp.down_proj.weight" ff d, s "layer_out" Residual 0 d 3 (G.int 0) (pair "res_att" "down") [], s "layer_x" Copy 0 d 3 (G.int 0) (input "layer_out") []],
            rms "final_norm" "x" (G.int (normBases M.! "model.norm.weight")) 4,
            quant "finalq" "final_norm" d 4,
            [ extent 512 (L.ceilDiv (vocab_size c) 512) (s "logits" Gemv d (vocab_size c) 4 (G.int 0) (input "finalq") classifier),
              s "partial" ArgmaxPartial (vocab_size c) (2 * L.ceilDiv (vocab_size c) 256) 4 (G.int 0) (input "logits") [],
              s "choice" ArgmaxFinal (L.ceilDiv (vocab_size c) 256) 2 4 (G.int 0) (input "partial") []
            ]
          ]
      ordered =
        [(stage, 0) | stage@(Stage _ _ _ _ _ phase _ _ _ _) <- stages, phase == 2]
          ++ [(stage, slot) | slot <- [0 .. layersPerFrame - 1], stage@(Stage _ _ _ _ _ phase _ _ _ _) <- stages, phase == 3]
          ++ [(stage, 0) | stage@(Stage _ _ _ _ _ phase _ _ _ _) <- stages, phase == 4]
      shaderName name phase slot = if phase == 3 then "layer" ++ show slot ++ "_" ++ name else name
      actual name = if name `elem` ["embed_x", "layer_x"] then "x" else name
      target name w h = (Key.fromString name, object ["width" .= w, "height" .= h, "persistent" .= True])
      specs = nub ([(actual name, w, h) | Stage name _ _ w h _ _ _ _ _ <- stages] ++ [("packet", 32, 5), ("control_a", 12, 1), ("control_b", 12, 1), ("tokens", 130, 1), ("output_a", outputBytes, 1), ("output_b", outputBytes, 1), ("generated_a", maxGeneration, 1), ("generated_b", maxGeneration, 1), ("text_layout", 1, 1), ("text_grid", 32, 9)])
      sample = TargetInput
      texture = TextureInput
      pass = Pass
      ctrl = [sample "Control" "control_a"]
      capacity = toInteger (L.page_width layout) * toInteger (L.page_height layout)
      window weights = if null weights then [] else L.pageWindow capacity weights
      weightInputs weights = [texture ("Weights" ++ show local) (takeBaseName (L.file page)) (L.width page) (L.height page) | (local, index) <- zip [0 :: Int ..] (window weights), let page = L.pages layout !! index]
      stagePass (Stage name op _ _ _ phase _ ins weights _, slot) =
        let dependency key = case key of "Keys" -> "keys"; "Values" -> "values"; _ -> maybe (error ("Missing operator input " ++ key)) id (lookup key ins)
            resources =
              [sample key (dependency key) | key <- inputs op]
                ++ [texture "Norms" "norms" (L.normWidth layout) (L.normHeight layout) | usesNorms op]
                ++ weightInputs weights
            file = shaderName name phase slot
         in pass file (file ++ "_vertex") (ctrl ++ resources) (actual name)
  forM_ specs $ \(_, w, h) -> unless (w > 0 && h > 0 && w <= 16384 && h <= 16384) (fail "Generated target exceeds texture limits")
  -- Tokenizer texture extents come from the compiled tokenizer resources.
  Object tokenizer <- either fail pure . eitherDecode =<< B.readFile (model </> "../tokenizer/tokenizer-layout.json")
  let field o key = maybe (error ("Missing tokenizer layout " ++ show key)) id (K.lookup key o)
      shape value = case fromJSON value of Success o -> o :: M.Map String Int; Error e -> error e
      tex name file value = let dims = shape value in texture name file (dims M.! "width") (dims M.! "height")
      unicodeFields = case field tokenizer "unicode" of Object o -> o; _ -> error "Unicode layout must be an object"
      unicode =
        [ tex "UnicodeMeta" "unicode_meta" (field unicodeFields "meta"),
          tex "UnicodeNfd" "unicode_nfd" (field unicodeFields "nfd"),
          tex "UnicodeCompose" "unicode_compose" (field unicodeFields "compose"),
          tex "SpecialMeta" "special_meta" (field tokenizer "special_meta"),
          tex "SpecialChars" "special_chars" (field tokenizer "special_chars"),
          tex "Merges" "merges" (field tokenizer "merges")
        ]
      tokenData = [tex "TokenMeta" "token_meta" (field tokenizer "token_meta"), tex "TokenBytes" "token_bytes" (field tokenizer "token_bytes")]
      passes =
        [pass "packet" "screen" [sample "Main" "minecraft:main"] "packet", pass "begin" "screen" [sample "Control" "control_b", sample "Packet" "packet"] "control_a", pass "tokenizer" "tokenizer_vertex" (ctrl ++ [sample "Packet" "packet"] ++ unicode) "tokens"]
          ++ map stagePass ordered
          ++ [ pass "output" "screen" (ctrl ++ [sample "Previous" "output_b", sample "Choice" "choice"] ++ tokenData) "output_a",
               pass "generated" "screen" (ctrl ++ [sample "Previous" "generated_b", sample "Choice" "choice"]) "generated_a",
               pass "end" "screen" (ctrl ++ [sample "Tokens" "tokens", sample "Choice" "choice"] ++ tokenData) "control_b",
               pass "copy" "screen" [sample "Previous" "output_a"] "output_b",
               pass "copy" "screen" [sample "Previous" "generated_a"] "generated_b",
               pass "layout" "format" (ctrl ++ [sample "Output" "output_b", sample "Result" "control_b"]) "text_layout",
               pass "grid" "format" (ctrl ++ [sample "Output" "output_b", sample "Result" "control_b", sample "Layout" "text_layout"]) "text_grid",
               pass "display" "screen" [sample "Main" "minecraft:main", sample "Grid" "text_grid", sample "Control" "control_b", texture "Glyphs" "glyphs" 4096 2176] "present",
               pass "copy" "screen" [sample "Previous" "present"] "minecraft:main"
             ]
      targets = K.fromList ([target name w h | (name, w, h) <- specs] ++ [("present", object [])])
  let tokenizerVocab = case fromJSON (field tokenizer "vocab_size") of Success n -> n :: Int; Error e -> error e
  unless (tokenizerVocab == vocab_size c) (fail "Tokenizer vocabulary differs from Config")
  createDirectoryIfMissing True output
  writeFile (output </> "limits.glsl") shaderLimits
  writeFile (output </> "model.glsl") constants
  B.writeFile
    (output </> "limits.json")
    ( encode
        ( object
            [ "config" .= c,
              "context_size" .= contextSize,
              "max_generation" .= maxGeneration,
              "output_bytes" .= outputBytes,
              "cache_width" .= cacheWidth,
              "cache_height" .= cacheHeight,
              "layers_per_frame" .= layersPerFrame,
              "head_frames" .= (1 :: Int),
              "logical_elements" .= object [Key.fromString (actual key) .= count | Stage key _ _ _ _ _ _ _ _ count <- stages],
              "weight_windows" .= object [Key.fromString key .= window weights | Stage key _ _ _ _ _ _ _ weights _ <- stages, not (null weights)]
            ]
        )
    )
  B.writeFile (output </> "pipeline.json") (encode (object ["targets" .= Object targets, "passes" .= passes]))
  forM_ ordered $ \(Stage name op n w _ phase offset _ weights count, slot) -> do
    let setup = Shader.operatorSetup op n offset w slot ++ Shader.weightSetup layout weights
        samplers = ["Control"] ++ inputs op ++ ["Norms" | usesNorms op] ++ ["Weights" ++ show i | i <- [0 .. length (window weights) - 1]]
        file = shaderName name phase slot
    source <- compileOperator shaders op samplers setup (Shader.weightReader layout weights) count
    writeFile (output </> file ++ ".fsh") (G.renderShader source)
    writeFile (output </> file ++ "_vertex.vsh") (G.renderShader (Shader.vertex phase op slot))
  writeFile (output </> "tokenizer_vertex.vsh") (G.renderShader (Shader.vertex 1 Copy 0))
  forM_ passes $ \(Pass fragment vertex ins _) -> do
    programs <- mapM readProgram [vertex ++ ".vsh", fragment ++ ".fsh"]
    either (fail . ((fragment ++ ": ") ++)) pure (G.validateBindings (map inputName ins) programs)
  where
    readProgram file = do
      generated <- doesFileExist (output </> file)
      let path = (if generated then output else shaders) </> file
      either fail pure . G.parseShader path =<< readFile path
