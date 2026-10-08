module Backrooms.WorldGen.Density
  ( Axis (..),
    Op (..),
    Density (..),
    NoiseSource,
    encodeDensity,
    evaluate,
    evaluateMany,
    dependencies,
    noiseDependencies,
    mapReferences,
    validateRegistry,
    (.+.),
    (.-.),
    (.*.),
    band,
    union,
    intersection,
    select,
    inverse,
    near,
    less,
    between,
    repeatAt,
    choice,
    octile,
    quantileChoice,
    pick,
  )
where

import Backrooms.Json
import Control.Monad (foldM)
import Data.List (nub)
import Data.Map.Lazy qualified as M
import Data.Set qualified as S

data Axis = X | Y | Z deriving (Eq, Show)

data Op = Add | Sub | Mul | Min | Max deriving (Eq, Show)

-- Coordinates and decisions stay typed until the registry serialization seam.
data Density
  = Constant Double
  | Ref String
  | Gradient Axis Int Int Double Double Bool
  | Binary Op Density Density
  | Range Density Double Double Density Density
  | Floor Density
  | Noise String Density Density
  | NoiseAt String Density Density Density
  | Cache Density
  deriving (Eq, Show)

type NoiseSource = String -> (Double, Double, Double) -> Double

mapReferences :: (String -> String) -> Density -> Density
mapReferences rename = go
  where
    go (Ref name) = Ref (rename name)
    go (Binary op a b) = Binary op (go a) (go b)
    go (Range a lo hi b c) = Range (go a) lo hi (go b) (go c)
    go (Floor a) = Floor (go a)
    go (Noise name a b) = Noise name (go a) (go b)
    go (NoiseAt name a b c) = NoiseAt name (go a) (go b) (go c)
    go (Cache a) = Cache (go a)
    go value = value

encodeDensity :: Density -> Json
encodeDensity density = case density of
  Constant v -> number v
  Ref name -> string ("backrooms:interior/" ++ name)
  Gradient axis lo hi a b tiled -> node "gradient" [("axis", string (axisName axis)), ("tiling", string (if tiled then "repeat" else "clamp_to_edge")), ("from_coordinate", int lo), ("to_coordinate", int hi), ("from_value", number a), ("to_value", number b)]
  Binary op a b -> node (opName op) [("left", encodeDensity a), ("right", encodeDensity b)]
  Range input lo hi yes no -> node "range_choice" [("input", encodeDensity input), ("min_inclusive", number lo), ("max_exclusive", number hi), ("when_in_range", encodeDensity yes), ("when_out_of_range", encodeDensity no)]
  Floor input -> node "floor" [("input", encodeDensity input)]
  Noise name sx sz -> node "noise" [("noise", string ("backrooms:interior/" ++ name)), ("xz_scale", number 1), ("y_scale", number 0), ("shift_x", encodeDensity sx), ("shift_z", encodeDensity sz)]
  NoiseAt name sx sy sz -> node "noise" [("noise", string ("backrooms:interior/" ++ name)), ("xz_scale", number 1), ("y_scale", number 0), ("shift_x", encodeDensity sx), ("shift_y", encodeDensity sy), ("shift_z", encodeDensity sz)]
  Cache input -> node "cache" [("input", encodeDensity input)]
  where
    node name fields = object (("type", string ("minecraft:" ++ name)) : fields)
    axisName X = "x"
    axisName Y = "y"
    axisName Z = "z"
    opName Add = "add"
    opName Sub = "sub"
    opName Mul = "mul"
    opName Min = "min"
    opName Max = "max"

evaluate :: [(String, Density)] -> NoiseSource -> (Double, Double, Double) -> Density -> Double
evaluate registry = at
  where
    expressions = M.fromList registry
    at noise (x, y, z) = go
      where
        values = M.map go expressions
        go density = case density of
          Constant v -> v
          Ref name -> maybe (error ("Unknown density: " ++ name)) id (M.lookup name values)
          Gradient axis lo hi a b tiled ->
            let v = case axis of X -> x; Y -> y; Z -> z
                t = (v - fromIntegral lo) / fromIntegral (hi - lo)
                u = if tiled then t - fromIntegral (floor t :: Int) else max 0 (min 1 t)
             in a + u * (b - a)
          Binary op a b -> let f = case op of Add -> (+); Sub -> (-); Mul -> (*); Min -> min; Max -> max in f (go a) (go b)
          Range input lo hi yes no -> let v = go input in go (if v >= lo && v < hi then yes else no)
          Floor input -> fromIntegral (floor (go input) :: Int)
          Noise name sx sz -> noise name (x + go sx, 0, z + go sz)
          NoiseAt name sx sy sz -> noise name (x + go sx, go sy, z + go sz)
          Cache input -> go input

