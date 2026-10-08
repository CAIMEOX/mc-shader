module Backrooms.WorldGen.Runtime
  ( regionSize,
    roomBounds,
    rules,
    noiseNames,
    sample,
    walkable,
    connected,
    validate,
    furnitureKinds,
    layoutKinds,
    materialMasks,
    sampleBlock,
    walkableAt,
  )
where

import Backrooms.WorldGen.Block qualified as B
import Backrooms.WorldGen.Coordinates qualified as C
import Backrooms.WorldGen.Density
import Backrooms.WorldGen.Floors qualified as Floors
import Backrooms.WorldGen.Furniture qualified as F
import Backrooms.WorldGen.Geometry qualified as G
import Backrooms.WorldGen.Layout qualified as Layout
import Backrooms.WorldGen.Lighting qualified as L
import Backrooms.WorldGen.Materials (Surface (..), surfaceBlock)
import Backrooms.WorldGen.Navigation qualified as N
import Backrooms.WorldGen.Partition qualified as P
import Backrooms.WorldGen.Vertical qualified as V
import Data.List (nub)
import Data.Sequence qualified as Q
import Data.Set qualified as S

regionSize :: Int
regionSize = 48

coordinates :: C.Region
coordinates = C.region regionSize 128

floors :: Floors.Floors
floors = Floors.compile (C.y coordinates)

vertical :: V.Vertical
vertical = V.compile coordinates

roomBounds :: G.Bounds
roomBounds = G.Bounds (Ref "room/lo_x") (Ref "room/hi_x") (Ref "room/lo_z") (Ref "room/hi_z")

furnitureKinds, layoutKinds :: [(Int, String)]
furnitureKinds = F.familyNames
layoutKinds = Layout.kindNames

roomMaterials :: [(String, String)]
roomMaterials = [("lamps", surfaceBlock Luminaire)] ++ F.materialMasks ++ [("roof", surfaceBlock Ceiling), ("wallpaper", surfaceBlock Wallpaper)]

materialMasks :: [(String, B.BlockState)]
materialMasks = V.materialMasks vertical ++ [("material/" ++ key, B.plain block) | (key, block) <- roomMaterials] ++ [("material/carpet", B.plain (surfaceBlock Carpet))]

noiseNames :: [String]
noiseNames = nub (concatMap (noiseDependencies . snd) rules)

-- Each storey has its own XZ-cached planning graph. Only the final scene
-- selection depends on the queried Y; all room choices remain seed-driven.
scene :: Int -> [(String, Density)]
scene floorY =
  C.rules frame
    ++ Layout.rules layout
    ++ P.rules plan
    ++ G.boundsRules "room" (P.leaves plan)
    ++ boundaryRules frame plan layout elevation entry
    ++ [ ("light_kind", octile (Cache (noise "height"))),
         ("furnish_x", band (noise "furnish_x") 0 1000),
         ("furnish_z", band (noise "furnish_z") 0 1000),
         ("prop_kind", F.chooseFamily (Cache (noise "props")))
       ]
    ++ F.rules furniture
    ++ L.rules lights
    ++ [("material/" ++ key, intersection [interior, if key == "wallpaper" then Constant 1 else Ref key]) | (key, _) <- roomMaterials]
    ++ [ ("material/carpet", intersection [inverse (V.owned vertical), near elevation (Constant (-1)) 0]),
         ("solid", density (union [near elevation (Constant (-1)) 0, L.roof lights, Ref "wall", F.solids furniture]))
       ]
  where
    frame = C.onPlane (Constant (fromIntegral ((floorY - Floors.entranceY) `div` Floors.pitch * 64))) coordinates
    elevation = C.y frame .-. Constant (fromIntegral floorY)
    layout = Layout.compileReserved frame (V.active vertical) (V.localBounds vertical)
    plan = P.compileWithin frame (P.Specification "partition" 8 (Layout.seedBounds layout) (Layout.subdivide layout) (Layout.crowded layout))
    room = G.roomFrame (Constant (fromIntegral floorY)) frame (P.leaves plan) (Ref "furnish_x") (Ref "furnish_z")
    furniture = F.compile room (Ref "prop_kind") (union [Ref "openings", Layout.circulation layout]) entry
    lights = L.compile room (Ref "light_kind") (F.solids furniture)
    noise = snd . P.leafNoise plan
    entry = if floorY == Floors.entranceY then intersection [band (Gradient X (-5) 6 (-5) 6 False) (-4) 5, band (Gradient Z (-5) 6 (-5) 6 False) (-4) 5] else Constant 0
    interior = intersection [inverse (V.owned vertical), inverse (less elevation (Constant 0))]

scope :: Int -> String
scope floorY = "floor/" ++ show floorY ++ "/"

