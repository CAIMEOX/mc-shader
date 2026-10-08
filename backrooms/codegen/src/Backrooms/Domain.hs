module Backrooms.Domain where

import Data.List (minimumBy)
import Data.Maybe (mapMaybe)
import Data.Ord (comparing)

type V3 = (Double, Double, Double)

data Material = Wall | Floor | Ceiling | Column | Lamp | Mirror | PortalSurface | Native deriving (Eq, Ord, Show, Enum, Bounded)

materialId :: Material -> Int
materialId = (+ 1) . fromEnum

data Box = Box {lower :: V3, upper :: V3, material :: Material} deriving (Eq, Show)

data RoomId = Corridor | Hall deriving (Eq, Ord, Show, Enum)

data Room = Room {roomName :: String, origin :: V3, width :: Int, height :: Int, depth :: Int, boxes :: [Box]} deriving (Eq, Show)

data Portal = Portal {sourceX :: Double, targetX :: Double, centerZ :: Double, halfWidth :: Double, portalHeight :: Double} deriving (Eq, Show)

data Ray = Ray {rayRoom :: RoomId, rayOrigin :: V3, rayDirection :: V3} deriving (Eq, Show)

data Hit = Hit {hitDistance :: Double, hitMaterial :: Material, hitRoom :: RoomId} deriving (Eq, Show)

period, spanLength, baseY :: Int
period = 24
spanLength = 48
baseY = 64

portal :: Portal
portal = Portal 4 (-12) 12 1 3

room :: RoomId -> Room
room Corridor =
  Room
    "corridor"
    (0, fromIntegral baseY, 0)
    8
    5
    period
    [ Box (-5, -1, 0) (5, 0, 24) Floor,
      Box (-5, 5, 0) (5, 6, 24) Ceiling,
      Box (-5, 0, 0) (-4, 5, 24) Wall,
      Box (4, 0, 0) (5, 5, 11) Wall,
      Box (4, 0, 13) (5, 5, 24) Wall,
      Box (4, 3, 11) (5, 5, 13) Wall
    ]
room Hall =
  Room
    "hall"
    (128, fromIntegral baseY, 0)
    24
    7
    36
    ( [ Box (-13, -1, -19) (13, 0, 19) Floor,
        Box (-13, 7, -19) (13, 8, 19) Ceiling,
        Box (12, 0, -19) (13, 7, 19) Wall,
        Box (-13, 0, -19) (13, 7, -18) Wall,
        Box (-13, 0, 18) (13, 7, 19) Wall,
        Box (-13, 0, -18) (-12, 7, -1) Wall,
        Box (-13, 0, 1) (-12, 7, 18) Wall,
        Box (-13, 3, -1) (-12, 7, 1) Wall
      ]
        ++ [Box (x, 0, z) (x + 1, 7, z + 1) Column | x <- [-6, 5], z <- [-8, 7]]
    )

components :: V3 -> [Double]
components (x, y, z) = [x, y, z]

add :: V3 -> V3 -> V3
add (x, y, z) (a, b, c) = (x + a, y + b, z + c)

multiply :: Double -> V3 -> V3
multiply k (x, y, z) = (k * x, k * y, k * z)

mapPoint :: Int -> V3 -> V3
mapPoint cell p = add p (targetX portal - sourceX portal, 0, -centerZ portal - fromIntegral (cell * period))

reversePoint :: Int -> V3 -> V3
reversePoint cell p = add p (sourceX portal - targetX portal, 0, centerZ portal + fromIntegral (cell * period))

contains :: Box -> V3 -> Bool
contains b p = and [a <= x && x < c | (a, c, x) <- zip3 (components (lower b)) (components (upper b)) (components p)]

