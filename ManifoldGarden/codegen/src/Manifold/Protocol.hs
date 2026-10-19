module Manifold.Protocol where

import Data.Bits (shiftL, shiftR, (.&.), (.|.))
import Data.List (mapAccumL)
import Manifold.ThreeRings qualified as Rings

data Field = Field {fieldName :: String, fieldWidth :: Int, fieldBias :: Integer} deriving (Eq, Show)

header :: [Field]
header =
  [ Field "enabled" 1 0,
    Field "quality" 2 0,
    Field "period" 8 0,
    Field "g.x" 18 0,
    Field "g.y" 18 0,
    Field "g.z" 18 0,
    Field "g.frame" 5 0,
    Field "g.seq" 16 0,
    Field "g.epoch" 16 0,
    Field "g.fly" 1 0,
    Field "g.grounded" 1 0,
    Field "h.mode" 2 0,
    Field "h.slot" 1 0,
    Field "h.level" 2 0,
    Field "r.window0" 3 0,
    Field "r.window1" 3 0,
    Field "r.held" 10 1,
    Field "r.gates" 16 0,
    Field "r.complete" 1 0,
    Field "r.revision" 16 0
  ]

fieldOffsets :: [(Int, Field)]
fieldOffsets = snd $ mapAccumL (\offset f -> (offset + fieldWidth f, (offset, f))) 0 header

headerWords, objectWords, payloadWords, packetWords :: Int
headerWords = (sum (map fieldWidth header) + 23) `div` 24
objectWords = length Rings.cubes + 3
payloadWords = headerWords
packetWords = 22 + headerWords + objectWords

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
score name = "#" ++ name ++ " manifold"

setScore :: String -> Integer -> String
setScore name n = "scoreboard players set " ++ score name ++ " " ++ show n

operation :: String -> String -> String -> String
operation a op b = "scoreboard players operation " ++ score a ++ " " ++ op ++ " " ++ score b

constants :: [String]
constants = [setScore ("pow" ++ show n) (2 ^ n) | n <- [0 .. 26 :: Int]]

encodeCommands :: [String]
encodeCommands =
  ["execute unless score " ++ score "tx.ready" ++ " matches 1 run function manifold:transport/reset"]
    ++ ["execute unless score " ++ score (fieldName f) ++ " = " ++ score (previousField f) ++ " run function manifold:transport/update/" ++ fieldName f | f <- header]
    ++ ["execute if score " ++ score (dirtyWord i) ++ " matches 1 run function manifold:transport/write/" ++ show i | i <- [0 .. headerWords - 1]]

encodingFragments :: [(Field, Piece)]
encodingFragments = [(f, p) | (offset, f) <- fieldOffsets, p <- pieces offset (fieldWidth f)]

data PacketCache = PacketCache {cachedWords :: [Integer], cachedParts :: [Integer]} deriving (Eq, Show)

-- A field change applies its fragment deltas to persistent RGB words.
updatePacket :: Maybe PacketCache -> [Integer] -> Either String (PacketCache, [Int])
updatePacket previous values = do
  _ <- pack values
  let parts = [shiftL (shiftR (value + fieldBias f) (valueShift p) .&. (2 ^ pieceWidth p - 1)) (wordShift p) | ((offset, f), value) <- zip fieldOffsets values, p <- pieces offset (fieldWidth f)]
      oldParts = maybe (replicate (length parts) 0) cachedParts previous
      oldWords = maybe (replicate headerWords 0) cachedWords previous
      deltas = zipWith (-) parts oldParts
      change i = sum [delta | ((_, p), delta) <- zip encodingFragments deltas, wordIndex p == i]
      words24 = [old + change i | (i, old) <- zip [0 ..] oldWords]
      dirty = [i | i <- [0 .. headerWords - 1], maybe True (const (change i /= 0)) previous]
  pure (PacketCache words24 parts, dirty)

previousField :: Field -> String
previousField f = "tx.previous." ++ fieldName f

dirtyWord :: Int -> String
dirtyWord i = "tx.dirty." ++ show i

encodingFunctions :: [(String, [String])]
encodingFunctions =
  [("transport/reset", [setScore "tx.ready" 1] ++ concat [[setScore ("word" ++ show i) 0, setScore (dirtyWord i) 1] | i <- [0 .. headerWords - 1]] ++ [setScore (fragment n) 0 | (n, _) <- numbered] ++ [setScore (previousField f) (2 ^ fieldWidth f - fieldBias f) | f <- header])]
    ++ [("transport/update/" ++ fieldName f, operation (previousField f) "=" (fieldName f) : concat [update n f p | (n, (owner, p)) <- numbered, owner == f]) | f <- header]
    ++ [("transport/merge/" ++ show n, [operation (word p) "-=" (fragment n), operation (word p) "+=" "tx.part", operation (fragment n) "=" "tx.part", setScore (dirtyWord (wordIndex p)) 1]) | (n, (_, p)) <- numbered]
    ++ [("transport/write/" ++ show i, ["execute store result storage manifold:tx colors[" ++ show i ++ "] int 1 run scoreboard players get " ++ score ("word" ++ show i), setScore (dirtyWord i) 0]) | i <- [0 .. headerWords - 1]]
  where
    numbered = zip [0 :: Int ..] encodingFragments
    fragment n = "tx.fragment." ++ show n
    word p = "word" ++ show (wordIndex p)
    update n f p =
      [operation "tx.part" "=" (fieldName f)]
        ++ ["scoreboard players add " ++ score "tx.part" ++ " " ++ show (fieldBias f) | fieldBias f /= 0]
        ++ [operation "tx.part" "/=" ("pow" ++ show (valueShift p)) | valueShift p > 0]
        ++ [operation "tx.part" "%=" ("pow" ++ show (pieceWidth p))]
        ++ [operation "tx.part" "*=" ("pow" ++ show (wordShift p)) | wordShift p > 0]
        ++ ["execute unless score " ++ score "tx.part" ++ " = " ++ score (fragment n) ++ " run function manifold:transport/merge/" ++ show n]
