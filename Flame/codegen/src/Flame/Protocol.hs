module Flame.Protocol where

import Data.Bits (shiftL, shiftR, (.&.), (.|.))
import Data.List (mapAccumL)
import Flame.Domain

data Field = Field {fieldName :: String, fieldWidth :: Int, fieldBias :: Integer}
  deriving (Eq, Show)

header :: [Field]
header =
  [ Field "epoch" 24 0,
    Field "origin.x" 26 33554432,
    Field "origin.y" 12 2048,
    Field "origin.z" 26 33554432,
    Field "source" 14 0,
    Field "power" 9 0,
    Field "mode" 2 0
  ]

fieldOffsets :: [Field] -> [(Int, Field)]
fieldOffsets = snd . mapAccumL (\offset field -> (offset + fieldWidth field, (offset, field))) 0

headerWords :: Int
headerWords = (sum (map fieldWidth header) + 23) `div` 24

terrainWords :: Config -> Int
terrainWords c = (volume (region c) * 7 + 23) `div` 24

dataWords :: Config -> Int
dataWords c = headerWords + terrainWords c

cameraWords :: Int
cameraWords = 4

packetWords :: Config -> Int
packetWords c = 1 + cameraWords + dataWords c

packetDimensions :: Config -> (Int, Int)
packetDimensions c = (32, (packetWords c + 31) `div` 32)

packValues :: [(Int, Integer)] -> Either String [Integer]
packValues fields
  | any (\(width, x) -> width < 1 || width > 31 || x < 0 || x >= 2 ^ width) fields = Left "Field outside its encoded range"
  | otherwise = Right [shiftR payload (24 * i) .&. 0xffffff | i <- [0 .. wordCount - 1]]
  where
    (bits, payload) = foldl (\(offset, acc) (width, x) -> (offset + width, acc .|. shiftL x offset)) (0, 0) fields
    wordCount = (bits + 23) `div` 24

unpackValues :: [Int] -> [Integer] -> [Integer]
unpackValues widths words24 = snd $ mapAccumL get 0 widths
  where
    payload = foldl (.|.) 0 [shiftL x (24 * i) | (i, x) <- zip [0 ..] words24]
    get offset width = (offset + width, shiftR payload offset .&. (2 ^ width - 1))

data Piece = Piece {wordIndex :: Int, wordShift :: Int, valueShift :: Int, pieceWidth :: Int}
  deriving (Eq, Show)

pieces :: Int -> Int -> [Piece]
pieces offset width = go offset 0 width
  where
    go _ _ 0 = []
    go bit consumed remaining =
      let count = min remaining (24 - bit `mod` 24)
       in Piece (bit `div` 24) (bit `mod` 24) consumed count : go (bit + count) (consumed + count) (remaining - count)

score :: String -> String
score name = "#" ++ name ++ " flame"

setScore :: String -> Integer -> String
setScore name n = "scoreboard players set " ++ score name ++ " " ++ show n

operation :: String -> String -> String -> String
operation dst op src = "scoreboard players operation " ++ score dst ++ " " ++ op ++ " " ++ score src

-- Each fragment is at most 24 bits, so command arithmetic remains signed-int safe.
pieceCommands :: String -> String -> Piece -> [String]
pieceCommands source destination p =
  [operation "piece" "=" source]
    ++ [operation "piece" "/=" (constant (valueShift p)) | valueShift p /= 0]
    ++ [operation "piece" "%=" (constant (pieceWidth p))]
    ++ [operation "piece" "*=" (constant (wordShift p)) | wordShift p /= 0]
    ++ [operation destination "+=" "piece"]
  where
    constant n = "pow" ++ show n

constantCommands :: [String]
constantCommands = [setScore ("pow" ++ show n) (2 ^ n) | n <- [0 .. 26 :: Int]]
