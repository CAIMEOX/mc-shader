module Backrooms.WorldGen.Layout
  ( Kind (..),
    kindNames,
    Layout,
    compile,
    compileReserved,
    rules,
    noiseNames,
    kind,
    crowded,
    seedBounds,
    subdivide,
    circulation,
    walls,
    openings,
  )
where

import Backrooms.WorldGen.Coordinates qualified as C
import Backrooms.WorldGen.Density
import Backrooms.WorldGen.Geometry qualified as G

data Kind = Dense | Suites | Spine | Ring | VerticalCore deriving (Eq, Show, Enum, Bounded)

kindNames :: [(Int, String)]
kindNames = [(fromEnum layout, name layout) | layout <- [minBound .. maxBound]]
  where
    name Dense = "dense"
    name Suites = "suites"
    name Spine = "spine"
    name Ring = "ring"
    name VerticalCore = "vertical_core"

-- Circulation is reserved before room subdivision. Each query point selects
-- one coherent seed rectangle; all partition decisions use that rectangle.
data Layout = Layout
  { rules :: [(String, Density)],
    noiseNames :: [String],
    kind :: Density,
    crowded :: Density,
    seedBounds :: G.Bounds,
    subdivide :: Density,
    circulation :: Density,
    walls :: Density,
    openings :: Density
  }

compile :: C.Region -> Layout
compile region = compileReserved region (Constant 0) (G.Bounds (Constant 0) (Constant 1) (Constant 0) (Constant 1))

compileReserved :: C.Region -> Density -> G.Bounds -> Layout
compileReserved region reserved reservedBounds = Layout definitions names style dense seeds enabled route wall doors
  where
    c = Constant
    x = C.x region
    z = C.z region
    end = c (fromIntegral (C.size region))
    middle = end .*. c 0.5
    ref key = Ref ("layout/" ++ key)
    names = concatMap (noiseDependencies . snd) definitions
    roll key = octile (Cache (C.noiseAt region ("layout/" ++ key) middle middle))
    style = ref "kind"
    chosen layout = let index = fromIntegral (fromEnum layout) in band style index (index + 1)
    dense = chosen Dense
    isSpine = chosen Spine
    isRing = chosen Ring
    isCore = chosen VerticalCore
    slots = concat [replicate weight (fromIntegral (fromEnum layout)) | (layout, weight) <- [(Dense, 3), (Suites, 2), (Spine, 2), (Ring, 1)]]
    whole = G.Bounds (c 0) end (c 0) end

    north = ref "north"
    south = ref "south"
    cross = ref "cross"
    above = less z cross
    below = inverse (less z (cross .+. c 3))
    arm = select above north south
    side = selectBounds (less x arm) (G.Bounds (c 0) arm (c 0) end) (G.Bounds (arm .+. c 3) end (c 0) end)
    wing = side {G.loZ = select above (c 0) (cross .+. c 3), G.hiZ = select above cross end}
    spineRoute = union [between z cross (cross .+. c 3), intersection [union [above, below], between x arm (arm .+. c 3)]]
    spineStrip = selectBounds (between z cross (cross .+. c 3)) (G.Bounds (c 0) end cross (cross .+. c 3)) (G.Bounds arm (arm .+. c 3) (G.loZ wing) (G.hiZ wing))
    spineSeeds = selectBounds spineRoute spineStrip wing
    spineWalls = intersection [inverse spineRoute, enclosure region wing]
    spineDoors = ports region wing

    ix = ref "inset_x"
    iz = ref "inset_z"
    outer = G.Bounds ix (end .-. ix) iz (end .-. iz)
    core = G.Bounds (ix .+. c 4) (end .-. ix .-. c 4) (iz .+. c 4) (end .-. iz .-. c 4)
    insideOuter = contains region outer
    insideCore = contains region core
    ringRoute = intersection [insideOuter, inverse insideCore]
    exterior =
      selectBounds
        (less z iz)
        (G.Bounds (c 0) end (c 0) iz)
        ( selectBounds
            (inverse (less z (G.hiZ outer)))
            (G.Bounds (c 0) end (G.hiZ outer) end)
            (selectBounds (less x ix) (G.Bounds (c 0) ix iz (G.hiZ outer)) (G.Bounds (G.hiX outer) end iz (G.hiZ outer)))
        )
    ringStrip =
      selectBounds
        (less z (G.loZ core))
        (outer {G.hiZ = G.loZ core})
        ( selectBounds
            (inverse (less z (G.hiZ core)))
            (outer {G.loZ = G.hiZ core})
            (selectBounds (less x (G.loX core)) (G.Bounds ix (G.loX core) (G.loZ core) (G.hiZ core)) (G.Bounds (G.hiX core) (G.hiX outer) (G.loZ core) (G.hiZ core)))
        )
    ringSeeds = selectBounds insideCore core (selectBounds ringRoute ringStrip exterior)
    ringWalls = union [intersection [inverse ringRoute, enclosure region ringSeeds], perimeter region outer]
    ringDoors = union [ports region outer, ports region core]

    envelope = G.Bounds (G.loX reservedBounds .-. c 3) (G.hiX reservedBounds .+. c 3) (G.loZ reservedBounds .-. c 3) (G.hiZ reservedBounds .+. c 3)
    coreZone = contains region envelope
    coreExterior =
      selectBounds
        (less z (G.loZ envelope))
        (G.Bounds (c 0) end (c 0) (G.loZ envelope))
        ( selectBounds
            (inverse (less z (G.hiZ envelope)))
            (G.Bounds (c 0) end (G.hiZ envelope) end)
            (selectBounds (less x (G.loX envelope)) (G.Bounds (c 0) (G.loX envelope) (G.loZ envelope) (G.hiZ envelope)) (G.Bounds (G.hiX envelope) end (G.loZ envelope) (G.hiZ envelope)))
        )
    coreStrip =
      selectBounds
        (less z (G.loZ reservedBounds))
        (envelope {G.hiZ = G.loZ reservedBounds})
        ( selectBounds
            (inverse (less z (G.hiZ reservedBounds)))
            (envelope {G.loZ = G.hiZ reservedBounds})
            (selectBounds (less x (G.loX reservedBounds)) (G.Bounds (G.loX envelope) (G.loX reservedBounds) (G.loZ reservedBounds) (G.hiZ reservedBounds)) (G.Bounds (G.hiX reservedBounds) (G.hiX envelope) (G.loZ reservedBounds) (G.hiZ reservedBounds)))
        )
    coreSeeds = selectBounds (contains region reservedBounds) reservedBounds (selectBounds coreZone coreStrip coreExterior)
    seeds = selectBounds isCore coreSeeds (selectBounds isSpine spineSeeds (selectBounds isRing ringSeeds whole))
    route = ref "circulation"
    enabled = inverse (union [route, intersection [isRing, insideCore]])
    wall = ref "wall"
    doors = ref "openings"
    definitions =
      [ ("layout/kind", select reserved (c (fromIntegral (fromEnum VerticalCore))) (pick slots (quantileChoice (length slots) (Cache (C.noiseAt region "layout/kind" middle middle))))),
        ("layout/north", Floor (end .*. c 0.29) .+. roll "north"),
        ("layout/south", Floor (end .*. c 0.54) .+. roll "south"),
        ("layout/cross", Floor (end .*. c 0.38) .+. roll "cross"),
        ("layout/inset_x", Floor (end .*. c 0.17) .+. Floor (roll "inset_x" .*. c 0.5)),
        ("layout/inset_z", Floor (end .*. c 0.17) .+. Floor (roll "inset_z" .*. c 0.5)),
        ("layout/circulation", union [intersection [isCore, coreZone], intersection [isSpine, spineRoute], intersection [isRing, ringRoute]]),
        ("layout/wall", union [intersection [isCore, inverse coreZone, enclosure region coreExterior], intersection [isSpine, spineWalls], intersection [isRing, ringWalls]]),
        ("layout/openings", union [intersection [isCore, ports region envelope], intersection [isSpine, spineDoors], intersection [isRing, ringDoors]])
      ]

