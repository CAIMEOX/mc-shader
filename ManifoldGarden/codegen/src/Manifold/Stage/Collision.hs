module Manifold.Stage.Collision (functions, collisionBoxes, sweepDelta, intersects, periodicBoxes, sweepBoxes, intersectsBoxes, sweepCandidates, compileFunctions) where

import Data.List (nub)
import Manifold.Gravity qualified as G
import Manifold.Stage qualified as Stage

-- Include every periodic solid reachable during a maximum-speed sweep from
-- the canonical cell, allowing for the largest body half extent as well.
collisionBoxes :: [Stage.Box]
collisionBoxes = periodicBoxes Stage.stageBoxes

periodicBoxes :: [Stage.Box] -> [Stage.Box]
periodicBoxes solids =
  nub
    [ shifted
    | box <- solids,
      x <- [-cellSize, 0, cellSize],
      y <- [-cellSize, 0, cellSize],
      z <- [-cellSize, 0, cellSize],
      let offset = (x, y, z)
          shifted = box {Stage.boxLo = G.add (Stage.boxLo box) offset, Stage.boxHi = G.add (Stage.boxHi box) offset},
      intersectsReach shifted
    ]
  where
    cellSize = G.period `div` G.unit
    margin = G.terminalSpeed + G.bodyHeight
    intersectsReach box =
      and
        [ low * G.unit - G.unit `div` 2 < G.period + margin && high * G.unit + G.unit `div` 2 > -margin
        | (low, high) <- zip (G.components (Stage.boxLo box)) (G.components (Stage.boxHi box))
        ]

-- Expanded native block bounds use the gravity controller's fixed-point unit.
expandedBounds :: G.V -> Stage.Box -> (G.V, G.V)
expandedBounds halfExtent box =
  ( G.vector (zipWith (\x h -> x * G.unit - G.unit `div` 2 - h) (G.components (Stage.boxLo box)) (G.components halfExtent)),
    G.vector (zipWith (\x h -> x * G.unit + G.unit `div` 2 + h) (G.components (Stage.boxHi box)) (G.components halfExtent))
  )

-- Clip one axial displacement to the first forward face. Exact contact is a
-- legal pose; the orthogonal projections must overlap strictly to collide.
sweepDelta :: G.V -> G.V -> Int -> Int -> Int
sweepDelta = sweepBoxes collisionBoxes

sweepBoxes :: [Stage.Box] -> G.V -> G.V -> Int -> Int -> Int
sweepBoxes boxes position halfExtent axis displacement =
  foldl clip displacement boxes
  where
    clip step box =
      let (low, high) = expandedBounds halfExtent box
          overlaps = and [G.component i position > G.component i low && G.component i position < G.component i high | i <- [0 .. 2], i /= axis]
          p = G.component axis position
          l = G.component axis low
          u = G.component axis high
       in if overlaps && step > 0 && p <= l
            then min step (l - p)
            else
              if overlaps && step < 0 && p >= u
                then max step (u - p)
                else step

intersects :: G.V -> G.V -> Bool
intersects = intersectsBoxes collisionBoxes

intersectsBoxes :: [Stage.Box] -> G.V -> G.V -> Bool
intersectsBoxes boxes position halfExtent = any inside boxes
  where
    inside box =
      let (low, high) = expandedBounds halfExtent box
       in and [G.component i position > G.component i low && G.component i position < G.component i high | i <- [0 .. 2]]

-- Each level owns these functions. The controller supplies g.step; native
-- solids can shorten that displacement after candidate filtering.
-- The bounds g.b* are beamRadius + bodyHalfExtent, as in Gravity.DataPack.
functions :: [(String, [String])]
functions = compileFunctions "manifold:atrium" [("", box) | box <- collisionBoxes]