evaluateMany :: [(String, Density)] -> NoiseSource -> (Double, Double, Double) -> [Density] -> [Double]
evaluateMany registry noise point = map (evaluate registry noise point)

dependencies :: Density -> [String]
dependencies = nub . go
  where
    go (Ref name) = [name]
    go (Binary _ a b) = go a ++ go b
    go (Range a _ _ b c) = go a ++ go b ++ go c
    go (Floor a) = go a
    go (Noise _ a b) = go a ++ go b
    go (NoiseAt _ a b c) = go a ++ go b ++ go c
    go (Cache a) = go a
    go _ = []

noiseDependencies :: Density -> [String]
noiseDependencies = nub . go
  where
    go (Noise name a b) = name : go a ++ go b
    go (NoiseAt name a b c) = name : go a ++ go b ++ go c
    go (Binary _ a b) = go a ++ go b
    go (Range a _ _ b c) = go a ++ go b ++ go c
    go (Floor a) = go a
    go (Cache a) = go a
    go _ = []

validateRegistry :: [(String, Density)] -> Either String ()
validateRegistry registry = do
  let names = map fst registry
  if length names == M.size entries then Right () else Left "Density rule names must be unique"
  _ <- foldM (visit S.empty) S.empty names
  Right ()
  where
    entries = M.fromList registry
    visit stack done key
      | key `S.member` done = Right done
      | key `S.member` stack = Left ("Cyclic density dependency: " ++ key)
      | otherwise = case M.lookup key entries of
          Nothing -> Left ("Missing density dependency: " ++ key)
          Just value -> S.insert key <$> foldM (visit (S.insert key stack)) done (dependencies value)

infixl 6 .+., .-.

infixl 7 .*.

(.+.), (.-.), (.*.) :: Density -> Density -> Density
(.+.) = Binary Add
(.-.) = Binary Sub
(.*.) = Binary Mul

band :: Density -> Double -> Double -> Density
band d lo hi = Range d lo hi (Constant 1) (Constant 0)

union :: [Density] -> Density
union = foldr (Binary Max) (Constant 0)

intersection :: [Density] -> Density
intersection = foldr (Binary Min) (Constant 1)

select :: Density -> Density -> Density -> Density
select input = Range input 0.5 2

inverse :: Density -> Density
inverse input = Constant 1 .-. input

near :: Density -> Density -> Int -> Density
near a b radius = band (a .-. b) (negate (fromIntegral radius)) (fromIntegral radius + 1)

-- Architectural comparisons use coordinate differences in [-256, 256].
less :: Density -> Density -> Density
less a b = band (a .-. b) (-256) 0

between :: Density -> Density -> Density -> Density
between value lo hi = intersection [inverse (less value lo), less value hi]

repeatAt :: Density -> Double -> Density
repeatAt value period = value .-. Floor (value .*. Constant (1 / period)) .*. Constant period

choice :: Int -> Density -> Density
choice count input = Floor ((Binary Max (Constant (-1)) (Binary Min (Constant 1) input) .+. Constant 1) .*. Constant (fromIntegral count / 2 - 0.0001))

-- Octiles spread normally distributed noise over architectural choices.
octile :: Density -> Density
octile input =
  foldr
    (\(index, limit) rest -> Range input (-1000) limit (Constant (fromIntegral index)) rest)
    (Constant 7)
    (zip [0 :: Int ..] [-0.383, -0.225, -0.106, 0, 0.106, 0.225, 0.383])

-- Approximate normal quantiles (sigma = 1/3) keep catalog entries represented
-- as the catalog grows. The inverse-erf approximation is evaluated by codegen.
quantileChoice :: Int -> Density -> Density
quantileChoice count input
  | count < 1 = error "A choice catalog requires at least one entry"
  | count == 8 = octile input
  | otherwise = foldr step (Constant (fromIntegral (count - 1))) [1 .. count - 1]
  where
    step index = Range input (-1000) (threshold (fromIntegral index / fromIntegral count)) (Constant (fromIntegral (index - 1)))
    threshold probability =
      let x = 2 * probability - 1
          l = log (1 - x * x)
          a = 0.147
          t = 2 / (pi * a) + l / 2
       in signum x * sqrt (2 * (sqrt (t * t - l / a) - t)) / 3

pick :: [Double] -> Density -> Density
pick values input = foldr (\(index, value) rest -> Range input (fromIntegral index) (fromIntegral index + 1) (Constant value) rest) (Constant 0) (zip [0 :: Int ..] values)
