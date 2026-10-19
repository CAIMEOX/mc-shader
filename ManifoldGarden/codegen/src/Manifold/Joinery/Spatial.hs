module Manifold.Joinery.Spatial (functions, pose, axes, call) where

import Manifold.Gravity qualified as G
import Manifold.Joinery qualified as J
import Manifold.Runtime qualified as R
import Manifold.Stage qualified as B
import Manifold.Stage.Collision qualified as C

axes :: [String]
axes = ["x", "y", "z"]

pose :: Int -> String -> String
pose i a = "j.p" ++ show i ++ a

call :: String -> String
call name = R.call ("joinery/" ++ name)

functions :: R.Functions
functions = collision ++ projection ++ ray

-- Collision queries translate the player into each member's local coordinates.
-- Static compiled boxes retain their exact notches in every gravity frame.
collision :: R.Functions
collision =
  [("scene/" ++ kind, [R.set "g.blocked" 0 | kind == "inside"] ++ save ++ concat [local i ++ [call ("shape/" ++ show i ++ "/" ++ kind)] | i <- [0 .. 5 :: Int]] ++ restore) | kind <- ["inside", "clip/x", "clip/y", "clip/z"]]
    ++ concat [map (\(name, body) -> ("shape/" ++ show i ++ "/" ++ name, body)) (C.compileFunctions ("manifold:joinery/shape/" ++ show i) [("", b) | b <- J.boxes rod]) | rod <- J.rods, let i = J.rodId rod]
    ++ [("player/" ++ show i ++ "/" ++ show d, [R.set "g.blocked" 0] ++ save ++ local i ++ [call ("swept/" ++ show i ++ "/" ++ show d ++ "/inside")] ++ restore) | i <- [0 .. 5 :: Int], d <- [0 .. 5 :: Int]]
    ++ concat [map (\(name, body) -> ("swept/" ++ show i ++ "/" ++ show d ++ "/" ++ name, body)) [(name, body) | (name, body) <- C.compileFunctions "manifold:joinery" [("", b) | b <- J.motionBoxes rod (0, 0, 0) direction], name == "inside"] | rod <- J.rods, let i = J.rodId rod, (d, direction) <- zip [0 :: Int ..] G.downDirections]
  where
    save = [R.op ("j.saved" ++ a) "=" ("g." ++ a) | a <- axes]
    restore = [R.op ("g." ++ a) "=" ("j.saved" ++ a) | a <- axes]
    local i = concat [[R.op ("g." ++ a) "=" ("j.saved" ++ a), R.op ("g." ++ a) "-=" ("j.s" ++ show i ++ a), R.op ("g." ++ a) "%=" "g.period"] | a <- axes]

-- Build only the active collision window. Each box needs at most two images per
-- axis; clip in logical space, then rotate integer bounds into the native room.
projection :: R.Functions
projection =
  [ ("materialize", [R.when (R.test "r.target" (show slot)) (R.call ("rooms/origin/" ++ show slot)) | slot <- [0, 1 :: Int]] ++ concat [project rod box | rod <- J.rods, box <- J.boxes rod]),
    ("project/box", [R.when (unwords [R.cmp ("j.l" ++ a) "<=" ("j.u" ++ a) | a <- axes]) (call "project/fill")]),
    ("project/fill", [R.when (R.test "r.frame" (show frame)) (call ("project/rotate/" ++ show frame)) | frame <- [0 .. 23 :: Int]] ++ [R.when (R.test "r.target" "1") (R.add ("j." ++ side ++ "x") 80) | side <- ["l", "u"]] ++ [R.add ("j." ++ side ++ "y") 200 | side <- ["l", "u"]] ++ [R.put ("joinery_fill." ++ side ++ a) ("j." ++ side ++ a) | side <- ["l", "u"], a <- axes] ++ [call "project/native with storage manifold:runtime joinery_fill"]),
    ("project/native", ["$fill $(lx) $(ly) $(lz) $(ux) $(uy) $(uz) minecraft:stripped_oak_wood"])
  ]
    ++ [("project/rotate/" ++ show frame, [R.op ("j.tmp" ++ side ++ a) "=" ("j." ++ side ++ a) | side <- ["l", "u"], a <- axes] ++ concat [let v = B.transformBlock basis unit; index = sum [k | k <- [0 .. 2], G.component k v /= 0]; sign = G.component index v in [R.op ("j." ++ side ++ axes !! index) "=" ("j.tmp" ++ (if sign < 0 then if side == "l" then "u" else "l" else side) ++ a)] ++ [R.op ("j." ++ side ++ axes !! index) "*=" "g.neg" | sign < 0] | (a, unit) <- zip axes G.axes, side <- ["l", "u"]]) | (frame, basis) <- zip [0 :: Int ..] G.frames]
  where
    project rod box =
      concat [[R.op ("j.base" ++ a) "=" (pose (J.rodId rod) a), R.op ("j.base" ++ a) "*=" "r.four", R.add ("j.base" ++ a) (lo + 6), R.op ("j.base" ++ a) "-=" ("r.o" ++ a), R.op ("j.base" ++ a) "%=" "r.period", R.add ("j.base" ++ a) (-6)] | (a, lo) <- zip axes (G.components (B.boxLo box))]
        ++ concat [concat [[R.op ("j.l" ++ a) "=" ("j.base" ++ a), R.add ("j.l" ++ a) delta, R.op ("j.u" ++ a) "=" ("j.l" ++ a), R.add ("j.u" ++ a) (hi - lo), R.op ("j.l" ++ a) ">" "j.low", R.op ("j.u" ++ a) "<" "j.high"] | (a, lo, hi, delta) <- zip4 axes (G.components (B.boxLo box)) (G.components (B.boxHi box)) [x, y, z]] ++ [call "project/box"] | x <- [0, -64], y <- [0, -64], z <- [0, -64]]
    zip4 as bs cs ds = zipWith (\(a, b, c) d -> (a, b, c, d)) (zip3 as bs cs) ds