-- Orthogonal bounds admit every body extent supported by the controller.
candidateRanges :: Int -> Stage.Box -> [(Int, Int, Int)]
candidateRanges axis box = [(i, G.component i (Stage.boxLo box) * G.unit - G.unit `div` 2 - G.bodyHeight, G.component i (Stage.boxHi box) * G.unit + G.unit `div` 2 + G.bodyHeight) | i <- [0 .. 2], i /= axis]

sweepCandidates :: [Stage.Box] -> G.V -> Int -> [Stage.Box]
sweepCandidates boxes position axis = filter (all (\(i, low, high) -> let p = G.component i position in p >= low && p <= high) . candidateRanges axis) boxes

compileFunctions :: String -> [(String, Stage.Box)] -> [(String, [String])]
compileFunctions prefix boxes =
  [("clip/" ++ axis, [execute (conditionsFor conditional ++ ["if score " ++ score ("g." ++ axes !! i) ++ " matches " ++ show low ++ ".." ++ show high | (i, low, high) <- candidateRanges axisIndex box]) ("function " ++ prefix ++ "/collision/" ++ axis ++ "/" ++ show j) | (j, (conditional, box)) <- numbered]) | (axisIndex, axis) <- zip [0 ..] axes]
    ++ [("inside", concatMap inside boxes)]
    ++ [("collision/" ++ axis ++ "/" ++ show j, clip axis ("", box)) | axis <- axes, (j, (_, box)) <- numbered]
  where
    numbered = zip [0 :: Int ..] boxes
    conditionsFor conditional = [conditional | not (null conditional)]
    bounds box =
      concat
        [ [ set ("h.col.l" ++ axis) (low * G.unit - G.unit `div` 2 + G.beamRadius),
            operation ("h.col.l" ++ axis) "-=" ("g.b" ++ axis),
            set ("h.col.u" ++ axis) (high * G.unit + G.unit `div` 2 - G.beamRadius),
            operation ("h.col.u" ++ axis) "+=" ("g.b" ++ axis)
          ]
        | (axis, low, high) <- zip3 axes (G.components (Stage.boxLo box)) (G.components (Stage.boxHi box))
        ]
    overlaps axis =
      [compareScore ("g." ++ axis) ">" ("h.col.l" ++ axis), compareScore ("g." ++ axis) "<" ("h.col.u" ++ axis)]
    clip axis (conditional, box) =
      bounds box
        ++ [ operation "h.col.distance" "=" ("h.col.l" ++ axis),
             operation "h.col.distance" "-=" ("g." ++ axis),
             execute
               (conditionsFor conditional ++ concatMap overlaps (filter (/= axis) axes) ++ ["if score #g.step manifold matches 1..", compareScore ("g." ++ axis) "<=" ("h.col.l" ++ axis)])
               (operation "g.step" "<" "h.col.distance"),
             operation "h.col.distance" "=" ("h.col.u" ++ axis),
             operation "h.col.distance" "-=" ("g." ++ axis),
             execute
               (conditionsFor conditional ++ concatMap overlaps (filter (/= axis) axes) ++ ["if score #g.step manifold matches ..-1", compareScore ("g." ++ axis) ">=" ("h.col.u" ++ axis)])
               (operation "g.step" ">" "h.col.distance")
           ]
    inside (conditional, box) = bounds box ++ [execute (conditionsFor conditional ++ concatMap overlaps axes) (set "g.blocked" 1)]

axes :: [String]
axes = ["x", "y", "z"]

score :: String -> String
score name = "#" ++ name ++ " manifold"

set :: String -> Int -> String
set name value = "scoreboard players set " ++ score name ++ " " ++ show value

operation :: String -> String -> String -> String
operation target op source = "scoreboard players operation " ++ score target ++ " " ++ op ++ " " ++ score source

compareScore :: String -> String -> String -> String
compareScore a op b = "if score " ++ score a ++ " " ++ op ++ " " ++ score b

execute :: [String] -> String -> String
execute conditions command = "execute " ++ unwords conditions ++ " run " ++ command
