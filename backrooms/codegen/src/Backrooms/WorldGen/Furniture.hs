module Backrooms.WorldGen.Furniture
  ( Family (..),
    familyNames,
    chooseFamily,
    materialMasks,
    Furnishings,
    compile,
    rules,
    solids,
  )
where

import Backrooms.WorldGen.Density
import Backrooms.WorldGen.Geometry qualified as G

data Family = Alcoves | Columns | Archives | Meeting | Gallery | Maintenance | Screens | Lounge | Carrels
  deriving (Eq, Show, Enum, Bounded)

familyNames :: [(Int, String)]
familyNames = [(fromEnum family, familyName family) | family <- [minBound .. maxBound]]

familyName :: Family -> String
familyName family = case family of
  Alcoves -> "alcoves"
  Columns -> "columns"
  Archives -> "archives"
  Meeting -> "meeting"
  Gallery -> "gallery"
  Maintenance -> "maintenance"
  Screens -> "screens"
  Lounge -> "lounge"
  Carrels -> "carrels"

chooseFamily :: Density -> Density
chooseFamily = quantileChoice (length familyNames)

data Finish = Wallpaper | Wood | Shelves | Metal | Soft deriving (Eq, Enum, Bounded)

-- A component owns its geometry and finish; lowering collects finish masks.
data Part = Part Finish Density

finish :: Finish -> (String, String)
finish material = case material of
  Wallpaper -> ("wallpaper", "minecraft:end_stone")
  Wood -> ("wood", "minecraft:oak_planks")
  Shelves -> ("shelves", "minecraft:bookshelf")
  Metal -> ("metal", "minecraft:iron_block")
  Soft -> ("soft", "minecraft:brown_wool")

materialMasks :: [(String, String)]
materialMasks = map finish [Wood .. maxBound]

data Furnishings = Furnishings
  { rules :: [(String, Density)],
    solids :: Density
  }

compile :: G.RoomFrame -> Density -> Density -> Density -> Furnishings
compile room kind openings entry =
  Furnishings
    ( [ ("furniture", union [shape | Part _ shape <- parts]),
        ("props", union [returns room articulated openings entry, Ref "furniture"])
      ]
        ++ [(fst (finish material), union [shape | Part paint shape <- parts, paint == material]) | material <- [Wood .. maxBound]]
    )
    (Ref "props")
  where
    parts = [Part material (intersection [selectFamily kind family shape, clearance]) | family <- [minBound .. maxBound], Part material shape <- partsFor room family]
    articulated = articulation room kind
    clearance = furnitureClearance room articulated openings entry

partsFor :: G.RoomFrame -> Family -> [Part]
partsFor room family = case family of
  Meeting -> [Part Wood shape]
  Archives -> [Part Shelves shape]
  Maintenance -> [Part Metal shape]
  Lounge -> [Part Soft shape, Part Wood (coffeeTable room)]
  Carrels -> [Part Wallpaper shape, Part Wood (carrelDesks room)]
  _ -> [Part Wallpaper shape]
  where
    shape = patternFor room family

selectFamily :: Density -> Family -> Density -> Density
selectFamily kind family mask = intersection [band kind index (index + 1), mask]
  where
    index = fromIntegral (fromEnum family)

patternFor :: G.RoomFrame -> Family -> Density
patternFor room family = case family of
  Alcoves -> intersection [low, union [rect (c 3) (c 3) (long .*. c 0.45) (c 1), rect (c 3) (c 3) (c 1) (short .*. c 0.55)]]
  Columns -> intersection [band (repeatAt (G.u room) 5) 0 1, band (repeatAt (G.v room) 5) 0 1]
  Archives -> intersection [low, between (G.u room) (c 3) (long .-. c 3), union [near (G.v room) (c 3) 0, near (G.v room) (short .-. c 3) 0, intersection [band short 15 49, near (G.v room) midV 0]]]
  Meeting -> intersection [band (G.elevation room) 0 1, union [rect (thirdU .-. c 1) quarterV (c 4) (c 2), rect (lastU .-. c 1) (lastV .-. c 1) (c 4) (c 2)]]
  Gallery -> union [rect (c 3) (c 3) (c 1) (midV .-. c 1), rect (long .-. c 4) (midV .-. c 1) (c 1) (short .-. midV)]
  Maintenance -> intersection [band (G.elevation room) 0 3, union [rect (c 3) (c 3) (c 3) (c 2), rect (long .-. c 6) (short .-. c 5) (c 3) (c 2)]]
  Screens -> intersection [band (G.elevation room) 0 3, union [rect thirdU (c 3) (c 1) (midV .-. c 1), rect lastU (midV .-. c 1) (c 1) (short .-. midV)]]
  Lounge -> intersection [low, rect (c 3) (c 3) (long .-. c 6) (c 1)]
  Carrels -> intersection [low, union [rect (c 3) midV (long .-. c 6) (c 1), intersection [band (repeatAt (G.u room .-. c 3) 6) 0 1, between (G.v room) (c 3) (midV .+. c 1)]]]
  where
    c = Constant
    rect = G.rectangle room
    long = G.lengthU room
    short = G.lengthV room
    low = band (G.elevation room) 0 2
    midV = Floor (short .*. c 0.5)
    thirdU = Floor (long .*. c (1 / 3))
    lastU = Floor (long .*. c (2 / 3))
    quarterV = Floor (short .*. c 0.25)
    lastV = Floor (short .*. c 0.75)

coffeeTable :: G.RoomFrame -> Density
coffeeTable room = intersection [band (G.elevation room) 0 1, G.rectangle room (midU .-. Constant 1) (midV .-. Constant 1) (Constant 3) (Constant 2)]
  where
    midU = Floor (G.lengthU room .*. Constant 0.5)
    midV = Floor (G.lengthV room .*. Constant 0.5)

carrelDesks :: G.RoomFrame -> Density
carrelDesks room = intersection [band (G.elevation room) 0 1, band (repeatAt (G.u room .-. Constant 3) 6) 2 5, near (G.v room) (Floor (G.lengthV room .*. Constant 0.5) .-. Constant 1) 0]

articulation :: G.RoomFrame -> Density -> Density
articulation room kind = union [inverse (less (G.lengthU room) (G.lengthV room .*. Constant 2.5)), intersection [band (G.width room .*. G.depth room) 180 2500, union [band kind 3 4, band kind 5 6, band kind 7 8]]]

returns :: G.RoomFrame -> Density -> Density -> Density -> Density
returns room articulated openings entry =
  intersection
    [ articulated,
      inverse openings,
      inverse entry,
      between (G.v room) (Constant 1) (G.lengthV room),
      union [rect thirdU (Constant 1) (Constant 1) midV, rect lastU midV (Constant 1) (G.lengthV room .-. midV)]
    ]
  where
    rect = G.rectangle room
    thirdU = Floor (G.lengthU room .*. Constant (1 / 3))
    lastU = Floor (G.lengthU room .*. Constant (2 / 3))
    midV = Floor (G.lengthV room .*. Constant 0.5)

furnitureClearance :: G.RoomFrame -> Density -> Density -> Density -> Density
furnitureClearance room articulated openings entry =
  intersection
    [ inverse openings,
      inverse entry,
      between (G.dx room) (Constant 3) (G.width room .-. Constant 2),
      between (G.dz room) (Constant 3) (G.depth room .-. Constant 2),
      inverse (intersection [articulated, union [near (G.u room) thirdU 1, near (G.u room) lastU 1]])
    ]
  where
    thirdU = Floor (G.lengthU room .*. Constant (1 / 3))
    lastU = Floor (G.lengthU room .*. Constant (2 / 3))
