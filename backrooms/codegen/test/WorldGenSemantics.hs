module WorldGenSemantics (tests, noise) where

import Backrooms.WorldGen.Coordinates qualified as C
import Backrooms.WorldGen.Density
import Backrooms.WorldGen.Furniture qualified as F
import Backrooms.WorldGen.Geometry qualified as G
import Backrooms.WorldGen.Layout qualified as Layout
import Backrooms.WorldGen.Lighting qualified as L
import Backrooms.WorldGen.Partition qualified as P
import Backrooms.WorldGen.Runtime qualified as R
import Control.Monad (unless)
import Data.Char (ord)
import Data.Either (isLeft)
import Data.Map.Strict qualified as M
import Data.Set qualified as S

tests :: IO ()
tests = do
  densityTests
  coordinateTests
  mapM_ (uncurry partitionTests) [(spanXZ, levels) | spanXZ <- [24, 48, 96], levels <- [0, 2, 6]]
  mapM_ rootOpeningTests [C.region spanXZ 128 | spanXZ <- [24, 48, 96]]
  nodeCentreTests
  layoutTests
  densePartitionTests
  furnitureTests
  lightingTests
  floorFrameTests

assert :: String -> Bool -> IO ()
assert label ok = unless ok (fail label)

noise :: Int -> NoiseSource
noise seed name (x, y, z) = fromIntegral ((round (x * 2) * 7919 + round (y * 2) * 65537 + round (z * 2) * 104729 + sum (map ord name) * 15485863 + seed * 32452843) `mod` 2001) / 1000 - 1

densityTests :: IO ()
densityTests = do
  let sample = evaluate [] (noise 1) (0, 0, 0)
      masks = [Constant a | a <- [0, 1]]
  mapM_ (\(a, b) -> assert "Mask union and complement obey De Morgan's law" (sample (inverse (union [a, b])) == sample (intersection [inverse a, inverse b]))) [(a, b) | a <- masks, b <- masks]
  mapM_ (\n -> assert "Periodic coordinates use positive remainders" (sample (repeatAt (Constant (fromIntegral n)) 8) == fromIntegral (n `mod` 8))) [-25 .. 25 :: Int]
  assert "Density references reject missing bindings" (isLeft (validateRegistry [("root", Ref "missing")]))
  assert "Density references reject duplicate bindings" (isLeft (validateRegistry [("a", Constant 1), ("a", Constant 2)]))
  assert "Density references reject recursive cycles" (isLeft (validateRegistry [("a", Ref "b"), ("b", Ref "a")]))
  either fail pure (validateRegistry [("sum", Ref "leaf" .+. Ref "leaf"), ("leaf", Constant 1)])
  let noisy = Cache (Range (Noise "decision" (Constant 0) (Constant 0)) 0 1 (Ref "leaf") (Floor (Noise "detail" (Constant 0) (Constant 0))))
  assert "Registry and noise dependencies retain separate resource identities" (dependencies noisy == ["leaf"] && S.fromList (noiseDependencies noisy) == S.fromList ["decision", "detail"])
  let registry = [("sample", NoiseAt "shared" (Constant 0) (Constant 64) (Constant 0)), ("result", Ref "sample" .+. Constant 2)]
      rename = ("storey/" ++)
      scoped = [(rename key, mapReferences rename value) | (key, value) <- registry]
  either fail pure (validateRegistry scoped)
  assert "Scoping a density graph preserves its samples and noise identity" (all (\p -> evaluate registry (noise 7) p (Ref "result") == evaluate scoped (noise 7) p (Ref (rename "result"))) [(x, y, z) | x <- [-48, 0, 48], y <- [52, 64, 76], z <- [-48, 0, 48]])
  mapM_ (\count -> let choices = map (\n -> round (sample (quantileChoice count (Constant n))) :: Int) [-1, -0.99 .. 1] in assert "Catalog selection covers every entry in order" (S.fromList choices == S.fromList [0 .. count - 1] && and (zipWith (<=) choices (drop 1 choices)))) [1, 8, 9, 16]

coordinateTests :: IO ()
coordinateTests = do
  let region = C.region 24 96
      sample point expr = evaluate (C.rules region) (noise 1) point expr
  either fail pure (validateRegistry (C.rules region))
  mapM_ (\x -> assert "Configured region coordinates repeat across signed world positions" (sample (fromIntegral x, 64, 0) (C.rawX region) == fromIntegral (x `mod` 24))) ([-16385, -49, -24, -1, 0, 23, 24, 49, 16384] :: [Int])
  assert "Configured vertical coordinates clamp at world bounds" (sample (0, -1, 0) (C.y region) == 0 && sample (0, 97, 0) (C.y region) == 96)

