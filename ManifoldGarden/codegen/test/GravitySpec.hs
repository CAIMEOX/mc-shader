module GravitySpec (checks) where

import Control.Monad (forM_, unless)
import Data.List (nub)
import Manifold.Gravity

checks :: IO ()
checks = do
  ensure "Twenty-four proper cube orientations" (length frames == 24 && length (nub frames) == 24)
  forM_ frames $ \frame@(a, b, c) -> do
    ensure "Frame is orthonormal and right handed" (dot a a == 1 && dot b b == 1 && dot c c == 1 && dot a b == 0 && cross a b == c)
    forM_ downDirections $ \target -> do
      let next = turnFrame frame target
      ensure "Gravity transition preserves a full cube frame" (next `elem` frames && gravity next == target)
      ensure "Reciprocal turn restores heading" (turnFrame next (gravity frame) == frame)
  forM_ downDirections $ \g -> do
    let axis = sum [i | (i, x) <- zip [0 ..] (components g), x /= 0]
        sign = component axis g
        free = (axis + 1) `mod` 3
        start = replace free (8 * unit) (replace axis (if sign < 0 then 4 * unit else period - 4 * unit) (0, 0, 0))
        body = Body start (scale (20 * unit) g) g False
        moved = moveBody body
        bound = beamRadius + bodyHeight
    ensure "Swept collision stops a fast body on every face" (component axis (position moved) == if sign < 0 then bound else period - bound)
    ensure "Ground contact follows gravity" (grounded moved && velocity moved == (0, 0, 0))
    ensure "Contact pose has clearance" (not (inside (position moved) (extents g)))
    let settled = iterate fall moved !! 50
    ensure "Standing remains stable" (position settled == position moved && grounded settled)
  forM_ [(x, y, z) | x <- [-200000, 0, 7000, 45000], y <- [0, 9000, 50000], z <- [0, 8000, 25000]] $ \p ->
    forM_ downDirections $ \g -> do
      let h = extents g
      ensure "Periodic collision uses one cell" (inside p h == inside (add p (period, -period, 3 * period)) h)
      ensure "Signed coordinates fold into the canonical cell" (all (\x -> x >= 0 && x < period) (components (wrap p)))
  let flying = Body (8 * unit, 8 * unit, 8 * unit) (-1000, 350, 90) (0, -1, 0) False
  forM_ downDirections $ \g -> case changeGravity g flying of
    Nothing -> fail "Open space accepts all gravity orientations"
    Just changed -> ensure "Changing gravity preserves position and world momentum" (position changed == position flying && velocity changed == velocity flying)
  let crossing = Body (period - 20, 8 * unit, 8 * unit) (100, 0, 0) (0, -1, 0) False
  ensure "Free flight crosses a periodic boundary" (position (moveBody crossing) == (80, 8 * unit, 8 * unit))
  let nearWall = Body (8 * unit, beamRadius + bodyRadius, 0) (0, 0, 0) (-1, 0, 0) False
  ensure "A gravity change checks the new body's clearance" (changeGravity (0, -1, 0) nearWall == Nothing)
  putStrLn "Passed: six-axis gravity, cube frames, periodic collision, swept contacts and momentum."
  where
    ensure message condition = unless condition (fail message)
