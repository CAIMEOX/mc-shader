module Backrooms.Pipeline where

import Backrooms.Json
import Data.List (nub)

newtype Target = Target {targetName :: String} deriving (Eq, Ord, Show)

data Extent = Fixed Int Int | Screen deriving (Eq, Show)

data TargetSpec = TargetSpec Target Extent Bool deriving (Eq, Show)

data Input = Color String Target | Depth String Target deriving (Eq, Show)

data Pass = Pass {passShader :: String, passVertex :: String, passInputs :: [Input], passOutput :: Target} deriving (Eq, Show)

data Pipeline = Pipeline [TargetSpec] [Pass] deriving (Eq, Show)

mainTarget :: Target
mainTarget = Target "minecraft:main"

pass :: String -> [Input] -> Target -> Pass
pass shader inputs output = Pass ("backrooms:post/" ++ shader) "minecraft:core/screenquad" inputs output

inputTarget :: Input -> Target
inputTarget (Color _ target) = target
inputTarget (Depth _ target) = target

inputName :: Input -> String
inputName (Color name _) = name
inputName (Depth name _) = name

validate :: Pipeline -> Either String ()
validate (Pipeline specs passes)
  | length ids /= length (nub ids) = Left "Target declared twice"
  | any badExtent specs = Left "Invalid target extent"
  | otherwise = mapM_ check passes
  where
    ids = [target | TargetSpec target _ _ <- specs]
    known = mainTarget : ids
    badExtent (TargetSpec _ (Fixed w h) _) = w < 1 || h < 1
    badExtent _ = False
    check p
      | any (`notElem` known) (passOutput p : map inputTarget (passInputs p)) = Left "Undeclared render target"
      | passOutput p `elem` map inputTarget (passInputs p) = Left "Pass reads its own output"
      | let names = map inputName (passInputs p), length names /= length (nub names) = Left "Duplicate sampler name"
      | otherwise = Right ()

compile :: Pipeline -> Either String Json
compile graph@(Pipeline specs passes) = do
  validate graph
  pure (object [("targets", object (map target specs)), ("passes", array (map stage passes))])
  where
    target (TargetSpec name extent persistent) = (targetName name, object (("persistent", bool persistent) : dimensions extent))
    dimensions Screen = []
    dimensions (Fixed w h) = [("width", int w), ("height", int h)]
    stage p = object [("vertex_shader", string (passVertex p)), ("fragment_shader", string (passShader p)), ("inputs", array (map input (passInputs p))), ("output", string (targetName (passOutput p)))]
    input i = object ([("sampler_name", string (inputName i)), ("target", string (targetName (inputTarget i)))] ++ case i of Depth _ _ -> [("use_depth_buffer", bool True)]; _ -> [])
