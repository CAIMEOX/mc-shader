module VerticalSemantics (tests) where

import Backrooms.WorldGen.Block qualified as B
import Backrooms.WorldGen.Coordinates qualified as C
import Backrooms.WorldGen.Density
import Backrooms.WorldGen.Floors qualified as F
import Backrooms.WorldGen.Geometry qualified as G
import Backrooms.WorldGen.Layout qualified as Layout
import Backrooms.WorldGen.Navigation qualified as N
import Backrooms.WorldGen.Partition qualified as P
import Backrooms.WorldGen.Vertical qualified as V
import Control.Monad (unless)
import Data.Map.Strict qualified as M
import Data.Set qualified as S
import WorldGenSemantics (noise)

assert :: String -> Bool -> IO ()
assert label ok = unless ok (fail label)

tests :: IO ()
tests = do
  floorTests
  mapM_ (uncurry coreTests) [(kind, swapped) | kind <- [minBound .. maxBound], swapped <- [False, True]]
  reservationTests

floorTests :: IO ()
floorTests = do
  let frame = C.region 48 128
      floors = F.compile (C.y frame)
      registry = C.rules frame ++ F.rules floors
      at y = evaluateMany registry (noise 17) (20, fromIntegral y, 20) [F.walkY floors, F.localY floors, F.noisePlane floors]
  mapM_ (\f -> assert "Floor support and headroom retain a single floor identity" (all (\y -> at y == [fromIntegral f, fromIntegral (y - f), fromIntegral ((f - F.entranceY) `div` F.pitch * 64)]) [f - 1 .. f + F.pitch - 2])) F.walkLevels
  let coordinateNoise _ p = let (_, y, _) = p in y
  assert "Noise planes use the declared sample height" (evaluate [] coordinateNoise (7, 82, 9) (NoiseAt "probe" (Constant 0) (Constant 128) (Constant 0)) == 128)

coreTests :: V.Kind -> Bool -> IO ()
coreTests kind swapped = do
  let frame = C.region 48 128
      core = V.compile frame
      replace key value = case key of
        "vertical/kind" -> Constant (fromIntegral (fromEnum kind))
        "vertical/lo_x" -> Constant 16
        "vertical/lo_z" -> Constant 16
        "vertical/transpose" -> Constant (if swapped then 1 else 0)
        "vertical/active" -> Constant 1
        _ -> value
      registry = C.rules frame ++ [(key, replace key value) | (key, value) <- V.rules core]
      sample p@(x, y, z) = case evaluateMany registry (noise 1) (fromIntegral x, fromIntegral y, fromIntegral z) (V.solid core : map (Ref . fst) (V.materialMasks core)) of
        occupied : masks | occupied > 0 -> case [state | ((_, state), mask) <- zip (V.materialMasks core) masks, mask > 0] of
          state : _ -> state
          [] -> error ("A solid core voxel needs a material: " ++ show p)
        _ -> B.air
      n = V.size kind
      positions = [(x, y, z) | x <- [16 .. 16 + n - 1], z <- [16 .. 16 + n - 1], y <- [F.lowestY - 1 .. F.highestY + 3]]
      blocks = M.fromList [(p, sample p) | p <- positions]
      at p = M.findWithDefault B.air p blocks
      allowed = S.fromList [p | p@(_, y, _) <- positions, y <= F.highestY + 1, N.navigable at p]
      transform (x, y, z) = (16 + (if swapped then z else x), y, 16 + (if swapped then x else z))
      start = transform (1, F.lowestY, 1)
      reached = N.reachable at allowed start
      required = V.stairPath kind ++ maybe [] (\(a, b) -> [a, b]) (V.ladderRoute kind)
  either fail pure (validateRegistry registry)
  assert ("Every core landing connects in both orientations: " ++ show (kind, swapped, S.size allowed, S.size reached, take 5 (S.toList (allowed S.\\ reached)))) (allowed == reached)
  assert "Core movement waypoints are supported and connected" (all ((`S.member` reached) . transform) required)
  let path = map transform (V.stairPath kind)
      segment (a@(ax, ay, az), b@(bx, by, bz)) = do
        let betweenInt value lo hi = value >= min lo hi && value <= max lo hi
            corridor = S.filter (\(x, y, z) -> betweenInt y ay by && ((ax == bx && x == ax && betweenInt z az bz) || (az == bz && z == az && betweenInt x ax bx))) allowed
        assert ("Each stair-route segment preserves a continuous walking line: " ++ show (kind, a, b)) (b `S.member` N.reachable at corridor a)
  mapM_ segment (zip path (drop 1 path))
  assert "Every story has a connected core landing" (all (\f -> any (\(_, y, _) -> y == f) (S.toList reached)) F.walkLevels)
  mapM_
    ( \(p@(x, y, z), state) -> case lookup "facing" (B.properties state) of
        Just direction | B.climbable (Just state) -> let backing = case direction of "east" -> (x - 1, y, z); "west" -> (x + 1, y, z); "north" -> (x, y, z + 1); _ -> (x, y, z - 1) in assert ("Ladder backing is present at " ++ show p) (B.supports (Just (at backing)))
        _ -> pure ()
    )
    (M.toList blocks)

reservationTests :: IO ()
reservationTests = do
  let frame = C.region 48 128
      core = V.compile frame
      layout = Layout.compileReserved frame (V.active core) (V.localBounds core)
      plan = P.compileWithin frame (P.Specification "reserved" 8 (Layout.seedBounds layout) (Layout.subdivide layout) (Layout.crowded layout))
      registry = C.rules frame ++ V.rules core ++ Layout.rules layout ++ P.rules plan
      points = [(x, y, z) | x <- [-288, -272 .. 280 :: Int], z <- [-288, -272 .. 280 :: Int], y <- F.walkLevels]
      at (x, y, z) = evaluate registry (noise 17) (fromIntegral x, fromIntegral y, fromIntegral z)
  either fail pure (validateRegistry registry)
  mapM_
    ( \p -> case map (at p) [V.active core, Ref "vertical/x", Ref "vertical/z", Ref "vertical/lo_x", Ref "vertical/lo_z", Ref "vertical/size"] of
        [enabled, x, z, lx, lz, n] | enabled > 0 -> do
          let origin t = fromIntegral (floor (t / 48) :: Int) * 48
          assert "Core reservations and collars fit inside the landmark-free central square" (origin x + lx - 3 >= 64 && origin z + lz - 3 >= 64 && origin x + lx + n + 3 <= 128 && origin z + lz + n + 3 <= 128)
        _ -> pure ()
    )
    points
  mapM_
    ( \p -> case map (at p) (G.boundsValues (P.leaves plan) ++ [C.x frame, C.z frame, Layout.circulation layout]) of
        [a, b, c, d, x, z, route] -> do
          assert "Reserved room subdivision contains its query point" (a <= x && x < b && c <= z && z < d)
          assert "Reserved circulation stays clear of partition walls" (route == 0 || all ((== 0) . at p) (P.walls plan))
        _ -> fail "Expected room bounds and local coordinates"
    )
    points
