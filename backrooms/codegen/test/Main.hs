module Main (main) where

import Backrooms.Domain
import Backrooms.Pack (metadata)
import Backrooms.Pipeline
import Backrooms.Program (pipeline)
import Backrooms.Protocol
import Backrooms.Structure.Nbt
import Backrooms.WorldGen qualified as W
import Backrooms.WorldGen.Block qualified as B
import Backrooms.WorldGen.Density (Density (Ref), evaluateMany)
import Backrooms.WorldGen.Geometry qualified as G
import Backrooms.WorldGen.Landmark qualified as L
import Backrooms.WorldGen.Materials qualified as Materials
import Backrooms.WorldGen.Runtime qualified as R
import Backrooms.WorldGen.Spatial qualified as Spatial
import Control.Monad (unless)
import Data.Aeson qualified as A
import Data.Bits (shiftL, shiftR, (.&.))
import Data.ByteString qualified as BS
import Data.Either (isLeft)
import Data.List (nub)
import Data.Map.Strict qualified as M
import Data.Set qualified as Set
import VerticalSemantics qualified as Vertical
import WorldGenSemantics qualified as Components

main :: IO ()
main = do
  let points = [(x, y, z) | x <- [-4, -1, 0, 4], y <- [0, 1.62, 2.8], z <- [11.5, 12, 12.5]]
  mapM_ (\cell -> assert "Portal round trip" (all (\p -> close p (reversePoint cell (mapPoint cell p))) points)) [-2 .. 2]
  assert "Portal lands at hall entrance" (mapPoint 0 (4, 1.62, 12) == (-12, 1.62, 0))
  assert "Hall has larger dimensions" (width (room Hall) > width (room Corridor) && depth (room Hall) > depth (room Corridor))
  assert "Walking opening is free" (all (\p -> not (any (`contains` p) (boxes (room Corridor)))) [(4.5, y, z) | y <- [0.2, 1.6, 2.8], z <- [11.1, 12, 12.9]])
  assert "Door lintel is solid" (any (`contains` (4.5, 3.5, 12)) (boxes (room Corridor)))
  assert "Periodic collision geometry" (all (\(x, y, z) -> occupied (x, y, z) == occupied (x, y, z + 24)) [(x, y, z) | x <- [-4.5, 0, 4.5], y <- [-0.5, 1.5, 5.5], z <- [0.5, 11.5, 12.5, 15.5]])
  mapM_ checkRay rayFixtures
  let values = [30000000, -64, -30000000, 24, 1, 2, 1, 1]
  encoded <- either fail pure (pack values)
  assert "Protocol round trip" (unpack encoded == values)
  let reconstructed = [sum [shiftL (shiftR (value + fieldBias field) (valueShift piece) .&. (2 ^ pieceWidth piece - 1)) (wordShift piece) | ((offset, field), value) <- zip fieldOffsets values, piece <- pieces offset (fieldWidth field), wordIndex piece == i] | i <- [0 .. headerWords - 1]]
  assert "Command fragments retain field bits" (reconstructed == encoded)
  assert "Protocol rejects out-of-range state" (isLeft (pack [0, 0, 0, 24, 1, 2, 2, 0]))
  either fail pure (validate pipeline)
  let t = Target "state"; invalid = Pipeline [TargetSpec t (Fixed 8 1) True] [pass "copy" [Color "Input" t] t]
  assert "Render feedback is explicit" (isLeft (validate invalid))
  assert "Metadata JSON round trip" (A.eitherDecode (A.encode metadata) == Right metadata)
  Components.tests
  Vertical.tests
  worldGenTests
  putStrLn "Haskell semantics passed: runtime partitions, landmark connectivity, density references, portal transforms and render protocol"
  where
    assert label ok = unless ok (fail label)
    close a b = and (zipWith (\x y -> abs (x - y) < 1e-8) (components a) (components b))
    occupied p = any (`contains` p) (collisionVolumes Corridor)
    checkRay ray = assert "Reference ray finds a finite surface" (case referenceHit ray of Just h -> hitDistance h > 0 && hitDistance h < 1000; Nothing -> False)

