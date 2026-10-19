module Manifold.Scene.DataPack (resources, resourcesFor) where

import Data.List (nub)
import Manifold.Gravity qualified as G
import Manifold.Runtime qualified as R
import Manifold.Scene qualified as S
import Manifold.Stage qualified as B
import Manifold.Stage.Collision qualified as C

resources :: S.Scene -> [(FilePath, String)]
resources scene = resourcesFor "scene" [(condition (S.solidChannel solid), S.solidBox solid) | solid <- S.sceneSolids scene] (Just "objects")
  where
    condition = maybe "" (\i -> R.test ("r.gate" ++ show i) "0" ++ " ")

resourcesFor :: String -> [(String, B.Box)] -> Maybe String -> [(FilePath, String)]
resourcesFor namespace solids dynamic = R.resources namespace (functions namespace solids dynamic)

functions :: String -> [(String, B.Box)] -> Maybe String -> R.Functions
functions namespace solids dynamic =
  [ ("cell", [call "bucket", "return run " ++ call "cell_dispatch"]),
    ("bucket", [R.op "q.bucket" "=" "q.z", R.op "q.bucket" "/=" "r.sixteen", R.op "q.bucket" "*=" "r.four", R.op "q.tmp" "=" "q.y", R.op "q.tmp" "/=" "r.sixteen", R.op "q.bucket" "+=" "q.tmp", R.op "q.bucket" "*=" "r.four", R.op "q.tmp" "=" "q.x", R.op "q.tmp" "/=" "r.sixteen", R.op "q.bucket" "+=" "q.tmp"])
  ]
    ++ R.dispatch namespace "cell_dispatch" "q.bucket" [(i, namespace ++ "/cell/" ++ show i) | (i, _) <- buckets]
    ++ [("cell/" ++ show i, [R.when (channel ++ unwords [R.test ("q." ++ a) (show low ++ ".." ++ show high) | (a, low, high) <- zip3 axes (G.components (B.boxLo box)) (G.components (B.boxHi box))]) "return 1" | (channel, box) <- near origin 0] ++ ["return 0"]) | (i, origin) <- buckets]
    ++ concat [R.dispatch namespace ("sweep_dispatch/" ++ axis) "q.bucket" [(i, namespace ++ "/sweep/" ++ axis ++ "/" ++ show i) | (i, _) <- buckets] | axis <- axes]
    ++ [("clip/" ++ axis, queryPlayer ++ [call "bucket", call ("sweep_dispatch/" ++ axis), dynamicCall ("clip/" ++ axis)]) | axis <- axes]
    ++ [("sweep/" ++ axis ++ "/" ++ show i, [R.when (channel ++ orthogonal axis box) (call ("collision/" ++ axis ++ "/" ++ show j)) | (channel, box) <- near origin 3, let j = indexOf (channel, box) boxes]) | axis <- axes, (i, origin) <- buckets]
    ++ R.dispatch namespace "inside_dispatch" "q.bucket" [(i, namespace ++ "/inside/" ++ show i) | (i, _) <- buckets]
    ++ [("inside", R.set "g.blocked" 0 : queryPlayer ++ [call "bucket", call "inside_dispatch", dynamicCall "inside"])]
    ++ [("inside/" ++ show i, concat [maybe [] id (lookup "inside" (C.compileFunctions ("manifold:" ++ namespace) [(unwords (words (channel)), box)])) | (channel, box) <- near origin 1]) | (i, origin) <- buckets]
    ++ [(name, body) | (name, body) <- C.compileFunctions ("manifold:" ++ namespace) [("", box) | (_, box) <- boxes], take 10 name == "collision/"]
  where
    axes = ["x", "y", "z"]
    call name = R.call (namespace ++ "/" ++ name)
    dynamicCall name = maybe "return 0" (\target -> R.call (target ++ "/" ++ name)) dynamic
    boxes = nub [(condition, image) | (condition, box) <- solids, image <- S.images periodic box, and [G.component a (B.boxHi image) >= -3 && G.component a (B.boxLo image) <= 66 | a <- [0 .. 2]]]
    periodic = either error id (S.compileScene 64 [])
    buckets = [(x + y * 4 + z * 16, (x * 16, y * 16, z * 16)) | z <- [0 .. 3], y <- [0 .. 3], x <- [0 .. 3]]
    near origin margin = [(channel, box) | (channel, box) <- boxes, and [G.component a (B.boxHi box) >= G.component a origin - margin && G.component a (B.boxLo box) <= G.component a origin + 15 + margin | a <- [0 .. 2]]]
    queryPlayer = concat [[R.op ("q." ++ a) "=" ("g." ++ a), R.op ("q." ++ a) "/=" "g.unit", R.op ("q." ++ a) "%=" "r.period"] | a <- axes]
    orthogonal axis box = unwords [R.test ("g." ++ a) (show (lo * G.unit - G.unit `div` 2 - G.bodyHeight) ++ ".." ++ show (hi * G.unit + G.unit `div` 2 + G.bodyHeight)) | (a, lo, hi) <- zip3 axes (G.components (B.boxLo box)) (G.components (B.boxHi box)), a /= axis]
    indexOf :: (Eq a) => a -> [a] -> Int
    indexOf item = go 0 where go _ [] = error "Indexed solid exists"; go i (x : xs) = if item == x then i else go (i + 1) xs
