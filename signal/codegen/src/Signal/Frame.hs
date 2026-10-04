module Signal.Frame (encodeFrame, decodeFrame, crc8, frameBits) where

import Data.Bits (shiftL, testBit, xor)
import Data.Char (chr, ord)
import Data.Word (Word8)

-- Length and payload are covered by CRC-8/SMBUS (poly 0x07, init 0).
crc8 :: [Word8] -> Word8
crc8 = foldl update 0
  where
    update crc byte = foldl (\value _ -> step value) (crc `xor` byte) [1 .. 8 :: Int]
    step value = if testBit value 7 then shiftL value 1 `xor` 7 else shiftL value 1

encodeFrame :: String -> Either String [Word8]
encodeFrame message
  | null message || length message > 64 = Left "Messages contain 1 to 64 ASCII characters"
  | any (\c -> ord c < 32 || ord c > 126) message = Left "Messages use printable ASCII"
  | otherwise = Right (body ++ [crc8 body])
  where
    body = fromIntegral (length message) : map (fromIntegral . ord) message

decodeFrame :: [Word8] -> Either String String
decodeFrame [] = Left "Missing length"
decodeFrame bytes@(size : rest)
  | size == 0 || size > 64 = Left "Length is outside the receiver range"
  | length rest /= fromIntegral size + 1 = Left "Incomplete frame or trailing data"
  | crc8 bytes /= 0 = Left "CRC mismatch"
  | any (\c -> c < 32 || c > 126) payload = Left "Invalid ASCII payload"
  | otherwise = Right (map (chr . fromIntegral) payload)
  where
    payload = take (fromIntegral size) rest

frameBits :: [Word8] -> [Int]
frameBits = concatMap (\byte -> [if testBit byte position then 1 else 0 | position <- [7, 6 .. 0]])
