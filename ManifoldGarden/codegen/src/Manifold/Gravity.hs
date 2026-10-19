module Manifold.Gravity where

import Data.List (elemIndex, permutations)
import Data.Maybe (fromJust)

type V = (Int, Int, Int)

type Frame = (V, V, V)

unit, period, beamRadius, bodyRadius, bodyHeight, acceleration, terminalSpeed :: Int
unit = 4096
period = 32 * unit
beamRadius = 6144
bodyRadius = 1229
bodyHeight = 3686
acceleration = 246
terminalSpeed = 8192

identity :: Frame
identity = ((1, 0, 0), (0, 1, 0), (0, 0, 1))

axes :: [V]
axes = [(1, 0, 0), (0, 1, 0), (0, 0, 1)]

downDirections :: [V]
downDirections = [(0, -1, 0), (0, 1, 0), (-1, 0, 0), (1, 0, 0), (0, 0, -1), (0, 0, 1)]

add, sub, cross :: V -> V -> V
add (a, b, c) (x, y, z) = (a + x, b + y, c + z)
sub (a, b, c) (x, y, z) = (a - x, b - y, c - z)
cross (a, b, c) (x, y, z) = (b * z - c * y, c * x - a * z, a * y - b * x)

scale :: Int -> V -> V
scale n (x, y, z) = (n * x, n * y, n * z)

dot :: V -> V -> Int
dot (a, b, c) (x, y, z) = a * x + b * y + c * z

apply :: Frame -> V -> V
apply (a, b, c) (x, y, z) = add (scale x a) (add (scale y b) (scale z c))

frames :: [Frame]
frames =
  identity
    : filter
      (/= identity)
      [ (a, b, c)
      | [x, y, z] <- permutations axes,
        i <- [-1, 1],
        j <- [-1, 1],
        k <- [-1, 1],
        let a = scale i x; b = scale j y; c = scale k z,
        dot a (cross b c) == 1
      ]

gravity :: Frame -> V
gravity f = apply f (0, -1, 0)

-- Quarter turns parallel-transport the whole frame. Opposite gravity turns
-- around the previous local right axis, giving a deterministic half turn.
turnFrame :: Frame -> V -> Frame
turnFrame f@(right, _, _) target =
  let old = gravity f
      axis = cross old target
      rotate v
        | old == target = v
        | dot old target == -1 = add (scale (2 * dot right v) right) (scale (-1) v)
        | otherwise = add (cross axis v) (scale (dot axis v) axis)
      (a, b, c) = f
   in (rotate a, rotate b, rotate c)

frameIndex :: Frame -> Int
frameIndex = fromJust . (`elemIndex` frames)

components :: V -> [Int]
components (x, y, z) = [x, y, z]

vector :: [Int] -> V
vector [x, y, z] = (x, y, z)
vector _ = error "A spatial vector has three components"

component :: Int -> V -> Int
component i = (!! i) . components

replace :: Int -> Int -> V -> V
replace i value v = vector [if j == i then value else x | (j, x) <- zip [0 ..] (components v)]

wrap :: V -> V
wrap = vector . map (`mod` period) . components

-- Each beam is infinite along one axis and periodic along the other two.
-- These same three primitives drive the renderer and swept collision commands.
data Beam = Beam {freeAxis :: Int, halfWidth :: Int} deriving (Eq, Show)

beams :: [Beam]
beams = [Beam i beamRadius | i <- [0 .. 2]]

extents :: V -> V
extents g = vector [if x == 0 then bodyRadius else bodyHeight | x <- components g]

inside :: V -> V -> Bool
inside p h = any hit beams
  where
    hit (Beam free r) =
      all
        ( \i ->
            let q = component i p `mod` period; bound = r + component i h
             in q < bound || q > period - bound
        )
        [i | i <- [0 .. 2], i /= free]

data Body = Body {position :: V, velocity :: V, down :: V, grounded :: Bool} deriving (Eq, Show)

-- Axis sweeps stop at the first expanded beam boundary, so a fast body
-- cannot tunnel through a column even when its destination is empty.
moveBody :: Body -> Body
moveBody initial = foldl sweep (initial {grounded = False}) [0 .. 2]
  where
    h = extents (down initial)
    sweep body axis =
      let p = position body
          speed = component axis (velocity body)
          candidates = [clip p axis speed beam | beam <- beams, freeAxis beam /= axis]
          distance = if speed >= 0 then minimum (speed : candidates) else maximum (speed : candidates)
          hit = distance /= speed
          floorHit = hit && signum speed == component axis (down body)
       in body
            { position = wrap (replace axis (component axis p + distance) p),
              velocity = if hit then replace axis 0 (velocity body) else velocity body,
              grounded = grounded body || floorHit
            }
    clip p axis speed (Beam free r) =
      let other = 3 - free - axis
          q = component other p `mod` period
          band = r + component other h
          low = r + component axis h
          x = component axis p `mod` period
       in if q >= band && q <= period - band
            then speed
            else if speed >= 0 then min speed (period - low - x) else max speed (low - x)

fall :: Body -> Body
fall b =
  moveBody
    ( b
        { velocity =
            vector
              ( map
                  (max (-terminalSpeed) . min terminalSpeed)
                  (components (add (velocity b) (scale acceleration (down b))))
              )
        }
    )

changeGravity :: V -> Body -> Maybe Body
changeGravity target body
  | inside (position body) (extents target) = Nothing
  | otherwise = Just body {down = target, grounded = False}

glslSettings :: String
glslSettings =
  unlines $
    [ "#ifndef MANIFOLD_GRAVITY_SETTINGS",
      "#define MANIFOLD_GRAVITY_SETTINGS",
      "const float GRAVITY_PERIOD = 32.0;",
      "const float GRAVITY_UNIT = 4096.0;",
      "const float GRAVITY_EYE_HEIGHT = 0.72;",
      "const float GRAVITY_TURN_SECONDS = 0.4;",
      "mat3 gravityBasis(int id) {"
    ]
      ++ [ "  if (id == " ++ show i ++ ") return mat3(" ++ vec a ++ "," ++ vec b ++ "," ++ vec c ++ ");"
         | (i, (a, b, c)) <- zip [0 :: Int ..] frames
         ]
      ++ [ "  return mat3(1);",
           "}",
           "float gravityDistance(vec3 p) {",
           "  vec3 q = abs(mod(p + GRAVITY_PERIOD * .5, GRAVITY_PERIOD) - GRAVITY_PERIOD * .5);",
           "  float d = 1e6;"
         ]
      ++ [ "  { vec2 a = q."
             ++ ["yz", "xz", "xy"] !! free
             ++ " - "
             ++ show (fromIntegral r / fromIntegral unit :: Double)
             ++ "; d = min(d, length(max(a, 0.0)) + min(max(a.x, a.y), 0.0)); }"
         | Beam free r <- beams
         ]
      ++ ["  return d;", "}", "#endif"]
  where
    vec v = "vec3(" ++ comma (map (show . (fromIntegral :: Int -> Double)) (components v)) ++ ")"
    comma = foldr1 (\a b -> a ++ "," ++ b)