partitionTests :: Int -> Int -> IO ()
partitionTests spanXZ levels = do
  let region = C.region spanXZ 128
      plan = P.compile region levels
      registry = C.rules region ++ P.rules plan
      fields = G.boundsValues (P.leaves plan) ++ [C.x region, C.z region]
      points = [(fromIntegral x, 64, fromIntegral z) | x <- [-spanXZ, -spanXZ + 6 .. spanXZ - 1], z <- [-spanXZ, -spanXZ + 6 .. spanXZ - 1]]
      check point = case evaluateMany registry (noise 17) point fields of
        [lx, hx, lz, hz, x, z] -> do
          assert "Partition leaves contain their query point" (lx <= x && x < hx && lz <= z && z < hz)
          assert "Partition leaves remain inside their region with minimum child spans" (lx >= 0 && lz >= 0 && hx <= fromIntegral spanXZ && hz <= fromIntegral spanXZ && hx - lx >= 6 && hz - lz >= 6)
          assert "Zero subdivision levels retain the whole region" (levels /= 0 || [lx, hx, lz, hz] == [0, fromIntegral spanXZ, 0, fromIntegral spanXZ])
        _ -> fail "Partition samples require bounds and two local coordinates"
  either fail pure (validateRegistry registry)
  mapM_ check points

rootOpeningTests :: C.Region -> IO ()
rootOpeningTests region = do
  let plan = P.compile region 1
      registry = C.rules region ++ P.rules plan
      points = [(x, z) | x <- [0 .. C.size region - 1], z <- [0 .. C.size region - 1]]
      at (x, z) expr = evaluate registry (\_ _ -> -0.2) (fromIntegral x, 64, fromIntegral z) expr > 0
      wall = S.fromList (filter (\p -> any (at p) (P.walls plan)) points)
      opening = S.fromList (filter (\p -> any (at p) (P.openings plan)) points)
      xs = S.map fst wall
      zs = S.map snd wall
  assert "Root walls are one block thick and span one region axis" (S.size wall == C.size region && (S.size xs == 1 || S.size zs == 1))
  assert "Partition doors reserve a five by three passage and cut a three-block opening" (S.size opening == 15 && S.size (S.intersection wall opening) == 3)

nodeCentreTests :: IO ()
nodeCentreTests = do
  let region = C.region 48 128
      plan = P.compile region 6
      registry = C.rules region ++ P.rules plan
      (probeName, probe) = P.leafNoise plan "probe"
      source name point@(x, _, z) = if name == probeName then x * 1000 + z else noise 97 name point
      sample point = case evaluateMany registry source point (G.boundsValues (P.leaves plan) ++ [probe]) of
        [a, b, c, d, value] -> ((a, b, c, d), S.singleton value)
        _ -> error "Node centre samples require four bounds and one probe"
      grouped = M.fromListWith S.union (map sample [(fromIntegral x, 64, fromIntegral z) | x <- [0, 3 .. 47 :: Int], z <- [0, 3 .. 47 :: Int]])
  assert "Every leaf room shares one world-space noise sample" (all ((== 1) . S.size) (M.elems grouped))
  assert "Separate leaf rooms sample distinct world-space centres" (S.size (S.unions (M.elems grouped)) == M.size grouped && M.size grouped > 1)

fixture :: (C.Region, G.RoomFrame)
fixture = (region, G.roomFrame (Constant 64) region (G.Bounds (Constant 3) (Constant 23) (Constant 5) (Constant 17)) (Constant 0) (Constant 0))
  where
    region = C.region 48 128

furnitureTests :: IO ()
furnitureTests = mapM_ check [minBound .. maxBound :: F.Family]
  where
    (region, room) = fixture
    opening = G.rectangle room (Constant 5) (Constant 5) (Constant 3) (Constant 2)
    check family = do
      let furnishings = F.compile room (Constant (fromIntegral (fromEnum family))) opening (Constant 0)
          registry = C.rules region ++ F.rules furnishings
          at point expr = evaluate registry (\_ _ -> -0.2) point expr
          passage = [(x, y, z) | x <- [8, 9, 10], y <- [64, 65, 66], z <- [10, 11]]
          points = [(x, 64, z) | x <- [3 .. 22], z <- [5 .. 16]]
      either fail pure (validateRegistry registry)
      assert "Every furniture family preserves opening clearance" (all (\point -> at point opening == 1 && at point (F.solids furnishings) == 0) passage)
      assert "Furniture geometry produces boolean masks" (all (\point -> at point (F.solids furnishings) `elem` [0, 1]) points)
      assert "Material masks belong to solid furniture" (all (\point -> all (\(name, _) -> at point (Ref name) <= at point (F.solids furnishings)) F.materialMasks) points)

lightingTests :: IO ()
lightingTests = mapM_ check [0 .. 7]
  where
    (region, room) = fixture
    check kind = do
      let lights = L.compile room (Constant kind) (Constant 0)
          blocked = L.compile room (Constant kind) (Constant 1)
          registry = C.rules region ++ L.rules lights
          blockedRegistry = C.rules region ++ L.rules blocked
          at defs point expr = evaluate defs (\_ _ -> -0.2) point expr
          roof = [at registry (12, y, 10) (L.roof lights) | y <- [64 .. 74]]
          ceilingY = fromIntegral (64 + length (takeWhile (== 0) roof))
          points = [(x, y, z) | x <- [3 .. 22], y <- [66 .. 71], z <- [5 .. 16]]
          lampPoints = filter (\point -> at registry point (L.lamps lights) > 0) points
      either fail pure (validateRegistry registry)
      assert "Ceilings form a solid upper half-space" (at registry (12, 64, 10) (L.roof lights) == 0 && at registry (12, 74, 10) (L.roof lights) == 1 && and (zipWith (<=) roof (drop 1 roof)))
      assert "Lights occupy the first ceiling layer" (not (null lampPoints) && all (\(_, y, _) -> y == ceilingY) lampPoints)
      assert "Lights preserve clearance from solid room props" (all (\point -> at blockedRegistry point (L.lamps blocked) == 0) points)