worldGenTests :: IO ()
worldGenTests = do
  either fail pure W.validateWorldGen
  let tag = CompoundTag [("height", IntTag (-64)), ("label", StringTag "后室"), ("values", ListTag 3 [IntTag 3, IntTag 128])]
  assert "NBT values round trip through the binary seam" (decodeRoot (encodeRoot tag) == Right tag)
  assert "NBT decoder rejects truncated input" (isLeft (decodeRoot (BS.take 7 (encodeRoot tag))))
  mapM_ (\texture -> let bytes = Materials.pixels texture in assert "Material textures have complete opaque pixels" (length bytes == Materials.textureWidth texture * Materials.textureHeight texture * 4 && all (== 255) [a | (i, a) <- zip [0 :: Int ..] bytes, i `mod` 4 == 3])) Materials.textures
  mapM_ (\x -> assert "Local coordinates preserve block boundaries across positive and negative regions" (R.sample (noise 1) (fromIntegral x, 64, 0) "coordinate_x" == fromIntegral (x `mod` R.regionSize))) [-16385, -97, -49, -48, -1, 0, 1, 47, 48, 16384]
  maps <- mapM checkRuntime [1, 2, 3, 17, 97]
  assert "World seed changes interior partition geometry" (length (nub maps) == length maps)
  either fail pure (Spatial.spatialQuality (Spatial.measure (noise 1) [(x, z) | x <- [0, 48, 96], z <- [0, 48, 96]]))
  mapM_ checkLandmark L.templates
  where
    assert label ok = unless ok (fail label)
    noise = Components.noise
    checkRuntime seed = do
      let free = Set.fromList [(x, z) | x <- [-48 .. 47], z <- [-48 .. 47], R.walkable (noise seed) (x, z)]
          reachable = R.connected free (0, 0)
      assert ("Runtime partitions connect across region boundaries, seed " ++ show seed) (free == reachable)
      assert "Runtime floor supports the entrance" (W.sampleDensity (noise seed) (0, 63, 0) "solid" > 0 && R.walkable (noise seed) (0, 0))
      mapM_
        ( \(x, z) -> do
            let (w, d) = G.dimensions R.roomBounds
                spans = evaluateMany R.rules (noise seed) (fromIntegral x, 64, fromIntegral z) [w, d, Ref "layout/circulation"]
            assert "Partition leaves retain room and circulation scales" (case spans of [a, b, route] -> let minimumSpan = if route > 0 then 3 else 5 in all (\n -> n >= minimumSpan && n <= 48) [a, b]; _ -> False)
        )
        [(x, z) | x <- [-45, -39 .. 45 :: Int], z <- [-45, -39 .. 45 :: Int]]
      pure free
    checkLandmark lm = do
      let blocks = M.fromList (L.templateBlocks lm)
          at p = M.lookup p blocks
          (w, _, d) = L.templateDimensions lm
          clear (x, y, z) = B.passable (at (x, y, z)) && B.passable (at (x, y + 1, z))
          ladder (x, y, z) = B.climbable (at (x, y, z)) || B.climbable (at (x, y - 1, z))
          allowed = Set.fromList [(x, y, z) | x <- [0 .. w - 1], z <- [0 .. d - 1], y <- [L.minimumY lm + 1 .. maximum (L.floorLevels lm) + 1], clear (x, y, z), B.supports (at (x, y - 1, z)) || ladder (x, y, z)]
          neighbors p@(x, y, z) = [(a, y + dy, b) | (a, b) <- [(x - 1, z), (x + 1, z), (x, z - 1), (x, z + 1)], dy <- [0, -1, 1], dy <= 0 || B.passable (at (x, y + 2, z))] ++ [(x, y + dy, z) | dy <- [-1, 1], ladder p, ladder (x, y + dy, z)]
          go seen [] = seen
          go seen (p : rest) = let fresh = filter (\q -> q `Set.member` allowed && q `Set.notMember` seen) (neighbors p) in go (foldr Set.insert seen fresh) (rest ++ fresh)
          reached = go (Set.singleton (2, 1, 2)) [(2, 1, 2)]
      assert ("Landmark surfaces connect to their collars: " ++ show (L.kind lm, Set.size allowed, Set.size reached, take 8 (Set.toList (allowed Set.\\ reached)))) (allowed == reached)
      assert "Landmark landings and elevated openings connect" (all (`Set.member` reached) (L.requiredPoints lm))
      mapM_ (\(x, _, z) -> assert "Catch pools preserve solid support below the water" (at (x, L.minimumY lm + 1, z) == Just B.water && B.supports (at (x, L.minimumY lm, z)))) (L.fallPoints lm)
      mapM_
        ( \(bottom@(x, y, z), top@(_, topY, _)) -> do
            assert "Ladders connect their base and upper landing" (bottom `Set.member` reached && top `Set.member` reached)
            let backing h = case at (x, h, z) >>= lookup "facing" . B.properties of
                  Just "east" -> (x - 1, h, z)
                  Just "west" -> (x + 1, h, z)
                  Just "north" -> (x, h, z + 1)
                  Just "south" -> (x, h, z - 1)
                  _ -> (x, h, z)
            assert "Ladder rungs have continuous backing and climbing clearance" (all (\h -> B.climbable (at (x, h, z)) && B.passable (at (x, h + 1, z)) && B.supports (at (backing h))) [y .. topY - 1])
        )
        (L.ladderRoutes lm)