-- An event-driven voxel DDA selects the first timber hit, including copies
-- outside the native room. The idle tick checks one tool and its use statistic.
ray :: R.Functions
ray =
  [ ( "ray/start",
      [ R.set "j.hit" (-1),
        R.set "j.ray.steps" 0,
        "execute at @s anchored eyes positioned ^ ^ ^0.0 run tp @e[tag=manifold.direction,limit=1] ~ ~ ~",
        "execute store result score #j.eye manifold run data get entity @e[tag=manifold.direction,limit=1] Pos[1] 4096",
        "execute store result score #j.feet manifold run data get entity @s Pos[1] 4096",
        R.op "j.eye" "-=" "j.feet",
        R.add "j.eye" (-G.bodyHeight),
        "execute positioned 0.0 0.0 0.0 rotated as @s positioned ^ ^ ^1 run tp @e[tag=manifold.direction,limit=1] ~ ~ ~"
      ]
        ++ ["execute store result score #g.l" ++ a ++ " manifold run data get entity @e[tag=manifold.direction,limit=1] Pos[" ++ show i ++ "] 4096" | (i, a) <- zip [0 :: Int ..] axes]
        ++ [R.call "gravity/transform"]
        ++ concat [[R.op ("j.o" ++ a) "=" ("g.d" ++ a), R.op ("j.o" ++ a) "*=" "j.eye", R.op ("j.o" ++ a) "*=" "g.neg", R.op ("j.o" ++ a) "+=" ("g." ++ a), R.add ("j.o" ++ a) (G.unit `div` 2), R.op ("j.o" ++ a) "%=" "g.period", R.op ("j.c" ++ a) "=" ("j.o" ++ a), R.op ("j.c" ++ a) "/=" "j.module", R.op ("j.abs" ++ a) "=" ("g.a" ++ a), R.when (R.test ("j.abs" ++ a) "..-1") (R.op ("j.abs" ++ a) "*=" "g.neg"), R.set ("j.t" ++ a) 100000000, R.set ("j.delta" ++ a) 100000000, R.when (R.test ("j.abs" ++ a) "1..") (call ("ray/init/" ++ a))] | a <- axes]
        ++ [call "ray/step"]
    ),
    ("ray/step", [R.add "j.ray.steps" 1, R.when (R.test "j.ray.steps" "97..") "return 0"] ++ concat [[R.op ("q." ++ a) "=" ("j.c" ++ a), R.op ("q." ++ a) "%=" "r.sixteen"] | a <- axes] ++ [call "cell", R.when (R.test "j.hit" "0..") "return 1", R.op "j.next" "=" "j.tx", R.op "j.next" "<" "j.ty", R.op "j.next" "<" "j.tz", R.when (R.test "j.next" "393217..") "return 0"] ++ [R.when (R.cmp ("j.t" ++ a) "=" "j.next") (call ("ray/advance/" ++ a)) | a <- axes] ++ ["return run " ++ call "ray/step"]),
    ("cell", [R.set "j.hit" (-1)] ++ ["execute if function manifold:joinery/cell/" ++ show i ++ " run return 1" | i <- [0 .. 5 :: Int]] ++ ["return 0"])
  ]
    ++ [("cell/" ++ show i, concat [[R.op ("j.local" ++ a) "=" ("q." ++ a), R.op ("j.local" ++ a) "-=" (pose i a), R.op ("j.local" ++ a) "%=" "r.sixteen"] | a <- axes] ++ [R.set "j.hit" i] ++ [R.when (unwords [R.test ("j.local" ++ a) (show lo ++ ".." ++ show hi) | (a, lo, hi) <- zip3 axes (G.components low) (G.components high)]) "return 1" | (low, high) <- J.mergeCells (J.rodAxis rod) (J.rodCells rod)] ++ [R.set "j.hit" (-1), "return 0"]) | rod <- J.rods, let i = J.rodId rod]
    ++ [("ray/init/" ++ a, [R.op ("j.t" ++ a) "=" ("j.c" ++ a), R.when (R.test ("g.a" ++ a) "1..") (R.add ("j.t" ++ a) 1), R.op ("j.t" ++ a) "*=" "j.module", R.op ("j.t" ++ a) "-=" ("j.o" ++ a), R.when (R.test ("j.t" ++ a) "..-1") (R.op ("j.t" ++ a) "*=" "g.neg"), R.op ("j.t" ++ a) "*=" "g.unit", R.op ("j.t" ++ a) "/=" ("j.abs" ++ a), R.set ("j.delta" ++ a) (4 * G.unit * G.unit), R.op ("j.delta" ++ a) "/=" ("j.abs" ++ a)]) | a <- axes]
    ++ [("ray/advance/" ++ a, [R.when (R.test ("g.a" ++ a) "1..") (R.add ("j.c" ++ a) 1), R.when (R.test ("g.a" ++ a) "..-1") (R.add ("j.c" ++ a) (-1)), R.op ("j.t" ++ a) "+=" ("j.delta" ++ a)]) | a <- axes]
