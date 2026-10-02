module Flame.Pipeline where

import Data.List (nub)
import Flame.Json

newtype Target = Target {targetName :: String} deriving (Eq, Ord, Show)

data Extent = Fixed Int Int | Screen deriving (Eq, Show)

data TargetSpec = TargetSpec Target Extent Bool deriving (Eq, Show)

data Input = Color String Target | Depth String Target deriving (Eq, Show)

data Pass = Pass
  { passShader :: String,
    passVertex :: String,
    passInputs :: [Input],
    passOutput :: Target,
    passParameters :: Maybe [Double]
  }
  deriving (Eq, Show)

data Pipeline = Pipeline [TargetSpec] [Pass] deriving (Eq, Show)

mainTarget :: Target
mainTarget = Target "minecraft:main"

pass :: String -> [Input] -> Target -> Pass
pass shader inputs output = Pass ("flame:post/" ++ shader) "minecraft:core/screenquad" inputs output Nothing

parameterized :: [Double] -> Pass -> Pass
parameterized values p = p {passParameters = Just values}

-- The final target is returned explicitly; callers never guess parity.
pingPong :: Int -> (Target -> Target -> Pass) -> (Target, Target) -> ([Pass], Target)
pingPong count make (first, second) = go count first second
  where
    go 0 current _ = ([], current)
    go n current next = let (rest, final) = go (n - 1) next current in (make current next : rest, final)

inputTarget :: Input -> Target
inputTarget (Color _ t) = t
inputTarget (Depth _ t) = t

inputName :: Input -> String
inputName (Color n _) = n
inputName (Depth n _) = n

validate :: Pipeline -> Either String ()
validate (Pipeline specs passes)
  | length ids /= length (nub ids) = Left "A target is declared twice"
  | any badExtent specs = Left "A target has an invalid extent"
  | otherwise = mapM_ check passes
  where
    ids = [t | TargetSpec t _ _ <- specs]
    known = mainTarget : ids
    badExtent (TargetSpec _ (Fixed w h) _) = w < 1 || h < 1
    badExtent _ = False
    check p
      | any (`notElem` known) (passOutput p : map inputTarget (passInputs p)) = Left "Pass refers to an undeclared target"
      | passOutput p `elem` map inputTarget (passInputs p) = Left "A pass samples its own output"
      | let names = map inputName (passInputs p), length names /= length (nub names) = Left "Sampler names must be unique per pass"
      | otherwise = Right ()

compile :: Pipeline -> Either String Json
compile pipeline@(Pipeline specs passes) = do
  validate pipeline
  pure $ object [("targets", object (map compileTarget specs)), ("passes", array (map compilePass passes))]
  where
    compileTarget (TargetSpec t extent persistent) =
      (targetName t, object (("persistent", bool persistent) : dimensions extent))
    dimensions Screen = []
    dimensions (Fixed w h) = [("width", int w), ("height", int h)]
    compilePass p =
      object $
        [ ("vertex_shader", string (passVertex p)),
          ("fragment_shader", string (passShader p)),
          ("inputs", array (map compileInput (passInputs p))),
          ("output", string (targetName (passOutput p)))
        ]
          ++ maybe [] (\xs -> [("uniforms", object [("Parameters", array [object [("name", string "Values"), ("type", string "vec4"), ("value", array (map number xs))]])])]) (passParameters p)
    compileInput i =
      object $
        [("sampler_name", string (inputName i)), ("target", string (targetName (inputTarget i)))]
          ++ case i of
            Depth _ _ -> [("use_depth_buffer", bool True)]
            _ -> []