qualify :: Int -> [(String, Density)] -> [(String, Density)]
qualify floorY definitions = [(scope floorY ++ key, mapReferences rename value) | (key, value) <- definitions]
  where
    names = S.fromList (map fst definitions)
    rename key = if key `S.member` names then scope floorY ++ key else key

selectFloor :: String -> Density
selectFloor key = foldr (\floorY rest -> Range (C.y coordinates) (fromIntegral (floorY - 1)) (fromIntegral (floorY + Floors.pitch - 1)) (Ref (scope floorY ++ key)) rest) (Constant 0) Floors.walkLevels

rules :: [(String, Density)]
rules =
  map (\(key, value) -> (key, Cache value)) $
    [(key, value) | (key, value) <- C.rules coordinates, key `elem` ["coordinate_x", "coordinate_z", "y"]]
      ++ Floors.rules floors
      ++ V.rules vertical
      ++ concat [qualify floorY (scene floorY) | floorY <- Floors.walkLevels]
      ++ [(key, selectFloor key) | (key, _) <- scene Floors.entranceY, key `notElem` ["coordinate_x", "coordinate_z", "y", "solid"]]
      ++ [("solid", solid)]

density :: Density -> Density
density mask = select mask (Constant 1) (Constant (-1))

solid :: Density
solid = select (V.owned vertical) (density (V.solid vertical)) (select (Floors.active floors) (selectFloor "solid") (density (less (C.y coordinates) (Constant (fromIntegral (Floors.lowestY - 1))))))

boundaryRules :: C.Region -> P.Plan -> Layout.Layout -> Density -> Density -> [(String, Density)]
boundaryRules frame plan layout elevation entry =
  [("openings", openings), ("wall", intersection [union (border : Layout.walls layout : P.walls plan), inverse (intersection [openings, band elevation 0 2])])]
  where
    border = union [near (C.x frame) (Constant 0) 0, near (C.z frame) (Constant 0) 0]
    rawX = C.rawX frame
    rawZ = C.rawZ frame
    spanXZ = fromIntegral (C.size frame)
    midpoint = Constant (spanXZ * 0.5)
    gateX = NoiseAt "gate_x" (nearest rawX .-. rawX) (C.noisePlane frame) (midpoint .-. rawZ)
    gateZ = NoiseAt "gate_z" (midpoint .-. rawX) (C.noisePlane frame) (nearest rawZ .-. rawZ)
    nearest local = select (band local 0 (spanXZ * 0.5)) (Constant 0) (Constant spanXZ)
    openings = union (entry : Layout.openings layout : boundaryOpen frame rawX rawZ gateX : boundaryOpen frame rawZ rawX gateZ : P.openings plan)

boundaryOpen :: C.Region -> Density -> Density -> Density -> Density
boundaryOpen region across along noise =
  intersection
    [ union [band across 0 3, band across (spanXZ - 2) spanXZ],
      union
        [ near along (Constant (spanXZ * 0.5) .+. choice 11 noise .-. Constant 5) 1,
          near along (Constant 8 .+. octile noise) 3,
          near along (Constant (spanXZ - 8) .-. octile noise) 3
        ]
    ]
  where
    spanXZ = fromIntegral (C.size region)

sample :: NoiseSource -> (Double, Double, Double) -> String -> Double
sample source point key = evaluator source point (Ref key)

evaluator :: NoiseSource -> (Double, Double, Double) -> Density -> Double
evaluator = evaluate rules

sampleBlock :: NoiseSource -> (Int, Int, Int) -> B.BlockState
sampleBlock source (x, y, z) = case map (evaluator source (fromIntegral x, fromIntegral y, fromIntegral z)) (Ref "solid" : map (Ref . fst) materialMasks) of
  occupied : masks | occupied > 0 -> case [state | ((_, state), mask) <- zip materialMasks masks, mask > 0] of
    state : _ -> state
    [] -> B.plain "minecraft:stone"
  _ -> B.air

walkable :: NoiseSource -> (Int, Int) -> Bool
walkable source (x, z) = walkableAt source (x, Floors.entranceY, z)

walkableAt :: NoiseSource -> (Int, Int, Int) -> Bool
walkableAt source = N.navigable (sampleBlock source)

connected :: S.Set (Int, Int) -> (Int, Int) -> S.Set (Int, Int)
connected allowed start = go (S.singleton start) (Q.singleton start)
  where
    go seen queue = case Q.viewl queue of
      Q.EmptyL -> seen
      (x, z) Q.:< rest ->
        let fresh = filter (\p -> p `S.member` allowed && p `S.notMember` seen) [(x - 1, z), (x + 1, z), (x, z - 1), (x, z + 1)]
         in go (foldr S.insert seen fresh) (rest Q.>< Q.fromList fresh)

validate :: Either String ()
validate = validateRegistry rules
