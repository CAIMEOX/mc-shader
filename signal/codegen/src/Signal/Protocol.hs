module Signal.Protocol (Mode (..), Request (..), encode, decode, digest, resultBit, balancedPayload, resultSymbol, balancedFourPayload) where

import Data.Bits (shiftL, shiftR, xor, (.&.), (.|.))
import Data.List (sortOn)
import Data.Word (Word32)

data Mode = Light | Heavy | Compute | ComputeFour deriving (Eq, Show, Enum, Bounded)

data Request = Request
  { sequenceId :: Int,
    mode :: Mode,
    power :: Int
  }
  deriving (Eq, Show)

encode :: Request -> Either String Int
encode (Request index kind strength)
  | index < 1 || index > 65535 = Left "Sequence must be in 1..65535"
  | strength < 0 || strength > 63 = Left "Power must be in 0..63"
  | otherwise = Right (index .|. shiftL (fromEnum kind) 16 .|. shiftL strength 18)

decode :: Int -> Either String Request
decode word
  | word < 0 || word > 0xffffff || index == 0 = Left "Invalid request"
  | otherwise = Right (Request index (toEnum tag) (shiftR word 18))
  where
    index = word .&. 65535
    tag = shiftR word 16 .&. 3

digest :: Int -> Word32
digest index = c `xor` shiftR c 16
  where
    a = fromIntegral index `xor` 0x53a9f17d
    b = (a `xor` shiftR a 16) * 0x7feb352d
    c = (b `xor` shiftR b 15) * 0x846ca68b

resultBit :: Request -> Int
resultBit = (.&. 1) . resultSymbol

resultSymbol :: Request -> Int
resultSymbol request = case mode request of
  Light -> 0
  Heavy -> 1
  Compute -> fromIntegral (digest (sequenceId request) .&. 1)
  ComputeFour -> fromIntegral (digest (sequenceId request) .&. 3)

balancedPayload :: Int -> Either String [Request]
balancedPayload = balancedSymbols Compute 2

balancedFourPayload :: Int -> Either String [Request]
balancedFourPayload = balancedSymbols ComputeFour 4

balancedSymbols :: Mode -> Int -> Int -> Either String [Request]
balancedSymbols kind alphabet start
  | start < 1 || start > 65535 = Left "Payload start is outside the protocol range"
  | length selected /= 32 = Left "Insufficient sequences for a balanced payload"
  | otherwise = Right (sortOn (digest . (+ 7919) . sequenceId) selected)
  where
    candidates = [Request i kind 1 | i <- [start .. 65535]]
    selected = concat [take (32 `div` alphabet) (filter ((== symbol) . resultSymbol) candidates) | symbol <- [0 .. alphabet - 1]]
