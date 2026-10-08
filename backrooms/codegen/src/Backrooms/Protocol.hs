module Backrooms.Protocol where

import Data.Bits (shiftL, shiftR, (.&.), (.|.))
import Data.List (mapAccumL)

data Field = Field {fieldName :: String, fieldWidth :: Int, fieldBias :: Integer} deriving (Eq, Show)

data Piece = Piece {wordIndex :: Int, wordShift :: Int, valueShift :: Int, pieceWidth :: Int} deriving (Eq, Show)

header :: [Field]
header = [Field "origin.x" 26 33554432, Field "origin.y" 12 2048, Field "origin.z" 26 33554432, Field "period" 8 0, Field "enabled" 1 0, Field "quality" 2 0, Field "room" 1 0, Field "mirror" 1 0]

cameraWords, headerWords, packetWords :: Int
cameraWords = 7
headerWords = (sum (map fieldWidth header) + 23) `div` 24
packetWords = cameraWords + headerWords

magic :: Int
magic = 0x42524d

fieldOffsets :: [(Int, Field)]
fieldOffsets = snd (mapAccumL (\offset f -> (offset + fieldWidth f, (offset, f))) 0 header)

pieces :: Int -> Int -> [Piece]
pieces start = go start 0
  where
    go _ _ 0 = []
    go bit consumed remaining = let n = min remaining (24 - bit `mod` 24) in Piece (bit `div` 24) (bit `mod` 24) consumed n : go (bit + n) (consumed + n) (remaining - n)

pack :: [Integer] -> Either String [Integer]
pack values
  | length values /= length header = Left "Incorrect field count"
  | any (\(f, x) -> x < 0 || x >= 2 ^ fieldWidth f) fields = Left "Header field outside range"
  | otherwise = Right [shiftR bits (24 * i) .&. 0xffffff | i <- [0 .. headerWords - 1]]
  where
    fields = zip header (zipWith (\f x -> x + fieldBias f) header values)
    bits = foldl (.|.) 0 [shiftL x offset | ((offset, _), (_, x)) <- zip fieldOffsets fields]

unpack :: [Integer] -> [Integer]
unpack words24 = [(shiftR bits offset .&. (2 ^ fieldWidth f - 1)) - fieldBias f | (offset, f) <- fieldOffsets]
  where
    bits = foldl (.|.) 0 [shiftL x (24 * i) | (i, x) <- zip [0 ..] words24]

encodeCommands :: [String]
encodeCommands =
  ["scoreboard players set #word" ++ show i ++ " backrooms 0" | i <- [0 .. headerWords - 1]]
    ++ concatMap field fieldOffsets
    ++ ["execute store result storage backrooms:tx colors[" ++ show i ++ "] int 1 run scoreboard players get #word" ++ show i ++ " backrooms" | i <- [0 .. headerWords - 1]]
  where
    field (offset, f) = ["scoreboard players operation #value backrooms = #" ++ fieldName f ++ " backrooms", "scoreboard players add #value backrooms " ++ show (fieldBias f)] ++ concatMap fragment (pieces offset (fieldWidth f))
    fragment p = ["scoreboard players operation #part backrooms = #value backrooms", op "/=" (valueShift p), op "%=" (pieceWidth p), op "*=" (wordShift p), "scoreboard players operation #word" ++ show (wordIndex p) ++ " backrooms += #part backrooms"]
    op operator power = "scoreboard players operation #part backrooms " ++ operator ++ " #pow" ++ show power ++ " backrooms"
