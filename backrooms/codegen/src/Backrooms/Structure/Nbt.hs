module Backrooms.Structure.Nbt (Tag (..), encodeRoot, decodeRoot) where

import Data.ByteString qualified as BS
import Data.ByteString.Builder qualified as B
import Data.ByteString.Lazy qualified as BL
import Data.Int (Int32)
import Data.Text qualified as T
import Data.Text.Encoding qualified as E
import Data.Word (Word8)

data Tag = IntTag Int32 | StringTag String | ListTag Word8 [Tag] | CompoundTag [(String, Tag)] deriving (Eq, Show)

tagId :: Tag -> Word8
tagId (IntTag _) = 3
tagId (StringTag _) = 8
tagId (ListTag _ _) = 9
tagId (CompoundTag _) = 10

utf8 :: String -> B.Builder
utf8 value = let bytes = E.encodeUtf8 (T.pack value) in B.word16BE (fromIntegral (BS.length bytes)) <> B.byteString bytes

payload :: Tag -> B.Builder
payload tag = case tag of
  IntTag value -> B.int32BE value
  StringTag value -> utf8 value
  ListTag kind entries -> B.word8 kind <> B.int32BE (fromIntegral (length entries)) <> foldMap payload entries
  CompoundTag entries -> foldMap (\(name, value) -> B.word8 (tagId value) <> utf8 name <> payload value) entries <> B.word8 0

encodeRoot :: Tag -> BS.ByteString
encodeRoot tag = BL.toStrict (B.toLazyByteString (B.word8 (tagId tag) <> utf8 "" <> payload tag))

decodeRoot :: BS.ByteString -> Either String Tag
decodeRoot bytes = do
  (kind, rest) <- byte bytes
  (_, body) <- readString rest
  (result, trailing) <- parse kind body
  if BS.null trailing then Right result else Left "Trailing NBT bytes"
  where
    byte input = maybe (Left "Truncated NBT") Right (BS.uncons input)
    word count input
      | BS.length input < count = Left "Truncated NBT number"
      | otherwise = Right (BS.foldl' (\a b -> a * 256 + fromIntegral b) (0 :: Integer) (BS.take count input), BS.drop count input)
    readString input = do
      (size, rest) <- word 2 input
      if BS.length rest < fromIntegral size
        then Left "Truncated NBT string"
        else do
          text <- either (Left . show) Right (E.decodeUtf8' (BS.take (fromIntegral size) rest))
          Right (T.unpack text, BS.drop (fromIntegral size) rest)
    parse kind input = case kind of
      3 -> do (value, rest) <- word 4 input; Right (IntTag (fromIntegral value), rest)
      8 -> do (value, rest) <- readString input; Right (StringTag value, rest)
      9 -> do
        (element, rest) <- byte input
        (count, body) <- word 4 rest
        if count > 2000000
          then Left "NBT list exceeds decoder bound"
          else do
            (values, tailBytes) <- many (fromIntegral count) element body
            Right (ListTag element values, tailBytes)
      10 -> do (entries, rest) <- compound input; Right (CompoundTag entries, rest)
      _ -> Left ("Unsupported NBT tag: " ++ show kind)
    many :: Int -> Word8 -> BS.ByteString -> Either String ([Tag], BS.ByteString)
    many 0 _ input = Right ([], input)
    many n kind input = do
      (value, rest) <- parse kind input
      (values, tailBytes) <- many (n - 1) kind rest
      Right (value : values, tailBytes)
    compound input = do
      (kind, rest) <- byte input
      if kind == 0
        then Right ([], rest)
        else do
          (name, body) <- readString rest
          (value, tailBytes) <- parse kind body
          (entries, remaining) <- compound tailBytes
          Right ((name, value) : entries, remaining)
