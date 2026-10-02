module Flame.Json (Json (..), object, array, string, int, number, bool, render, quote) where

import Data.Char (ord)
import Data.List (intercalate)
import Numeric (showHex)

data Json = Object [(String, Json)] | Array [Json] | String String | Number Double | Boolean Bool
  deriving (Eq, Show)

object :: [(String, Json)] -> Json
object = Object

array :: [Json] -> Json
array = Array

string :: String -> Json
string = String

int :: (Integral a) => a -> Json
int = Number . fromIntegral

number :: Double -> Json
number = Number

bool :: Bool -> Json
bool = Boolean

quote :: String -> String
quote text = '"' : concatMap escape text ++ "\""
  where
    escape '"' = "\\\""
    escape '\\' = "\\\\"
    escape '\n' = "\\n"
    escape '\r' = "\\r"
    escape '\t' = "\\t"
    escape c
      | ord c < 32 = "\\u" ++ replicate (4 - length hex) '0' ++ hex
      | otherwise = [c]
      where
        hex = showHex (ord c) ""

render :: Json -> String
render (Object xs) = "{" ++ intercalate "," [quote k ++ ":" ++ render v | (k, v) <- xs] ++ "}"
render (Array xs) = "[" ++ intercalate "," (map render xs) ++ "]"
render (String x) = quote x
render (Boolean x) = if x then "true" else "false"
render (Number x)
  | isNaN x || isInfinite x = error "A resource number must be finite"
  | x == fromInteger (round x) = show (round x :: Integer)
  | otherwise = show x