intersection :: Box -> V3 -> V3 -> Maybe Double
intersection box o d = do
  intervals <- sequence [slab a b x dx | (a, b, x, dx) <- zip4 (components (lower box)) (components (upper box)) (components o) (components d)]
  let near = maximum (map fst intervals); far = minimum (map snd intervals); t = if near > 1e-5 then near else far
  if far >= near && t > 1e-5 then Just t else Nothing
  where
    slab a b x dx
      | abs dx < 1e-10 = if x < a || x > b then Nothing else Just (-1 / 0, 1 / 0)
      | otherwise = let u = (a - x) / dx; v = (b - x) / dx in Just (min u v, max u v)
    zip4 (a : as) (b : bs) (c : cs) (e : es) = (a, b, c, e) : zip4 as bs cs es
    zip4 _ _ _ _ = []

collisionVolumes :: RoomId -> [Box]
collisionVolumes rid =
  [ Box (add offset (lower b)) (add offset (upper b)) (material b)
  | cell <- if rid == Corridor then [-1, 0, 1, 2] else [0],
    b <- boxes (room rid) ++ lights rid,
    let offset = add (origin (room rid)) (0, 0, fromIntegral (cell * period))
  ]

closest :: [Hit] -> Maybe Hit
closest [] = Nothing
closest hs = Just (minimumBy (comparing hitDistance) hs)

bodyHits :: RoomId -> V3 -> V3 -> [Hit]
bodyHits rid o d =
  [ Hit t (surfaceMaterial rid (material b) (add localOrigin (multiply t d))) rid
  | cell <- if rid == Corridor then [-4 .. 11] else [0],
    b <- boxes (room rid),
    let localOrigin = add o (0, 0, negate (fromIntegral (cell * period))),
    t <- mapMaybe (\p -> intersection b p d) [localOrigin]
  ]

lights :: RoomId -> [Box]
lights Corridor = [Box (0, 5, z) (1, 6, z + 2) Lamp | z <- [2, 8, 14, 20]]
lights Hall = [Box (x, 7, z) (x + 1, 8, z + 2) Lamp | x <- [-6, 0, 6], z <- [-12, -6, 0, 6, 12]]

surfaceMaterial :: RoomId -> Material -> V3 -> Material
surfaceMaterial rid Ceiling (x, _, z) = if any (`contains` (x, fromIntegral (height (room rid)), z)) (lights rid) then Lamp else Ceiling
surfaceMaterial _ m _ = m

referenceHit :: Ray -> Maybe Hit
referenceHit (Ray rid o@(x, _, _) d@(dx, _, _)) = closest (bodyHits rid o d ++ portalHits)
  where
    plane = if rid == Corridor then sourceX portal else targetX portal
    directionFits = if rid == Corridor then dx > 1e-6 else dx < -1e-6
    t = (plane - x) / dx
    p@(_, y, z) = add o (multiply t d)
    cell = if rid == Corridor then floor (z / fromIntegral period) else 0
    anchor = if rid == Corridor then centerZ portal + fromIntegral (cell * period) else 0
    target = if rid == Corridor then Hall else Corridor
    mapped = if rid == Corridor then mapPoint cell p else reversePoint 0 p
    portalHits =
      [ h {hitDistance = t + hitDistance h}
      | directionFits,
        t > 0,
        y >= 0,
        y < portalHeight portal,
        abs (z - anchor) < halfWidth portal,
        h <- maybe [] pure (closest (bodyHits target mapped d))
      ]

rayFixtures :: [Ray]
rayFixtures =
  [ Ray Corridor (0, 1.62, 3) (0, -1, 0),
    Ray Corridor (0, 1.62, 3) (0, 1, 0),
    Ray Corridor (0, 1.62, 3) (1, 0, 0),
    Ray Corridor (0, 1.62, 12) (1, 0, 0),
    Ray Hall (-10, 1.62, 0) (1, 0, 0),
    Ray Hall (0, 1.62, 0) (0, 0, 1),
    Ray Hall (-5.5, 1.62, 0) (0, 0, -1)
  ]

blockName :: Material -> String
blockName Wall = "minecraft:bamboo_planks"
blockName Floor = "minecraft:brown_wool"
blockName Ceiling = "minecraft:smooth_stone"
blockName Column = "minecraft:smooth_sandstone"
blockName Lamp = "minecraft:ochre_froglight"
blockName _ = "minecraft:air"
