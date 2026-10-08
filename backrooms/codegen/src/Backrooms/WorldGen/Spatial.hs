module Backrooms.WorldGen.Spatial (Metrics (..), measure, spatialQuality) where

import Backrooms.WorldGen.Density
import Backrooms.WorldGen.Geometry qualified as G
import Backrooms.WorldGen.Runtime qualified as R
import Data.Set qualified as S

data Metrics = Metrics
  { rooms :: Int,
    roomCounts :: [Int],
    elongatedFraction :: Double,
    largeFraction :: Double,
    squareFraction :: Double,
    boundaryCoverage :: Double,
    aspectClasses :: Int
  }
  deriving (Eq, Show)

measure :: NoiseSource -> [(Int, Int)] -> Metrics
measure noise origins = Metrics (length allRooms) (map S.size plans) (fraction elongated) (fraction large) (fraction square) border (S.size (S.fromList (map aspectClass allRooms)))
  where
    size = R.regionSize
    plans = [S.fromList [bounds (ox + x, oz + z) | x <- [2, 5 .. size - 1], z <- [2, 5 .. size - 1], R.sample noise (fromIntegral (ox + x), 64, fromIntegral (oz + z)) "layout/circulation" == 0] | (ox, oz) <- origins]
    bounds (x, z) = case evaluateMany R.rules noise (fromIntegral x, 64, fromIntegral z) (G.boundsValues R.roomBounds) of
      [a, b, c, d] -> (round a, round b, round c, round d) :: (Int, Int, Int, Int)
      _ -> error "Room bounds require four coordinates"
    allRooms = concatMap S.toList plans
    dimensions (a, b, c, d) = (b - a - 1, d - c - 1)
    aspect :: (Int, Int, Int, Int) -> Double
    aspect r = let (w, d) = dimensions r in fromIntegral (max w d) / fromIntegral (min w d)
    elongated r = aspect r >= 2.5
    large r = let (w, d) = dimensions r in w * d >= 180
    square r = aspect r <= 1.35
    aspectClass r | aspect r >= 3.5 = 3 :: Int | aspect r >= 2.5 = 2 | aspect r >= 1.5 = 1 | otherwise = 0
    fraction f = fromIntegral (length (filter f allRooms)) / fromIntegral (length allRooms)
    boundary = [R.sample noise (fromIntegral x, 64, fromIntegral z) "wall" > 0 | (ox, oz) <- origins, t <- [0 .. size - 1], (x, z) <- [(ox, oz + t), (ox + t, oz)]]
    border = fromIntegral (length (filter id boundary)) / fromIntegral (length boundary)

spatialQuality :: Metrics -> Either String ()
spatialQuality m
  | elongatedFraction m < 0.10 = Left ("Elongated spaces need at least 10% representation: " ++ show m)
  | largeFraction m < 0.04 = Left ("Shared spaces need at least 4% representation: " ++ show m)
  | largeFraction m > 0.16 = Left ("Shared spaces occupy at most 16% of rooms: " ++ show m)
  | S.size (S.fromList (roomCounts m)) < 3 = Left ("Regions need different subdivision counts: " ++ show m)
  | boundaryCoverage m > 0.75 = Left ("Planning boundaries need interrupted wall coverage: " ++ show m)
  | squareFraction m > 0.55 = Left ("Room proportions need a broad distribution: " ++ show m)
  | aspectClasses m < 4 = Left ("Room proportions need four distinct aspect classes: " ++ show m)
  | otherwise = Right ()
