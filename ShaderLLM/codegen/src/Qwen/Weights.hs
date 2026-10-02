{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}

module Qwen.Weights (compileWeights, compileWeightsWithPageSide, imageBytes, vectorBytes, configureContext) where

import Codec.Picture
import Control.Monad (unless)
import Data.Aeson
import Data.Aeson.KeyMap qualified as KM
import Data.Binary.Put
import Data.Bits
import Data.ByteString qualified as BS
import Data.ByteString.Internal qualified as BI
import Data.ByteString.Lazy qualified as BL
import Data.Int (Int8)
import Data.Vector.Storable qualified as VS
import Data.Vector.Unboxed qualified as U
import Data.Word
import Foreign.ForeignPtr (castForeignPtr)
import Foreign.Storable (Storable, sizeOf)
import GHC.Float (castFloatToWord32, castWord32ToFloat)
import Qwen.Layout qualified as L
import Qwen.Limits (contextSize)
import Qwen.Model
import System.Directory (createDirectoryIfMissing)
import System.FilePath ((</>))
import System.IO

groupSize :: Int
groupSize = 64

configureContext :: FilePath -> IO ()
configureContext output = do
  withBinaryFile (output </> "reference.bin") ReadWriteMode $ \handle -> do
    hSeek handle AbsoluteSeek 32
    BL.hPut handle (runPut (putWord32le (fromIntegral contextSize)))
  value <- either fail pure . eitherDecode =<< BL.readFile (output </> "weights.json")
  case value of
    Object fields -> BL.writeFile (output </> "weights.json") (encode (Object (KM.insert "context_size" (toJSON contextSize) fields)))
    _ -> fail "Expected model manifest object"

tensorValue :: Tensor -> BS.ByteString -> Int -> Float
tensorValue t bytes i = case dtype t of
  "BF16" -> castWord32ToFloat ((fromIntegral (BS.index bytes (2 * i)) .|. (fromIntegral (BS.index bytes (2 * i + 1)) `shiftL` 8)) `shiftL` 16)
  "F32" -> castWord32ToFloat (foldr (.|.) 0 [fromIntegral (BS.index bytes (4 * i + j)) `shiftL` (8 * j) | j <- [0 .. 3]])
  value -> error ("Unsupported weight dtype: " ++ value)

quantize :: Tensor -> BS.ByteString -> Int -> (U.Vector Int8, U.Vector Float)
quantize tensor bytes n = (values, scales)
  where
    readValue = tensorValue tensor bytes
    scales = U.generate (n `div` groupSize) $ \g ->
      let go !j !m
            | j == groupSize = m / 127
            | otherwise = go (j + 1) (max m (abs (readValue (g * groupSize + j))))
       in go 0 0
    values = U.generate n $ \i ->
      let s = scales U.! (i `div` groupSize)
          x = if s == 0 then 0 else readValue i / s
          q = round x :: Int
       in fromIntegral (max (-127) (min 127 q))

vectorBytes :: forall a. (Storable a) => VS.Vector a -> BS.ByteString
vectorBytes vector =
  let (fp, n) = VS.unsafeToForeignPtr0 vector
   in BI.fromForeignPtr (castForeignPtr fp) 0 (n * sizeOf (undefined :: a))

floatBytes :: U.Vector Float -> BS.ByteString
floatBytes values = vectorBytes (VS.generate (U.length values) (values U.!))

atlasBytes :: U.Vector Int8 -> U.Vector Float -> BS.ByteString
atlasBytes values scales = vectorBytes (VS.generate (U.length scales * 17) word)
  where
    word i
      | i `mod` 17 == 16 = byteSwap32 (castFloatToWord32 (scales U.! (i `div` 17)))
      | otherwise = foldr (.|.) 0 [fromIntegral (fromIntegral (values U.! (i `div` 17 * 64 + i `mod` 17 * 4 + j)) + 128 :: Int) `shiftL` (8 * j) | j <- [0 .. 3]]

imageBytes :: Int -> Int -> BS.ByteString -> Image PixelRGBA8
imageBytes w h b = let (fp, start, n) = BI.toForeignPtr b in Image w h (VS.unsafeFromForeignPtr fp start n)

writeAtlasPages :: Int -> FilePath -> FilePath -> IO [Value]
writeAtlasPages side source destination = withBinaryFile source ReadMode $ \h -> go h 0
  where
    go :: Handle -> Int -> IO [Value]
    go h page = do
      bytes <- BS.hGet h (side * side * 4)
      if BS.null bytes
        then pure []
        else do
          let height = (BS.length bytes + side * 4 - 1) `div` (side * 4)
              padded = bytes <> BS.replicate (side * height * 4 - BS.length bytes) 0
              name = "weights_" ++ show page ++ ".png"
          writePng (destination </> name) (imageBytes side height padded)
          putStrLn ("Weight texture " ++ name ++ " " ++ show side ++ "x" ++ show height)
          rest <- go h (page + 1)
          pure (object ["file" .= name, "width" .= side, "height" .= height] : rest)