layoutTests :: IO ()
layoutTests = mapM_ check [0 .. 3]
  where
    region = C.region 48 128
    layout = Layout.compile region
    check kind = do
      let spec = P.Specification "wing" 8 (Layout.seedBounds layout) (Layout.subdivide layout) (Layout.crowded layout)
          plan = P.compileWithin region spec
          registry = C.rules region ++ [(key, if key == "layout/kind" then Constant kind else value) | (key, value) <- Layout.rules layout] ++ P.rules plan
          sample point = evaluate registry (noise 17) point
          points = [(x, 64, z) | x <- [0 .. 47], z <- [0 .. 47]]
          fields = G.boundsValues (P.leaves plan) ++ [C.x region, C.z region, Layout.circulation layout]
          checkPoint p = case map (sample p) fields of
            [lx, hx, lz, hz, x, z, route] -> do
              assert "Every layout leaf contains its query point" (lx <= x && x < hx && lz <= z && z < hz)
              assert "Circulation and room leaves retain their minimum spans" (min (hx - lx) (hz - lz) >= if route > 0 then 3 else 5)
              assert "Reserved circulation receives no subdivision walls" (route == 0 || all ((== 0) . sample p) (P.walls plan))
            _ -> fail "Layout samples require bounds, coordinates and circulation"
      either fail pure (validateRegistry registry)
      mapM_ checkPoint points
      let passage p = sample p (Layout.circulation layout) > 0 && (sample p (Layout.walls layout) == 0 || sample p (Layout.openings layout) > 0)
          passages = S.fromList [(round x, round z) | p@(x, _, z) <- points, passage p]
      assert "Circulation-first layouts reserve connected passages" (kind < 2 || (not (S.null passages) && R.connected passages (S.findMin passages) == passages))

densePartitionTests :: IO ()
densePartitionTests = do
  let region = C.region 48 128
      initialBounds = G.Bounds (Constant 0) (Constant 48) (Constant 0) (Constant 48)
      compile namespace levels = P.compileWithin region (P.Specification namespace levels initialBounds (Constant 1) (Constant 1))
      shallow = compile "dense" 6
      deep = compile "dense" 8
      at plan p = evaluateMany (C.rules region ++ P.rules plan) (noise 17) p (G.boundsValues (P.leaves plan))
      pairs = [(at shallow p, at deep p) | x <- [0, 2 .. 46], z <- [0, 2 .. 46], let p = (x, 64, z)]
      contained ([a, b, c, d], [e, f, g, h]) = a <= e && f <= b && c <= g && h <= d
      contained _ = False
  assert "Additional dense levels subdivide remaining leaves" (any (uncurry (/=)) pairs && all contained pairs)
  either fail pure (validateRegistry (C.rules region ++ P.rules (compile "east" 4) ++ P.rules (compile "west" 4)))

floorFrameTests :: IO ()
floorFrameTests = do
  let (region, room) = fixture
      shifted = room {G.elevation = G.elevation room .-. Constant 12}
      furniture frame = F.compile frame (Constant (fromIntegral (fromEnum F.Carrels))) (Constant 0) (Constant 0)
      lights frame = L.compile frame (Constant 1) (F.solids (furniture frame))
      registry frame = C.rules region ++ F.rules (furniture frame) ++ L.rules (lights frame)
      fields = map Ref ("props" : "lamps" : "roof" : map fst F.materialMasks)
      check (x, y, z) = evaluateMany (registry room) (noise 1) (x, y, z) fields == evaluateMany (registry shifted) (noise 1) (x, y + 12, z) fields
  assert "Furniture, finishes and lights translate with the floor frame" (all check [(x, y, z) | x <- [3, 6 .. 22], y <- [64 .. 70], z <- [5, 8 .. 16]])
  let narrow = G.roomFrame (Constant 64) region (G.Bounds (Constant 0) (Constant 24) (Constant 0) (Constant 3)) (Constant 0) (Constant 0)
      corridorLighting = L.compile narrow (Constant 0) (Constant 0)
      sample = evaluate (C.rules region ++ L.rules corridorLighting) (const (const (-0.2)))
      lampPoints = [(x, y, z) | x <- [0 .. 23], y <- [66 .. 70], z <- [0 .. 2], sample (x, y, z) (L.lamps corridorLighting) > 0]
  assert "Narrow circulation has lamps aligned with its centre" (not (null lampPoints) && all (\(_, _, z) -> z == 1) lampPoints)
