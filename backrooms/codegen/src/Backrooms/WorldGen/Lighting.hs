module Backrooms.WorldGen.Lighting (Lighting, compile, rules, roof, lamps) where

import Backrooms.WorldGen.Density
import Backrooms.WorldGen.Geometry qualified as G

data Lighting = Lighting
  { rules :: [(String, Density)],
    roof :: Density,
    lamps :: Density
  }

compile :: G.RoomFrame -> Density -> Density -> Lighting
compile room kind props =
  Lighting
    [ ("ceiling", ceilingHeight room kind),
      ("roof", roofMask),
      ("lamps", intersection [near (G.elevation room) (Ref "ceiling") 0, select narrow (corridorLights room) (select extended (extendedLights room) (smallLights room kind)), inverse props])
    ]
    roofMask
    (Ref "lamps")
  where
    roofMask = inverse (less (G.elevation room) (Ref "ceiling"))
    extended = union [band (G.width room .*. G.depth room) 180 2500, band (G.lengthU room) 18 49]
    narrow = band (G.lengthV room) 0 5

ceilingHeight :: G.RoomFrame -> Density -> Density
ceilingHeight room kind = select (band (G.width room .*. G.depth room) 180 2500) (pick [4, 4, 5, 5, 6, 4, 5, 4] kind) (select compact (pick [2, 3, 3, 2, 3, 3, 2, 3] kind) (pick [3, 3, 3, 4, 4, 3, 4, 3] kind))
  where
    compact = intersection [band (G.lengthV room) 5 9, band (G.width room .*. G.depth room) 0 120]

corridorLights :: G.RoomFrame -> Density
corridorLights room = intersection [between (G.u room) (Constant 2) (G.lengthU room .-. Constant 1), band (repeatAt (G.u room .-. Constant 2) 7) 0 3, near (G.v room) (Floor (G.lengthV room .*. Constant 0.5)) 0]

lampsAt :: G.RoomFrame -> Density -> Density -> Density
lampsAt room a b = intersection [near (G.u room) a 1, near (G.v room) b 0]

smallLights :: G.RoomFrame -> Density -> Density
smallLights room kind = select (band kind 0 4) (lampsAt room midU midV) (union [lampsAt room thirdU (select wide quarterV midV), lampsAt room lastU (select wide lastV midV)])
  where
    midU = Floor (G.lengthU room .*. Constant 0.5)
    midV = Floor (G.lengthV room .*. Constant 0.5)
    thirdU = Floor (G.lengthU room .*. Constant (1 / 3))
    lastU = Floor (G.lengthU room .*. Constant (2 / 3))
    quarterV = Floor (G.lengthV room .*. Constant 0.25)
    lastV = Floor (G.lengthV room .*. Constant 0.75)
    wide = band (G.lengthV room) 15 49

extendedLights :: G.RoomFrame -> Density
extendedLights room =
  intersection
    [ between (G.u room) (Constant 3) (G.lengthU room .-. Constant 2),
      between (G.v room) (Constant 3) (G.lengthV room .-. Constant 2),
      band (repeatAt (G.u room .-. startU) 8) 0 3,
      band (repeatAt (G.v room .-. startV) 8) 0 1
    ]
  where
    startU = Constant 3 .+. Floor (repeatAt (G.lengthU room .-. Constant 8) 8 .*. Constant 0.5)
    startV = Constant 3 .+. Floor (repeatAt (G.lengthV room .-. Constant 6) 8 .*. Constant 0.5)
