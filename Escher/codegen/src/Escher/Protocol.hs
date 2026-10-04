module Escher.Protocol where

import Data.Bits (shiftL, shiftR, (.&.), (.|.))
import Data.List (mapAccumL)

data Field = Field {fieldName :: String, fieldWidth :: Int, fieldBias :: Integer} deriving (Eq, Show)

header :: [Field]
header =
  [ Field "origin.x" 26 33554432,
    Field "origin.y" 12 2048,
    Field "origin.z" 26 33554432,
    Field "period" 8 0,
    Field "ratio" 10 0,
    Field "turn" 13 4096,
    Field "enabled" 1 0,
    Field "quality" 2 0,
    Field "scene" 1 0,
    Field "folding" 10 0,
    Field "animate" 1 0,
    Field "rolling" 1 0,
    Field "overview" 1 0
  ]

fieldOffsets :: [(Int, Field)]
fieldOffsets = snd $ mapAccumL (\offset f -> (offset + fieldWidth f, (offset, f))) 0 header

headerWords, packetWords :: Int
headerWords = (sum (map fieldWidth header) + 23) `div` 24
packetWords = 5 + headerWords

data Piece = Piece {wordIndex :: Int, wordShift :: Int, valueShift :: Int, pieceWidth :: Int} deriving (Eq, Show)

-- A field can span several RGB24 words. Commands consume these same fragments.
pieces :: Int -> Int -> [Piece]
pieces offset = go offset 0
  where
    go _ _ 0 = []
    go bit consumed remaining =
      let width = min remaining (24 - bit `mod` 24)
       in Piece (bit `div` 24) (bit `mod` 24) consumed width : go (bit + width) (consumed + width) (remaining - width)

pack :: [Integer] -> Either String [Integer]
pack values
  | length values /= length header = Left "Incorrect field count"
  | any (\(f, x) -> x < 0 || x >= 2 ^ fieldWidth f) fields = Left "Field outside encoded range"
  | otherwise = Right [shiftR bits (24 * i) .&. 0xffffff | i <- [0 .. headerWords - 1]]
  where
    fields = zip header (zipWith (\f x -> x + fieldBias f) header values)
    bits = foldl (.|.) 0 [shiftL x offset | ((offset, _), (_, x)) <- zip fieldOffsets fields]

unpack :: [Integer] -> [Integer]
unpack words24 = [(shiftR bits offset .&. (2 ^ fieldWidth f - 1)) - fieldBias f | (offset, f) <- fieldOffsets]
  where
    bits = foldl (.|.) 0 [shiftL x (24 * i) | (i, x) <- zip [0 ..] words24]

score :: String -> String
score name = "#" ++ name ++ " escher"

setScore :: String -> Integer -> String
setScore name n = "scoreboard players set " ++ score name ++ " " ++ show n

operation :: String -> String -> String -> String
operation a op b = "scoreboard players operation " ++ score a ++ " " ++ op ++ " " ++ score b

constants :: [String]
constants = [setScore ("pow" ++ show n) (2 ^ n) | n <- [0 .. 26 :: Int]]

encodeCommands :: [String]
encodeCommands =
  [setScore ("word" ++ show i) 0 | i <- [0 .. headerWords - 1]]
    ++ concatMap field fieldOffsets
    ++ ["execute store result storage escher:tx colors[" ++ show i ++ "] int 1 run scoreboard players get " ++ score ("word" ++ show i) | i <- [0 .. headerWords - 1]]
  where
    field (offset, f) = [operation "value" "=" (fieldName f), "scoreboard players add " ++ score "value" ++ " " ++ show (fieldBias f)] ++ concatMap commands (pieces offset (fieldWidth f))
    commands p =
      let constant n = "pow" ++ show n
       in [operation "part" "=" "value", operation "part" "/=" (constant (valueShift p)), operation "part" "%=" (constant (pieceWidth p)), operation "part" "*=" (constant (wordShift p)), operation ("word" ++ show (wordIndex p)) "+=" "part"]
