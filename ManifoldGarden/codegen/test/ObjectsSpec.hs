module ObjectsSpec (run) where

import Control.Monad (foldM, unless)
import Data.Map.Strict qualified as M
import Data.Set qualified as S
import Manifold.Objects qualified as O
import Manifold.Scene qualified as Scene
import Manifold.Stage (Box (..))
import Manifold.ThreeRings qualified as T

assert :: Bool -> String -> IO ()
assert ok message = unless ok (fail message)

run :: IO ()
run = do
  either fail pure (O.validateDefinitions T.scene T.cubes)
  either fail pure (Scene.validateCircuits T.scene (map O.cubeId T.cubes) T.circuits)
  let blank = either error id (Scene.compileScene 64 [])
      base = O.Cube 0 (0, 1, 0) (8, 63, 4) O.Resting
      runEvent scene event world = either fail pure (O.apply scene [] event world)
  let doorway = either error id (Scene.compileScene 64 [Scene.Solid (Box (0, 0, 0) (8, 4, 0) "minecraft:quartz_block") Nothing, Scene.Solid (Box (3, 1, 0) (5, 3, 0) "minecraft:white_concrete") (Just 0)])
  assert (Scene.solidAt doorway [False] (4, 2, 0) && not (Scene.solidAt doorway [True] (4, 2, 0)) && Scene.solidAt doorway [True] (4, 0, 0)) "Door apertures preserve their sill and share open-state occupancy across backends"
  let seamScene = either error id (Scene.compileScene 64 [Scene.Solid (Box (-2, -2, 62) (2, 1, 65) "minecraft:quartz_block") Nothing, Scene.Solid (Box (-1, -1, 63) (1, 0, 64) "minecraft:white_concrete") (Just 0)])
      points = [(x, y, z) | x <- [0, 1, 2, 3, 31, 32, 60, 61, 62, 63], y <- [0, 1, 2, 3, 31, 32, 60, 61, 62, 63], z <- [0, 1, 2, 3, 31, 32, 60, 61, 62, 63]]
  mapM_
    ( \scene -> do
        let clipped = either error id (Scene.compileScene 64 (Scene.canonicalSolids scene))
        mapM_ (\opened -> mapM_ (\p -> assert (Scene.solidAt scene (replicate 3 opened) p == Scene.solidAt clipped (replicate 3 opened) p) "Canonical ray cells preserve periodic surfaces and door state") points) [False, True]
    )
    [T.scene, seamScene]
  (falling, _) <- runEvent blank (O.Turn (0, 1, 0)) (O.initial [base])
  (wrapped, _) <- runEvent blank O.Step falling
  assert (O.cubeCell (O.cubes wrapped M.! 0) == (8, 0, 4)) "A cube crosses the periodic boundary with the same identity"
  (frozen, _) <- runEvent blank (O.Turn (-1, 0, 0)) wrapped
  (still, delta) <- runEvent blank O.Step frozen
  assert (still == frozen && O.visitedObjects delta == 0 && S.null (O.active still)) "Frozen cubes leave the active set"
  let stacked = O.initial [O.Cube 0 (0, -1, 0) (4, 4, 4) O.Resting, O.Cube 1 (0, -1, 0) (4, 5, 4) O.Resting]
  (removed, _) <- runEvent blank (O.Take 0) stacked
  assert (O.active removed == S.singleton 1) "Removing support wakes the dependent cube"
  let floorScene = either error id (Scene.compileScene 64 [Scene.Solid (Box (0, 0, 0) (63, 0, 63) "minecraft:quartz_block") Nothing])
      sleeperCount count = O.initial [O.Cube i (0, 1, 0) (i `mod` 64, 40 + i `div` 64, 50) O.Resting | i <- [0 .. count - 1]]
  mapM_ (\count -> do (_, change) <- runEvent floorScene O.Step (sleeperCount count); assert (O.visitedObjects change == 0) "Sleeping objects add no movement visits") [3, 30, 300]
  let expected scene channels cell = any (\solid -> Scene.enabled channels solid && Scene.containsCell scene (Scene.solidBox solid) cell) (Scene.sceneSolids scene)
  mapM_ (\cell -> assert (Scene.solidAt T.scene [False, False, False] cell == expected T.scene [False, False, False] cell) "Spatial buckets preserve solid occupancy") [(x, y, z) | x <- [-1, 0, 5, 26, 32, 38, 50, 63, 64], y <- [-1, 0, 3, 8, 31, 63, 64], z <- [0, 4, 9, 18, 21, 28, 63]]
  let solveEvents = [O.Turn (0, 1, 0), O.Take 0, O.Put (26, 63, 4), O.Turn (-1, 0, 0), O.Take 1, O.Put (52, 3, 18), O.Turn (0, 0, 1), O.Take 2, O.Put (24, 3, 28), O.Turn (0, 1, 0), O.Take 0, O.Put (38, 63, 12), O.Turn (-1, 0, 0), O.Take 1, O.Put (38, 3, 9), O.Turn (0, 0, 1), O.Take 2, O.Put (38, 3, 28)]
  solved <- foldM (\world event -> fst <$> either fail pure (O.apply T.scene T.circuits event world)) (O.initial T.cubes) solveEvents
  assert (T.complete solved && take 2 (O.channels solved) == [True, True]) "Reusable cube roles connect all three final sockets"
  putStrLn "Passed: object identity, frozen activity, support dependencies, spatial occupancy and three-ring circuits."
