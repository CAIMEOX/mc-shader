module Manifold.Stage
  ( Box (..),
    stageBoxes,
    transformBlock,
    transformBox,
    stageOrigin,
    stageDistance,
    glslScene,
    buildCommands,
    containsBlock,
    fillSolids,
    clearSolids,
    cacheEnvelope,
  )
where

import Data.List (intercalate, nub)
import Manifold.Gravity qualified as G

-- Endpoints name the inclusive integer block centres in logical space.
-- A physical block centre is stageOrigin + .5 + R^T * logicalCentre.
data Box = Box {boxLo :: G.V, boxHi :: G.V, boxMaterial :: String} deriving (Eq, Show)

cellSize :: Int
cellSize = G.period `div` G.unit

bufferLo, bufferHi :: Int
-- The halo covers a 4.5-block interaction ray, eye offset, and cube extent.
bufferLo = -6
bufferHi = cellSize + 5

-- Each pillar follows the three periodic beams used by the gravity controller.
-- The extra boundary cells support native collision across a cell handoff.
stageBoxes :: [Box]
stageBoxes =
  [ Box
      (G.vector [if axis == free then bufferLo else centre axis - radius | axis <- [0 .. 2]])
      (G.vector [if axis == free then bufferHi else centre axis + radius | axis <- [0 .. 2]])
      "minecraft:quartz_block"
  | G.Beam free width <- G.beams,
    let radius = width `div` G.unit,
    a <- [0, cellSize],
    b <- [0, cellSize],
    let firstConstrained = if free == 0 then 1 else 0
        centre axis = if axis == firstConstrained then a else b
  ]

transformBlock :: G.Frame -> G.V -> G.V
transformBlock (right, up, forward) p = (G.dot right p, G.dot up p, G.dot forward p)

transformBox :: G.Frame -> Box -> Box
transformBox frame box = box {boxLo = pair min, boxHi = pair max}
  where
    a = G.components (transformBlock frame (boxLo box))
    b = G.components (transformBlock frame (boxHi box))
    pair f = G.vector (zipWith f a b)

stageOrigin :: Int -> G.V
stageOrigin 0 = (0, 200, 0)
stageOrigin 1 = (80, 200, 0)
stageOrigin _ = error "A native stage slot is 0 or 1"

containsBlock :: Box -> G.V -> Bool
containsBlock box p =
  and (zipWith (<=) (G.components (boxLo box)) (G.components p))
    && and (zipWith (<=) (G.components p) (G.components (boxHi box)))

-- The analytic scene uses complete periodic primitives. Wrapping around each
-- primitive centre selects its closest image across all three cell boundaries.
-- Native room materialisation independently clips those primitives to its cache.
sceneBoxes :: [Box]
sceneBoxes = nub (map canonical stageBoxes)
  where
    canonical box =
      let offset = G.vector [negate (cellSize * (((low + high) `div` 2) `div` cellSize)) | (low, high) <- zip (G.components (boxLo box)) (G.components (boxHi box))]
       in box {boxLo = G.add (boxLo box) offset, boxHi = G.add (boxHi box) offset}

-- The CPU distance query and GLSL are interpretations of the same Box values.
stageDistance :: (Double, Double, Double) -> Double
stageDistance (x, y, z) = minimum (map distance sceneBoxes)
  where
    period = fromIntegral cellSize
    closestImage a = a - period * fromIntegral (floor ((a + period / 2) / period) :: Int)
    distance box =
      let lo = map ((subtract 0.5) . fromIntegral) (G.components (boxLo box))
          hi = map ((+ 0.5) . fromIntegral) (G.components (boxHi box))
          q = zipWith3 (\a low high -> abs (closestImage (a - (low + high) / 2)) - (high - low) / 2) [x, y, z] lo hi
       in sqrt (sum [max 0 a ^ (2 :: Int) | a <- q]) + min 0 (maximum q)

