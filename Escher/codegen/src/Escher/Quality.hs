module Escher.Quality where

import Escher.Pipeline (Extent (..))

data Quality = Quality {qualityId :: Int, qualityName :: String, renderExtent :: Extent, traceSteps :: Int} deriving (Eq, Show)

qualities :: [Quality]
qualities =
  [ Quality 0 "low" (Fixed 960 540) 224,
    Quality 1 "balanced" (Fixed 1440 810) 288,
    Quality 2 "high" (Fixed 1920 1080) 352,
    Quality 3 "native" Screen 416
  ]

parameters :: Quality -> [Double]
parameters q = map fromIntegral [qualityId q, traceSteps q, w, h]
  where
    (w, h) = case renderExtent q of Fixed x y -> (x, y); Screen -> (0, 0)
