module Backrooms.WorldGen.Partition
  ( Plan,
    Specification (..),
    compile,
    compileWithin,
    rules,
    noiseNames,
    leaves,
    walls,
    openings,
    leafNoise,
  )
where

import Backrooms.WorldGen.Coordinates qualified as C
import Backrooms.WorldGen.Density
import Backrooms.WorldGen.Geometry qualified as G
import Data.List (nub)

data Plan = Plan
  { rules :: [(String, Density)],
    noiseNames :: [String],
    leaves :: G.Bounds,
    walls :: [Density],
    openings :: [Density],
    coordinates :: C.Region,
    specification :: Specification
  }

-- The host layout supplies a coherent seed rectangle and its subdivision policy.
data Specification = Specification
  { prefix :: String,
    levels :: Int,
    initialBounds :: G.Bounds,
    enabled :: Density,
    crowded :: Density
  }

-- Compile a finite point-query partition tree. Region spans are at most 256;
-- the level count is non-negative. Each point follows its own child bounds.
compile :: C.Region -> Int -> Plan
compile region count = compileWithin region (Specification "partition" count (G.Bounds (Constant 0) end (Constant 0) end) (Constant 1) (Constant 0))
  where
    end = Constant (fromIntegral (C.size region))

compileWithin :: C.Region -> Specification -> Plan
compileWithin region spec =
  Plan
    definitions
    (nub (concatMap (noiseDependencies . snd) definitions))
    (limits (node spec count))
    [field (node spec d) "wall" | d <- [0 .. count - 1]]
    [field (node spec d) "opening" | d <- [0 .. count - 1]]
    region
    spec
  where
    count = levels spec
    definitions = initial spec ++ concatMap (nodeRules region spec . node spec) [0 .. count - 1]

leafNoise :: Plan -> String -> (String, Density)
leafNoise plan key = (name, sampleNode (coordinates plan) (node spec (levels spec)) key)
  where
    spec = specification plan
    name = namespace spec (levels spec) ++ "/" ++ key

data Node = Node {level :: Int, path :: String, limits :: G.Bounds}

namespace :: Specification -> Int -> String
namespace spec d = prefix spec ++ "/" ++ show d

node :: Specification -> Int -> Node
node spec d = Node d (namespace spec d) (G.Bounds (ref "lo_x") (ref "hi_x") (ref "lo_z") (ref "hi_z"))
  where
    ref key = Ref (namespace spec d ++ "/" ++ key)

field :: Node -> String -> Density
field current key = Ref (path current ++ "/" ++ key)

initial :: Specification -> [(String, Density)]
initial spec = G.boundsRules (namespace spec 0) (initialBounds spec) ++ [(namespace spec 0 ++ "/active", enabled spec)]

-- Sampling at the node centre gives every block in that node one decision.
sampleNode :: C.Region -> Node -> String -> Density
sampleNode region current key = C.noiseAt region (path current ++ "/" ++ key) cx cz
  where
    (cx, cz) = G.centre (limits current)

data CutFrame = CutFrame
  { axis :: Density,
    here :: Density,
    there :: Density,
    lo :: Density,
    hi :: Density,
    otherLo :: Density,
    otherHi :: Density
  }

cutFrame :: C.Region -> Node -> CutFrame
cutFrame region current = CutFrame selected (choose (C.x region) (C.z region)) (choose (C.z region) (C.x region)) (choose lx lz) (choose hx hz) (choose lz lx) (choose hz hx)
  where
    selected = field current "axis"
    choose = select selected
    G.Bounds lx hx lz hz = limits current

chooseAxis :: C.Region -> Node -> Density
chooseAxis region current = select (less (d .*. Constant 1.35) w) (Constant 1) (select (less (w .*. Constant 1.35) d) (Constant 0) (band (sampleNode region current "axis") 0 1000))
  where
    w = field current "width"
    d = field current "depth"

continuePartition :: C.Region -> Specification -> Node -> Density
continuePartition region spec current
  | level current < 2 = Constant 1
  | level current >= 6 = intersection [crowded spec, keep]
  | otherwise = keep
  where
    keep = inverse (union [compact, corridor, shared, room])
    choose = select (crowded spec)
    largest = Binary Max (field current "width") (field current "depth")
    smallest = Binary Min (field current "width") (field current "depth")
    upper = fromIntegral (C.size region + 1)
    compact = less largest (choose (Constant 10) (Constant 13))
    corridor = intersection [less smallest (choose (Constant 8) (Constant 10)), less largest (choose (Constant 17) (Constant 33)), inverse (less largest (smallest .*. Constant 2.5))]
    shared = intersection [inverse (crowded spec), band smallest 12 upper, band largest 0 33, band (field current "random_stop") 6 8]
    room = choose (intersection [band largest 0 14, band smallest 7 upper, band (field current "random_stop") 6 8]) (intersection [band largest 0 19, band smallest 9 upper, band (field current "random_stop") 4 8])

minimumSpan :: Specification -> Density
minimumSpan spec = select (crowded spec) (Constant 5) (Constant 6)

splitPosition :: Specification -> Node -> CutFrame -> Density
splitPosition spec current cut = Binary Max (lo cut .+. minimumSpan spec) (Binary Min (hi cut .-. minimumSpan spec) (Floor (lo cut .+. (hi cut .-. lo cut) .*. pick ratios (field current "random_cut"))))
  where
    ratios = [0.17, 0.25, 0.33, 0.42, 0.58, 0.67, 0.75, 0.83]

doorPosition :: Node -> CutFrame -> Density
doorPosition current cut = otherLo cut .+. Constant 2 .+. Floor ((otherHi cut .-. otherLo cut .-. Constant 4) .*. (field current "random_door" .*. Constant (1 / 7)))

wallSegment :: Node -> CutFrame -> Density
wallSegment current cut
  | level current < 2 = Constant 1
  | otherwise = select (band (field current "random_join") 0 6) (Constant 1) (less (there cut) (otherHi cut .-. Constant 6))

advanceBounds :: Node -> CutFrame -> G.Bounds
advanceBounds current cut = G.Bounds (carry lx (choose (lower lx) lx)) (carry hx (choose (upper hx) hx)) (carry lz (choose lz (lower lz))) (carry hz (choose hz (upper hz)))
  where
    G.Bounds lx hx lz hz = limits current
    split = field current "split"
    low = less (here cut) split
    choose = select (axis cut)
    lower original = select low original split
    upper original = select low split original
    carry original value = select (field current "divide") value original

nodeRules :: C.Region -> Specification -> Node -> [(String, Density)]
nodeRules region spec current =
  [(name ("random_" ++ key), octile (Cache (sampleNode region current key))) | key <- ["cut", "stop", "door", "join"]]
    ++ [ (name "width", w),
         (name "depth", d),
         (name "axis", chooseAxis region current),
         (name "divide", intersection [f "active", continuePartition region spec current, inverse (less (hi cut .-. lo cut) (minimumSpan spec .*. Constant 2))]),
         (name "split", splitPosition spec current cut),
         (name "door", doorPosition current cut),
         (name "wall", intersection [f "divide", near (here cut) (f "split") 0, wallSegment current cut]),
         (name "opening", intersection [f "divide", near (here cut) (f "split") 2, near (there cut) (f "door") 1])
       ]
    ++ G.boundsRules (namespace spec (level current + 1)) (advanceBounds current cut)
    ++ [(namespace spec (level current + 1) ++ "/active", f "divide")]
  where
    name key = path current ++ "/" ++ key
    f = field current
    (w, d) = G.dimensions (limits current)
    cut = cutFrame region current
