{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE OverloadedStrings #-}

module Qwen.Model where

import Control.Monad (forM, unless)
import Data.Aeson
import Data.Aeson.Key qualified as K
import Data.Aeson.KeyMap qualified as KM
import Data.Binary.Get (getWord64le, runGet)
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as BL
import Data.Int (Int64)
import Data.Map.Strict qualified as M
import GHC.Generics (Generic)
import System.Directory (doesDirectoryExist, doesFileExist)
import System.FilePath (isRelative, splitDirectories, (</>))
import System.IO

data Config = Config
  { hidden_size :: Int,
    intermediate_size :: Int,
    num_hidden_layers :: Int,
    num_attention_heads :: Int,
    num_key_value_heads :: Int,
    head_dim :: Int,
    vocab_size :: Int,
    rms_norm_eps :: Float,
    rope_theta :: Float,
    tie_word_embeddings :: Bool
  }
  deriving (Eq, Show, Generic)

instance FromJSON Config

instance ToJSON Config

data Tensor = Tensor {dtype :: String, shape :: [Int], data_offsets :: [Int64]}
  deriving (Show, Generic)

instance FromJSON Tensor

data TensorLocation = TensorLocation FilePath Int64 Tensor

newtype Checkpoint = Checkpoint (M.Map String TensorLocation)

querySize, kvSize, kvMultiplier :: Config -> Int
querySize c = num_attention_heads c * head_dim c
kvSize c = num_key_value_heads c * head_dim c
kvMultiplier c = num_attention_heads c `div` num_key_value_heads c

validateConfig :: Config -> Either String ()
validateConfig c
  | any (<= 0) [hidden_size c, intermediate_size c, num_hidden_layers c, num_attention_heads c, num_key_value_heads c, head_dim c, vocab_size c] = Left "Model dimensions must be positive"
  | num_attention_heads c `mod` num_key_value_heads c /= 0 = Left "Query heads must be divisible by KV heads"
  | odd (head_dim c) = Left "RoPE requires an even head dimension"
  | any ((/= 0) . (`mod` 64)) [hidden_size c, intermediate_size c, querySize c] = Left "Quantized matrix columns must be divisible by 64"
  | any (\x -> isNaN x || isInfinite x || x <= 0) [rms_norm_eps c, rope_theta c] = Left "Normalization epsilon and RoPE theta must be finite and positive"
  | otherwise = Right ()

loadConfig :: FilePath -> IO Config
loadConfig path = do
  c <- either fail pure . eitherDecode =<< BL.readFile path
  either fail pure (validateConfig c)
  pure c

openCheckpoint :: FilePath -> IO Checkpoint
openCheckpoint path = do
  directory <- doesDirectoryExist path
  if not directory
    then Checkpoint <$> readHeader path
    else do
      indexed <- doesFileExist (path </> "model.safetensors.index.json")
      if not indexed
        then Checkpoint <$> readHeader (path </> "model.safetensors")
        else do
          value <- either fail pure . eitherDecode =<< BL.readFile (path </> "model.safetensors.index.json")
          weightMap <- case value of Object o -> maybe (fail "Missing safetensors weight_map") (either fail pure . parseEitherMap) (KM.lookup "weight_map" o); _ -> fail "Expected safetensors index object"
          shards <- forM (M.keys (M.fromList [(file, ()) | file <- M.elems weightMap])) $ \file -> do
            unless (isRelative file && ".." `notElem` splitDirectories file) (fail "Shard paths must stay within the checkpoint directory")
            contents <- readHeader (path </> file)
            pure (file, contents)
          tensors <- forM (M.toList weightMap) $ \(name, file) -> case lookup file shards >>= M.lookup name of
            Nothing -> fail ("Indexed tensor is missing from its shard: " ++ name)
            Just location -> pure (name, location)
          pure (Checkpoint (M.fromList tensors))
  where
    parseEitherMap value = case fromJSON value of Success a -> Right (a :: M.Map String FilePath); Error e -> Left e

readHeader :: FilePath -> IO (M.Map String TensorLocation)
readHeader path = withBinaryFile path ReadMode $ \h -> do
  bytes <- BS.hGet h 8
  unless (BS.length bytes == 8) (fail "Truncated safetensors header prefix")
  let lengthHeader = fromIntegral (runGet getWord64le (BL.fromStrict bytes))
  size <- hFileSize h
  unless (lengthHeader > 0 && toInteger lengthHeader + 8 <= size && lengthHeader <= 16777216) (fail "Invalid safetensors header length")
  header <- BS.hGet h lengthHeader
  value <- either fail pure (eitherDecodeStrict' header)
  fields <- case value of Object o -> pure o; _ -> fail "A safetensors header must be an object"
  tensors <- traverse parseTensor [(K.toString k, v) | (k, v) <- KM.toList fields, k /= "__metadata__"]
  let base = fromIntegral (lengthHeader + 8)
  validateExtents tensors base size
  pure (M.fromList [(name, TensorLocation path base t) | (name, t) <- tensors])
  where
    parseTensor (name, v) = case fromJSON v of Error e -> fail (name ++ ": " ++ e); Success t -> pure (name, t)
    validateExtents tensors base size =
      mapM_
        ( \(name, t) -> case data_offsets t of
            [a, b]
              | a >= 0
                  && b >= a
                  && toInteger base + toInteger b <= size
                  && all (> 0) (shape t)
                  && toInteger (b - a) == product (map toInteger (shape t)) * elementBytes (dtype t) ->
                  pure ()
            _ -> fail ("Invalid safetensors extent: " ++ name)
        )
        tensors
    elementBytes "BF16" = 2
    elementBytes "F32" = 4
    elementBytes _ = 0

hasTensor :: Checkpoint -> String -> Bool
hasTensor (Checkpoint tensors) name = M.member name tensors

readTensor :: Checkpoint -> String -> IO (Tensor, BS.ByteString)
readTensor (Checkpoint tensors) name = case M.lookup name tensors of
  Nothing -> fail ("Missing tensor: " ++ name)
  Just (TensorLocation path base t) -> case data_offsets t of
    [a, b] -> withBinaryFile path ReadMode $ \h -> do
      hSeek h AbsoluteSeek (fromIntegral (base + a))
      bytes <- BS.hGet h (fromIntegral (b - a))
      if BS.length bytes /= fromIntegral (b - a) then fail ("Truncated tensor: " ++ name) else pure (t, bytes)
    _ -> fail ("Invalid tensor extent: " ++ name)

layerName :: Int -> String -> String
layerName i suffix = "model.layers." ++ show i ++ "." ++ suffix

matrices :: Config -> [(String, Int, Int)]
matrices c =
  [("model.embed_tokens.weight", vocab_size c, hidden_size c)]
    ++ concat
      [ [(layerName i suffix, rows, cols) | i <- [0 .. num_hidden_layers c - 1]]
      | (suffix, rows, cols) <-
          [ ("self_attn.q_proj.weight", num_attention_heads c * head_dim c, hidden_size c),
            ("self_attn.k_proj.weight", num_key_value_heads c * head_dim c, hidden_size c),
            ("self_attn.v_proj.weight", num_key_value_heads c * head_dim c, hidden_size c),
            ("self_attn.o_proj.weight", hidden_size c, num_attention_heads c * head_dim c),
            ("mlp.gate_proj.weight", intermediate_size c, hidden_size c),
            ("mlp.down_proj.weight", hidden_size c, intermediate_size c),
            ("mlp.up_proj.weight", intermediate_size c, hidden_size c)
          ]
      ]
    ++ [("lm_head.weight", vocab_size c, hidden_size c) | not (tie_word_embeddings c)]

norms :: Config -> [(String, Int)]
norms c =
  [(layerName i suffix, n) | (suffix, n) <- [("input_layernorm.weight", hidden_size c), ("post_attention_layernorm.weight", hidden_size c)], i <- [0 .. num_hidden_layers c - 1]]
    ++ [("model.norm.weight", hidden_size c)]
    ++ [(layerName i suffix, head_dim c) | suffix <- ["self_attn.q_norm.weight", "self_attn.k_norm.weight"], i <- [0 .. num_hidden_layers c - 1]]
