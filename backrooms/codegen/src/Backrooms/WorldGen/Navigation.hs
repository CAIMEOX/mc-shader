module Backrooms.WorldGen.Navigation (Point, navigable, reachable) where

import Backrooms.WorldGen.Block qualified as B
import Data.Sequence qualified as Q
import Data.Set qualified as S

type Point = (Int, Int, Int)

-- Integer foot positions include supported walking, one-block jumps and
-- backed ladder movement. Native movement checks cover the half-step shapes.
navigable :: (Point -> B.BlockState) -> Point -> Bool
navigable at p@(x, y, z) = clear p && clear (x, y + 1, z) && (B.supports (Just (at (x, y - 1, z))) || ladder at p)
  where
    clear = B.passable . Just . at

ladder :: (Point -> B.BlockState) -> Point -> Bool
ladder at p@(x, y, z) = B.climbable (Just (at p)) || B.climbable (Just (at (x, y - 1, z)))

reachable :: (Point -> B.BlockState) -> S.Set Point -> Point -> S.Set Point
reachable at allowed start = go (S.singleton start) (Q.singleton start)
  where
    go seen queue = case Q.viewl queue of
      Q.EmptyL -> seen
      p@(x, y, z) Q.:< rest ->
        let adjacent = [(a, y + dy, b) | (a, b) <- [(x - 1, z), (x + 1, z), (x, z - 1), (x, z + 1)], dy <- [0, -1, 1], dy <= 0 || B.passable (Just (at (x, y + 2, z)))] ++ [(x, y + dy, z) | dy <- [-1, 1], ladder at p, ladder at (x, y + dy, z)]
            fresh = filter (\q -> q `S.member` allowed && q `S.notMember` seen) adjacent
         in go (foldr S.insert seen fresh) (rest Q.>< Q.fromList fresh)
