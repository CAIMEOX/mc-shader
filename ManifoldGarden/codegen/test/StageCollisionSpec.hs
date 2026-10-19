module StageCollisionSpec (checks) where

import Control.Monad (forM_, unless)
import Manifold.Gravity qualified as G
import Manifold.Stage.Collision

checks :: IO ()
checks = do
  let at (x, y, z) = (x * G.unit, y * G.unit, z * G.unit)
  forM_ G.downDirections $ \direction -> do
    let axis = sum [i | (i, v) <- zip [0 ..] (G.components direction), v /= 0]
        sign = G.component axis direction
        halfExtent = G.extents direction
        centre = at (if axis == 0 then (0, 8, 0) else (8, 0, 0))
        start = G.add centre (G.scale (-sign * 4 * G.unit) (G.axes !! axis))
        expected = sign * (4 * G.unit - G.beamRadius - G.bodyHeight)
        step = sweepDelta start halfExtent axis (sign * 4 * G.unit)
        contact = G.add start (G.scale step (G.axes !! axis))
    ensure "Sweeps stop at lattice faces in all six directions" (step == expected)
    ensure "A contact pose has exact clearance" (not (intersects contact halfExtent))
    ensure "A one-unit penetration is rejected" (intersects (G.add contact direction) halfExtent)
    ensure "Moving into a face from contact has zero travel" (sweepDelta contact halfExtent axis sign == 0)
    ensure "Moving away from contact retains displacement" (sweepDelta contact halfExtent axis (-sign) == -sign)

  let halfExtent = G.extents (0, -1, 0)
      start = at (8, 28, 0)
      face = G.period - G.beamRadius - G.bodyHeight
  ensure "A sweep reaches the next periodic beam" (sweepDelta start halfExtent 1 G.terminalSpeed == face - 28 * G.unit)
  let tangentStart = (8 * G.unit, 5 * G.unit, G.beamRadius + G.bodyRadius)
  ensure "Exact orthogonal contact permits an axial slide" (sweepDelta tangentStart halfExtent 1 (-4 * G.unit) == -4 * G.unit)
  forM_ [(x, y, z) | x <- [0, 2, 8, 16, 31], y <- [0, 1, 3, 16, 31], z <- [0, 2, 16, 30, 31]] $ \p ->
    forM_ G.downDirections $ \direction ->
      forM_ [0 .. 2] $ \axis ->
        forM_ [-5 * G.unit, -G.terminalSpeed, -1, 0, 1, G.terminalSpeed, 5 * G.unit] $ \speed -> do
          let position = at p
              extent = G.extents direction
          ensure "Candidate filtering preserves swept contacts for every gravity and velocity" (sweepBoxes collisionBoxes position extent axis speed == sweepBoxes (sweepCandidates collisionBoxes position axis) position extent axis speed)
  putStrLn "Passed: native lattice sweeps, six-face contacts, clearance and periodic beams."
  where
    ensure message condition = unless condition (fail message)