glslScene :: String
glslScene =
  unlines $
    [ "#ifndef MANIFOLD_STAGE",
      "#define MANIFOLD_STAGE",
      "#include <manifold:surface_finish.glsl>",
      "const vec3 NATIVE_WINDOW_LO = vec3(" ++ show (fromIntegral bufferLo - 0.5 :: Double) ++ ");",
      "const vec3 NATIVE_WINDOW_HI = vec3(" ++ show (fromIntegral bufferHi + 0.5 :: Double) ++ ");",
      "float stageBoxDistance(vec3 p, vec3 lo, vec3 hi) {",
      "  vec3 relative = mod(p - (lo + hi) * .5 + " ++ halfPeriod ++ ", " ++ period ++ ") - " ++ halfPeriod ++ ";",
      "  vec3 q = abs(relative) - (hi - lo) * .5;",
      "  return length(max(q, 0.0)) + min(max(q.x, max(q.y, q.z)), 0.0);",
      "}",
      "float stageDistance(vec3 p) {",
      "  float d = 1e6;"
    ]
      ++ map (emit "  ") sceneBoxes
      ++ ["  return d;", "}"]
      ++ [glslFinish "stageSurfaceFinish(vec3 p, vec3 n, float footprint)" sceneBoxes]
      ++ ["#endif"]
  where
    period = show (fromIntegral cellSize :: Double)
    halfPeriod = show (fromIntegral cellSize / 2 :: Double)
    vec offset v = "vec3(" ++ intercalate "," [show (fromIntegral x + offset :: Double) | x <- G.components v] ++ ")"
    emit indent box = indent ++ "d = min(d, stageBoxDistance(p, " ++ vec (-0.5) (boxLo box) ++ ", " ++ vec 0.5 (boxHi box) ++ "));"

glslFinish :: String -> [Box] -> String
glslFinish signature boxes =
  unlines $
    ["vec4 " ++ signature ++ " {", "  float nearest = 1e6;", "  vec4 detail = vec4(n, 8.0);"]
      ++ ["  stageBoxFinish(p, n, " ++ vec (-0.5) (boxLo b) ++ ", " ++ vec 0.5 (boxHi b) ++ ", footprint, nearest, detail);" | b <- boxes]
      ++ ["  return detail;", "}"]
  where
    vec offset v = "vec3(" ++ intercalate "," [show (fromIntegral x + offset :: Double) | x <- G.components v] ++ ")"

buildCommands :: Int -> Int -> [String]
buildCommands slot frameId = clearSolids slot Nothing ++ fillSolids slot frameId stageBoxes

cacheEnvelope :: Maybe G.Frame -> Box
cacheEnvelope previous = case previous of
  Just frame -> transformBox frame (Box (bufferLo, bufferLo, bufferLo) (bufferHi, bufferHi, bufferHi) "minecraft:air")
  Nothing -> let radius = bufferHi + 1 in Box (-radius, -radius, -radius) (radius, radius, radius) "minecraft:air"

clearSolids :: Int -> Maybe Int -> [String]
clearSolids slot previous =
  [ "fill " ++ coordinates (lx, y, lz) ++ " " ++ coordinates (hx, min hy (y + height - 1), hz) ++ " minecraft:air"
  | y <- [ly, ly + height .. hy]
  ]
  where
    bounds = cacheEnvelope ((G.frames !!) <$> previous)
    (lx, ly, lz) = G.add (stageOrigin slot) (boxLo bounds)
    (hx, hy, hz) = G.add (stageOrigin slot) (boxHi bounds)
    height = 32768 `div` ((hx - lx + 1) * (hz - lz + 1))
    coordinates = unwords . map show . G.components

fillSolids :: Int -> Int -> [Box] -> [String]
fillSolids slot frameId boxes = map fillBox boxes
  where
    frame
      | frameId >= 0 && frameId < length G.frames = G.frames !! frameId
      | otherwise = error "A stage frame belongs to the cube rotation group"
    origin = stageOrigin slot
    fillBox box =
      let transformed = transformBox frame box
       in fill (G.add origin (boxLo transformed)) (G.add origin (boxHi transformed)) (boxMaterial box)
    fill low high block = "fill " ++ coordinates low ++ " " ++ coordinates high ++ " " ++ block
    coordinates = unwords . map show . G.components
