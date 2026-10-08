module Backrooms.WorldGen.Geometry
  ( Bounds (..),
    boundsValues,
    boundsRules,
    dimensions,
    centre,
    RoomFrame (..),
    roomFrame,
    rectangle,
  )
where

import Backrooms.WorldGen.Coordinates qualified as C
import Backrooms.WorldGen.Density

data Bounds = Bounds
  { loX :: Density,
    hiX :: Density,
    loZ :: Density,
    hiZ :: Density
  }
  deriving (Eq, Show)

boundsValues :: Bounds -> [Density]
boundsValues bounds = [loX bounds, hiX bounds, loZ bounds, hiZ bounds]

boundsRules :: String -> Bounds -> [(String, Density)]
boundsRules namespace = zip (map ((namespace ++ "/") ++) ["lo_x", "hi_x", "lo_z", "hi_z"]) . boundsValues

dimensions :: Bounds -> (Density, Density)
dimensions bounds = (hiX bounds .-. loX bounds, hiZ bounds .-. loZ bounds)

centre :: Bounds -> (Density, Density)
centre bounds = ((loX bounds .+. hiX bounds) .*. Constant 0.5, (loZ bounds .+. hiZ bounds) .*. Constant 0.5)

-- Furniture and lights share an oriented, mirrored frame for each leaf room.
data RoomFrame = RoomFrame
  { width :: Density,
    depth :: Density,
    dx :: Density,
    dz :: Density,
    u :: Density,
    v :: Density,
    lengthU :: Density,
    lengthV :: Density,
    elevation :: Density
  }
  deriving (Eq, Show)

roomFrame :: Density -> C.Region -> Bounds -> Density -> Density -> RoomFrame
roomFrame floorY region bounds mirrorX mirrorZ = RoomFrame w d offsetX offsetZ along across long short (C.y region .-. floorY)
  where
    (w, d) = dimensions bounds
    offsetX = select mirrorX (hiX bounds .-. C.x region) (C.x region .-. loX bounds)
    offsetZ = select mirrorZ (hiZ bounds .-. C.z region) (C.z region .-. loZ bounds)
    longX = inverse (less w d)
    along = select longX offsetX offsetZ
    across = select longX offsetZ offsetX
    long = Binary Max w d
    short = Binary Min w d

rectangle :: RoomFrame -> Density -> Density -> Density -> Density -> Density
rectangle room a b spanU spanV = intersection [between (u room) a (a .+. spanU), between (v room) b (b .+. spanV)]
