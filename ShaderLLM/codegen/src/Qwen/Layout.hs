{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE OverloadedStrings #-}

module Qwen.Layout where

import Data.Aeson
import Data.List (groupBy, isPrefixOf, sortOn)
import Data.Map.Strict qualified as M
import GHC.Generics (Generic)
import Qwen.Model hiding (matrices, norms)
import Qwen.Model qualified as Model

data Matrix = Matrix {name :: String, base :: Integer, rows :: Int, cols :: Int} deriving (Eq, Show, Generic)

instance FromJSON Matrix

instance ToJSON Matrix

data Page = Page {file :: String, width :: Int, height :: Int} deriving (Eq, Show, Generic)

instance FromJSON Page

instance ToJSON Page

data Norm = Norm {normName :: String, normBase :: Int, normLength :: Int} deriving (Eq, Show)

instance FromJSON Norm where
  parseJSON = withObject "Norm" $ \o -> Norm <$> o .: "name" <*> o .: "base" <*> o .: "length"

data ModelLayout = ModelLayout
  {config :: Config, page_width :: Int, page_height :: Int, pages :: [Page], matrices :: [Matrix], norms :: [Norm], normWidth :: Int, normHeight :: Int}
  deriving (Show)

instance FromJSON ModelLayout where
  parseJSON = withObject "ModelLayout" $ \o -> do
    c <- o .: "config"
    pw <- o .: "page_width"
    ph <- o .: "page_height"
    ps <- o .: "pages"
    ms <- o .: "matrices"
    ns <- o .: "norms"
    shape <- o .:? "norm_texture"
    (nw, nh) <- case shape of
      Just value -> withObject "Norm texture" (\t -> (,) <$> t .: "width" <*> t .: "height") value
      Nothing -> pure (1024, ceilDiv (maximum (0 : [normBase n + normLength n | n <- ns])) 1024)
    pure (ModelLayout c pw ph ps ms ns nw nh)

ceilDiv :: (Integral a) => a -> a -> a
ceilDiv a b = (a + b - 1) `div` b

matrixPixels :: Matrix -> Integer
matrixPixels m = toInteger (rows m) * toInteger (cols m) `div` 64 * 17

family :: String -> String
family tensor
  | "model.layers." `isPrefixOf` tensor = drop 1 (dropWhile (/= '.') (drop (length ("model.layers." :: String)) tensor))
  | otherwise = tensor

familyGroups :: [Matrix] -> [[Matrix]]
familyGroups = groupBy (\a b -> family (name a) == family (name b)) . sortOn (family . name)

matrixPlan :: Config -> [Matrix]
matrixPlan c = snd (foldl step (0, []) (Model.matrices c))
  where
    step (offset, acc) (key, r, k) = let m = Matrix key offset r k in (offset + matrixPixels m, acc ++ [m])

pageWindow :: Integer -> [Matrix] -> [Int]
pageWindow capacity ms = [fromInteger first .. fromInteger lastPage]
  where
    first = minimum (map base ms) `div` capacity
    lastPage = maximum [base m + matrixPixels m - 1 | m <- ms] `div` capacity

choosePageSide :: Config -> Either String Int
choosePageSide c = case [side | side <- [8192, 16384], all ((<= 14) . length . pageWindow (toInteger side * toInteger side)) (familyGroups (matrixPlan c))] of
  side : _ -> Right side
  [] -> Left "A weight family exceeds the fragment sampler budget at the supported page sizes"

vectorExtent :: Int -> (Int, Int)
vectorExtent n = let w = min 8192 n in (w, ceilDiv n w)

cacheExtent :: Config -> Int -> Either String (Int, Int)
cacheExtent c context = case [(w, fromInteger h) | columns <- [max 1 (4096 `div` kvSize c) .. 16384 `div` kvSize c], let w = columns * kvSize c, let h = ceilDiv total (toInteger w), h <= 16384] of
  e : _ -> Right e
  [] -> Left "KV cache exceeds the 2D texture limits for this configuration"
  where
    total = toInteger (num_hidden_layers c) * toInteger context * toInteger (kvSize c)

validateLayout :: ModelLayout -> Either String ()
validateLayout layout = do
  validateConfig (config layout)
  let ms = matrices layout
      capacity = toInteger (page_width layout) * toInteger (page_height layout)
      expected = M.fromList [(key, (r, k)) | (key, r, k) <- Model.matrices (config layout)]
      actual = M.fromList [(name m, (rows m, cols m)) | m <- ms]
  if expected /= actual then Left "Compiled matrix shapes differ from Config" else pure ()
  if length ms /= M.size actual then Left "Matrix names must be unique" else pure ()
  if M.fromList [(key, len) | (key, len) <- Model.norms (config layout)] /= M.fromList [(normName n, normLength n) | n <- norms layout] then Left "Compiled norm shapes differ from Config" else pure ()
  if normWidth layout < 1 || normHeight layout < 1 || normWidth layout > 16384 || normHeight layout > 16384 || any (\n -> normBase n < 0 || normBase n + normLength n > normWidth layout * normHeight layout) (norms layout) then Left "Invalid normalization texture extent" else pure ()
  if page_width layout < 1 || page_height layout < 1 || page_width layout > 16384 || page_height layout > 16384 then Left "Invalid weight page extent" else pure ()
  if any (\p -> width p /= page_width layout || height p < 1 || height p > page_height layout) (pages layout) then Left "Weight page dimensions differ from the atlas layout" else pure ()
  if any (\ms' -> length (pageWindow capacity ms') > 14) (familyGroups ms) then Left "Weight family requires more than 14 samplers" else pure ()
  if any (\m -> base m < 0 || matrixPixels m + capacity >= 4294967296) ms then Left "Matrix-local address exceeds uint32" else pure ()
  if any (\i -> i < 0 || i >= length (pages layout)) (concatMap (pageWindow capacity) (familyGroups ms)) then Left "Matrix references an undeclared weight page" else pure ()
  if any (\m -> let lastPixel = base m + matrixPixels m - 1; p = pages layout !! fromInteger (lastPixel `div` capacity) in lastPixel `mod` capacity >= toInteger (width p) * toInteger (height p)) ms then Left "Matrix extends beyond its final weight page" else pure ()
