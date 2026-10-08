module Backrooms.Json (Json, object, array, string, int, number, bool, render, readJson, modifyObject) where

import Data.Aeson qualified as A
import Data.Aeson.Key qualified as K
import Data.Aeson.KeyMap qualified as KM
import Data.ByteString.Lazy qualified as BL
import Data.Text qualified as T
import Data.Text.Encoding qualified as T

type Json = A.Value

object :: [(String, Json)] -> Json
object xs = A.object [K.fromString k A..= v | (k, v) <- xs]

array :: [Json] -> Json
array = A.toJSON

string :: String -> Json
string = A.toJSON

int :: (Integral a) => a -> Json
int = A.toJSON . toInteger

number :: Double -> Json
number = A.toJSON

bool :: Bool -> Json
bool = A.toJSON

render :: Json -> String
render = T.unpack . T.decodeUtf8 . BL.toStrict . A.encode

readJson :: FilePath -> IO Json
readJson path = BL.readFile path >>= either fail pure . A.eitherDecode

modifyObject :: [(String, Json)] -> Json -> Json
modifyObject entries (A.Object value) = A.Object (foldl (\m (k, v) -> KM.insert (K.fromString k) v m) value entries)
modifyObject _ _ = error "Expected a resource object"
