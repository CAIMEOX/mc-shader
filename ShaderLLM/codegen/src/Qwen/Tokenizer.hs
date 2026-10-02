{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE OverloadedStrings #-}

module Qwen.Tokenizer (compileTokenizer, uintTexture, byteTexture) where

import Codec.Picture
import Control.Applicative ((<|>))
import Control.Monad (forM, unless)
import Data.Aeson
import Data.Aeson.Key qualified as K
import Data.Aeson.KeyMap qualified as KM
import Data.Bits
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as BL
import Data.Char
import Data.Map.Strict qualified as M
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Vector qualified as V
import Data.Vector.Storable qualified as VS
import Data.Vector.Storable.Mutable qualified as VM
import Data.Word
import Qwen.Model (loadConfig, vocab_size)
import Qwen.Weights (imageBytes, vectorBytes)
import System.Directory (createDirectoryIfMissing)
import System.FilePath ((</>))
import Unicode.Char.Normalization qualified as N

uintTexture :: FilePath -> Int -> VS.Vector Word32 -> IO Value
uintTexture path width values = do
  let height = (VS.length values + width - 1) `div` width
      padded = VS.generate (width * height) (\i -> byteSwap32 (if i < VS.length values then values VS.! i else 0))
  writePng path (imageBytes width height (vectorBytes padded))
  pure (object ["width" .= width, "height" .= height])

byteTexture :: FilePath -> Int -> BS.ByteString -> IO Value
byteTexture path width values = do
  let height = max 1 ((BS.length values + width * 4 - 1) `div` (width * 4))
      padded = values <> BS.replicate (width * height * 4 - BS.length values) 0
  writePng path (imageBytes width height padded)
  pure (object ["width" .= width, "height" .= height])

hashPair :: Word32 -> Word32 -> Word32
hashPair a b = (a * 0x9e3779b1) `xor` (b * 0x85ebca6b)

hashTexture :: FilePath -> Int -> [(Word32, Word32, Word32, Word32)] -> IO (Value, Int)
hashTexture path capacity entries = do
  values <- VM.replicate (capacity * 4) 0xffffffff
  probes <- forM entries $ \(a, b, c, d) -> do
    let insert !slot !probe = do
          key <- VM.read values (slot * 4)
          if key == 0xffffffff
            then do
              VM.write values (slot * 4) a
              VM.write values (slot * 4 + 1) b
              VM.write values (slot * 4 + 2) c
              VM.write values (slot * 4 + 3) d
              pure probe
            else insert ((slot + 1) .&. (capacity - 1)) (probe + 1)
    insert (fromIntegral (hashPair a b) .&. (capacity - 1)) (1 :: Int)
  frozen <- VS.unsafeFreeze values
  spec <- uintTexture path 2048 frozen
  pure (spec, maximum (1 : probes))

field :: T.Text -> Value -> Value
field name (Object o) = case KM.lookup (K.fromText name) o of Just v -> v; Nothing -> error ("Missing JSON field " ++ T.unpack name)
field _ _ = error "Expected a JSON object"

integer :: Value -> Int
integer value = case fromJSON value of Success n -> n; Error e -> error e

text :: Value -> T.Text
text (String t) = t
text _ = error "Expected JSON text"

byteAlphabet :: [(Int, Char)]
byteAlphabet = normal ++ zip missing (map chr [256 ..])
  where
    basic = [33 .. 126] ++ [161 .. 172] ++ [174 .. 255]
    normal = zip basic (map chr basic)
    missing = [b | b <- [0 .. 255], b `notElem` basic]

canonical :: Char -> [Char]
canonical c
  | ord c >= 0xac00 && ord c <= 0xd7a3 =
      let s = ord c - 0xac00; t = s `mod` 28
       in [chr (0x1100 + s `div` 588), chr (0x1161 + s `mod` 588 `div` 28)] ++ [chr (0x11a7 + t) | t /= 0]
  | otherwise = let d = N.decompose N.Canonical c in if d == [c] then [c] else concatMap canonical d

compileUnicode :: FilePath -> IO Value
compileUnicode output = do
  let maxCp = 0x110000
      records = [(cp, canonical (chr cp)) | cp <- [0 .. maxCp - 1]]
      (total, nfdLists, metaLists) = foldl' collect (0, [], []) records
      collect (!offset, ds, ms) (cp, parts) =
        let flags = classFlags (chr cp) .|. (fromIntegral (N.combiningClass (chr cp)) `shiftL` 8)
         in (offset + length parts, map (fromIntegral . ord) parts : ds, [flags, fromIntegral offset, fromIntegral (length parts)] : ms)
      nfd = VS.fromList (concat (reverse nfdLists))
      meta = VS.fromList (concat (reverse metaLists))
      compositionMap = M.fromList (concatMap compositions records)
      compositions (_, parts) = snd (foldl' step (Nothing, []) parts)
      step (Nothing, acc) c = (Just c, acc)
      step (Just starter, acc) c = case N.compose starter c <|> N.composeStarters starter c of
        Just result -> (Just result, ((fromIntegral (ord starter), fromIntegral (ord c)), fromIntegral (ord result)) : acc)
        Nothing -> (if N.combiningClass c == 0 then Just c else Just starter, acc)
      composeEntries = [(a, b, c, 0) | ((a, b), c) <- M.toList compositionMap]
  unless (VS.length nfd == total) (fail "Unicode decomposition length")
  a <- uintTexture (output </> "unicode_meta.png") 2048 meta
  b <- uintTexture (output </> "unicode_nfd.png") 2048 nfd
  (c, p) <- hashTexture (output </> "unicode_compose.png") 65536 composeEntries
  pure (object ["meta" .= a, "nfd" .= b, "compose" .= c, "compose_probe" .= p])
  where
    classFlags ch =
      (if isSpace ch then 1 else 0)
        .|. (if isLetter ch then 2 else 0)
        .|. (if generalCategory ch `elem` [DecimalNumber, LetterNumber, OtherNumber] then 4 else 0)
        .|. (if ch == '\n' || ch == '\r' then 8 else 0) ::
        Word32

compileTokenizer :: FilePath -> FilePath -> IO ()
compileTokenizer model output = do
  createDirectoryIfMissing True output
  modelConfig <- loadConfig (model </> "config.json")
  root <- either fail pure . eitherDecode =<< BL.readFile (model </> "tokenizer.json")
  let m = field "model" root
      vocab = case field "vocab" m of Object o -> M.fromList [(K.toText k, integer v) | (k, v) <- KM.toList o]; _ -> error "Invalid BPE vocabulary"
      merges = case field "merges" m of Array a -> V.toList a; _ -> error "Invalid BPE merges"
      lookupToken name = case M.lookup name vocab of Just i -> i; Nothing -> error ("Missing BPE token " ++ T.unpack name)
      pair value = case value of
        Array a | V.length a == 2 -> (text (a V.! 0), text (a V.! 1))
        String s -> case T.splitOn " " s of [a, b] -> (a, b); _ -> error "Invalid merge pair"
        _ -> error "Invalid BPE merge"
      entries = [(fromIntegral (lookupToken a), fromIntegral (lookupToken b), fromIntegral (lookupToken (a <> b)), fromIntegral rank) | (rank, value) <- zip [0 :: Int ..] merges, let (a, b) = pair value]
      inverse = M.fromList [(c, fromIntegral b :: Word8) | (b, c) <- byteAlphabet]
      rawToken s = BS.pack [case M.lookup c inverse of Just b -> b; Nothing -> error "Invalid byte-level vocabulary character" | c <- T.unpack s]
      added = case field "added_tokens" root of Array a -> V.toList a; _ -> error "Invalid added tokens"
      addedPairs = [(integer (field "id" v), TE.encodeUtf8 (text (field "content" v))) | v <- added]
      allTokens = M.union (M.fromList [(i, rawToken s) | (s, i) <- M.toList vocab]) (M.fromList addedPairs)
      configVocab = vocab_size modelConfig
      (byteCount, chunks, tokenRecords) =
        foldl'
          ( \(!offset, bs, rs) i ->
              let bytes = M.findWithDefault BS.empty i allTokens
               in (offset + BS.length bytes, bytes : bs, [fromIntegral offset, fromIntegral (BS.length bytes)] : rs)
          )
          (0, [], [])
          [0 .. configVocab - 1]
      tokenBytes = BS.concat (reverse chunks)
      tokenMeta = VS.fromList (concat (reverse tokenRecords))
      byteIds = [lookupToken (T.singleton c) | b <- [0 .. 255], let c = maybe (error "Byte alphabet") id (lookup b byteAlphabet)]
      (specialLen, specialLists, specialRecords) =
        foldl'
          ( \(!offset, bs, rs) v ->
              let chars = map ord (T.unpack (text (field "content" v))); i = integer (field "id" v)
               in (offset + length chars, chars : bs, [i, offset, length chars] : rs)
          )
          (0, [], [])
          added
      specialData = VS.fromList (map fromIntegral (concat (reverse specialLists)))
      specialMeta = VS.fromList (map fromIntegral (concat (reverse specialRecords)))
  unless (all (\(tokenId, _) -> tokenId >= 0 && tokenId < configVocab) (M.toList allTokens)) (fail "Tokenizer token ID exceeds Config vocabulary")
  unless (BS.length tokenBytes == byteCount && VS.length specialData == specialLen) (fail "Tokenizer resource extent")
  (mergeSpec, maxProbe) <- hashTexture (output </> "merges.png") 524288 entries
  metaSpec <- uintTexture (output </> "token_meta.png") 1024 tokenMeta
  bytesSpec <- byteTexture (output </> "token_bytes.png") 1024 tokenBytes
  specialSpec <- uintTexture (output </> "special_meta.png") 256 specialMeta
  specialBytesSpec <- uintTexture (output </> "special_chars.png") 256 specialData
  unicode <- compileUnicode output
  BL.writeFile
    (output </> "tokenizer-layout.json")
    ( encode
        ( object
            [ "merges" .= mergeSpec,
              "merge_capacity" .= (524288 :: Int),
              "merge_probe" .= maxProbe,
              "token_meta" .= metaSpec,
              "token_bytes" .= bytesSpec,
              "byte_ids" .= byteIds,
              "special_meta" .= specialSpec,
              "special_chars" .= specialBytesSpec,
              "special_count" .= length added,
              "unicode" .= unicode,
              "vocab_size" .= configVocab
            ]
        )
    )
  putStrLn ("Compiled tokenizer: " ++ show (length entries) ++ " merges, max probe " ++ show maxProbe)