selectBounds :: Density -> G.Bounds -> G.Bounds -> G.Bounds
selectBounds mask a b = G.Bounds (choose G.loX) (choose G.hiX) (choose G.loZ) (choose G.hiZ)
  where
    choose field = select mask (field a) (field b)

contains :: C.Region -> G.Bounds -> Density
contains region b = intersection [between (C.x region) (G.loX b) (G.hiX b), between (C.z region) (G.loZ b) (G.hiZ b)]

perimeter :: C.Region -> G.Bounds -> Density
perimeter region b = intersection [contains region b, union [near (C.x region) (G.loX b) 0, near (C.x region) (G.hiX b .-. Constant 1) 0, near (C.z region) (G.loZ b) 0, near (C.z region) (G.hiZ b .-. Constant 1) 0]]

-- Region boundaries have a separate shared-edge connection rule.
enclosure :: C.Region -> G.Bounds -> Density
enclosure region b = intersection [perimeter region b, between (C.x region) (Constant 1) end, between (C.z region) (Constant 1) end]
  where
    end = Constant (fromIntegral (C.size region - 1))

ports :: C.Region -> G.Bounds -> Density
ports region b = union [intersection [near (C.x region) (Floor cx) 1, union [near (C.z region) (G.loZ b) 2, near (C.z region) (G.hiZ b .-. Constant 1) 2]], intersection [near (C.z region) (Floor cz) 1, union [near (C.x region) (G.loX b) 2, near (C.x region) (G.hiX b .-. Constant 1) 2]]]
  where
    (cx, cz) = G.centre b