compileWeights :: FilePath -> FilePath -> IO ()
compileWeights model output = do
  c <- loadConfig (model </> "config.json")
  side <- either fail pure (L.choosePageSide c)
  compileWeightsWithPageSide side model output

compileWeightsWithPageSide :: Int -> FilePath -> FilePath -> IO ()
compileWeightsWithPageSide side model output = do
  unless (side > 0 && side <= 16384) (fail "Weight page size must be in 1..16384")
  c <- loadConfig (model </> "config.json")
  checkpoint <- openCheckpoint model
  if tie_word_embeddings c && hasTensor checkpoint "lm_head.weight"
    then do
      (_, embedding) <- readTensor checkpoint "model.embed_tokens.weight"
      (_, headWeights) <- readTensor checkpoint "lm_head.weight"
      unless (embedding == headWeights) (fail "Tied output weights do not match the embedding tensor")
    else pure ()
  createDirectoryIfMissing True output
  let textureRoot = output </> "textures"
  createDirectoryIfMissing True textureRoot
  withBinaryFile (output </> "reference.bin") WriteMode $ \reference -> do
    let header = BL.toStrict $ runPut $ do
          putWord32le 0x616a6331
          putWord32le 1
          mapM_
            (putWord32le . fromIntegral)
            [hidden_size c, intermediate_size c, num_hidden_layers c, num_attention_heads c, num_key_value_heads c, vocab_size c, contextSize, head_dim c, fromEnum (tie_word_embeddings c), groupSize]
          putByteString (BS.replicate (256 - 48) 0)
    BS.hPut reference header
    normRecords <- withBinaryFile (output </> "norms.rgba") WriteMode $ \atlas -> do
      (_, records) <-
        foldIO
          ( \(!base, records) (name, n) -> do
              (tensor, raw) <- readTensor checkpoint name
              unless (shape tensor == [n]) (fail ("Norm shape: " ++ name))
              let values = U.generate n (tensorValue tensor raw)
                  packedNorms = VS.generate n (byteSwap32 . castFloatToWord32 . (values U.!))
              BS.hPut reference (floatBytes values)
              BS.hPut atlas (vectorBytes packedNorms)
              pure (base + n, records ++ [object ["name" .= name, "base" .= base, "length" .= n]])
          )
          (0 :: Int, [])
          (norms c)
      pure records
    matrixRecords <- withBinaryFile (output </> "weights.rgba") WriteMode $ \atlas -> do
      (_, records) <-
        foldIO
          ( \(!base, records) (name, rows, cols) -> do
              (tensor, raw) <- readTensor checkpoint name
              unless (shape tensor == [rows, cols] && cols `mod` groupSize == 0) (fail ("Matrix shape: " ++ name))
              let (quantized, scales) = quantize tensor raw (rows * cols)
                  bytes = vectorBytes (VS.generate (U.length quantized) (quantized U.!))
                  packed = atlasBytes quantized scales
                  pixelCount = BS.length packed `div` 4
              BS.hPut reference bytes
              BS.hPut reference (floatBytes scales)
              BS.hPut atlas packed
              putStrLn ("Compiled " ++ name ++ " " ++ show rows ++ "x" ++ show cols)
              hFlush stdout
              pure (base + pixelCount, records ++ [object ["name" .= name, "base" .= base, "rows" .= rows, "cols" .= cols]])
          )
          (0 :: Int, [])
          (matrices c)
      pure records
    rawNorms <- BS.readFile (output </> "norms.rgba")
    let nw = min 8192 (hidden_size c); nh = (BS.length rawNorms + nw * 4 - 1) `div` (nw * 4)
    writePng (textureRoot </> "norms.png") (imageBytes nw nh (rawNorms <> BS.replicate (nw * nh * 4 - BS.length rawNorms) 0))
    pages <- writeAtlasPages side (output </> "weights.rgba") textureRoot
    BL.writeFile
      (output </> "weights.json")
      ( encode
          ( object
              [ "config" .= c,
                "group_size" .= groupSize,
                "context_size" .= contextSize,
                "page_width" .= side,
                "page_height" .= side,
                "pages" .= pages,
                "matrices" .= matrixRecords,
                "norms" .= normRecords,
                "norm_texture" .= object ["width" .= nw, "height" .= nh]
              ]
          )
      )
  where
    foldIO _ initial [] = pure initial
    foldIO f initial (x : xs) = f initial x >>= \next -> foldIO f next xs
