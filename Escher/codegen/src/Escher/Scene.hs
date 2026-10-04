module Escher.Scene where

import Data.List (intercalate, minimumBy)
import Data.Ord (comparing)
import Escher.Space (V3, norm, subtractV, wrap)

data Material = Stone | Chalk | Checker | Green | Red | Brass deriving (Eq, Ord, Show, Enum)

data Shape
  = Box V3 Material
  | Ball Double Material
  | Arch Double Double Double Material
  | Move V3 Shape
  | RepeatX Double Shape
  | RepeatZ Double Shape
  | Union [Shape]
  deriving (Show)

box :: V3 -> V3 -> Material -> Shape
box at size material = Move at (Box size material)

-- Half extents are shared by the distance field and the collision voxelizer.
gallery :: Shape
gallery =
  Union $
    [box (0, -5.5, 0) (8, 0.5, 10000) Checker]
      ++ [ Union
             [ box (x, 6, 0) (0.22, 0.22, 10000) Stone,
               box (x, 4, 0) (0.4, 0.18, 10000) Chalk,
               box (x, -3.85, 0) (0.065, 0.07, 10000) Green,
               RepeatZ 0.75 (box (x, -4.4, 0) (0.045, 0.55, 0.045) Green),
               RepeatZ 18 (Union [box (x, 0.5, 0) (0.5, 5.5, 0.5) Stone, box (x, -4.65, 0) (0.67, 0.35, 0.7) Chalk]),
               RepeatZ
                 6
                 ( Union
                     [ Move (x, 1, 0) (Arch 2.25 0.3 0.3 Stone),
                       box (x, -2, 2.5) (0.3, 3, 0.3) Stone,
                       box (x, -2, -2.5) (0.3, 3, 0.3) Stone,
                       box (x, 0.85, 2.5) (0.46, 0.15, 0.48) Chalk,
                       box (x, 0.85, -2.5) (0.46, 0.15, 0.48) Chalk
                     ]
                 )
             ]
         | x <- [-7.5, 7.5]
         ]
      ++ [ RepeatZ
             18
             ( Union
                 [ box (0, 6, 0) (8, 0.5, 0.5) Stone,
                   box (0, 5.8, 0.51) (7.3, 0.06, 0.04) Green
                 ]
             ),
           Move
             (0, 0, 5.5)
             ( RepeatZ
                 18
                 ( Union
                     [ box (3.5, -4.5, 0) (0.7, 0.5, 0.7) Stone,
                       box (3.5, -3.92, 0) (0.85, 0.08, 0.85) Chalk,
                       Move (3.5, -3.08, 0) (Ball 0.76 Red)
                     ]
                 )
             ),
           Move
             (0, 0, 7.5)
             ( RepeatZ
                 18
                 ( Union
                     (box (-3.5, 3.5, 0) (0.018, 2.5, 0.018) Green : frame (-3.5, 0, 0) 1.1 0.035 Brass)
                 )
             )
         ]
      ++ [Union [Move (0, 0, 1 + fromIntegral i) (RepeatZ 18 (box (-9, -4.8 + fromIntegral i * 0.38, 0) (1, 0.15, 0.55) Stone)) | i <- [0 .. 11 :: Int]]]
  where
    frame (x, y, z) r t m =
      [box (x, y + a * r, z + b * r) (r, t, t) m | a <- [-1, 1], b <- [-1, 1]]
        ++ [box (x + a * r, y, z + b * r) (t, r, t) m | a <- [-1, 1], b <- [-1, 1]]
        ++ [box (x + a * r, y + b * r, z) (t, t, r) m | a <- [-1, 1], b <- [-1, 1]]

-- Repetition distributes through unions and commutes with translations.
-- Folding coordinates at the primitive origin keeps whole translated objects.
canonical :: Shape -> Shape
canonical (Move at child) = Move at (canonical child)
canonical (Union children) = Union (map canonical children)
canonical (RepeatX period child) = repeatInside (RepeatX period) (canonical child)
canonical (RepeatZ period child) = repeatInside (RepeatZ period) (canonical child)
canonical shape = shape

repeatInside :: (Shape -> Shape) -> Shape -> Shape
repeatInside repeatShape (Move at child) = Move at (repeatInside repeatShape child)
repeatInside repeatShape (Union children) = Union (map (repeatInside repeatShape) children)
repeatInside repeatShape child = repeatShape child

sample :: Shape -> V3 -> (Double, Material)
sample shape = sampleCanonical (canonical shape)

sampleCanonical :: Shape -> V3 -> (Double, Material)
sampleCanonical (Box b m) p = (outside + min 0 (maximum qs), m)
  where
    (x, y, z) = subtractV (absolute p) b; qs = [x, y, z]; outside = norm (max x 0, max y 0, max z 0)
sampleCanonical (Ball r m) p = (norm p - r, m)
sampleCanonical (Arch r t depth m) (x, y, z) = (norm (max dx 0, max dr 0, 0) + min 0 (max dx dr), m)
  where
    dx = abs x - depth
    radial = abs (sqrt (y * y + z * z) - (r + t / 2)) - t / 2
    dr = if y < 0 then norm (y, max 0 (max (r - abs z) (abs z - r - t)), 0) else max radial (-y)
sampleCanonical (Move at shape) p = sampleCanonical shape (subtractV p at)
sampleCanonical (RepeatX len shape) (x, y, z) = sampleCanonical shape (wrap len (x + len / 2) - len / 2, y, z)
sampleCanonical (RepeatZ len shape) (x, y, z) = sampleCanonical shape (x, y, wrap len (z + len / 2) - len / 2)
sampleCanonical (Union shapes) p = minimumBy (comparing fst) (map (`sampleCanonical` p) shapes)

absolute :: V3 -> V3
absolute (x, y, z) = (abs x, abs y, abs z)

-- Bounds are derived from the same geometry tree and provide conservative
-- distances while a ray is far from an arcade, staircase or ornament.
bounds :: Shape -> (V3, V3)
bounds (Box b _) = (scaleV (-1) b, b)
bounds (Ball r _) = ((-r, -r, -r), (r, r, r))
bounds (Arch r t d _) = ((-d, 0, -r - t), (d, r + t, r + t))
bounds (Move at s) = let (lo, hi) = bounds s in (zipV (+) lo at, zipV (+) hi at)
bounds (RepeatX _ s) = let ((_, y, z), (_, b, c)) = bounds s in ((-10000, y, z), (10000, b, c))
bounds (RepeatZ _ s) = let ((x, y, _), (a, b, _)) = bounds s in ((x, y, -10000), (a, b, 10000))
bounds (Union ss) = foldl1 (\(a, b) (c, d) -> (zipV min a c, zipV max b d)) (map bounds ss)

zipV :: (Double -> Double -> Double) -> V3 -> V3 -> V3
zipV f (x, y, z) (a, b, c) = (f x a, f y b, f z c)

scaleV :: Double -> V3 -> V3
scaleV k (x, y, z) = (k * x, k * y, k * z)

-- Materialized blocks provide a coarse collision envelope; curved ornaments
-- keep their analytic surface in the shader. The red balls are visual objects.
voxels :: [((Int, Int, Int), Material)]
voxels =
  [ ((x, y, z), material)
  | z <- [0 .. 17],
    y <- [-6 .. 6],
    x <- [-11 .. 8],
    let (distance, material) = sample gallery (fromIntegral x + 0.5, fromIntegral y + 0.5, fromIntegral z + 0.5),
    distance < -0.001,
    material /= Red
  ]

glsl :: Shape -> String
glsl = glslNamed "scene"

glslNamed :: String -> Shape -> String
glslNamed name root = unlines definitions ++ "\nvec2 " ++ name ++ "(vec3 p){return " ++ prefix ++ show index ++ "(p);}\n"
  where
    prefix = name ++ "Shape"
    (_, index, definitions) = compile 0 (canonical root)
    compile :: Int -> Shape -> (Int, Int, [String])
    compile next shape = case shape of
      Union children ->
        let (n, ids, defs) = foldl (\(k, is, ds) child -> let (k', i, d) = compile k child in (k', is ++ [(i, child)], ds ++ d)) (next, [], []) children
         in (n + 1, n, defs ++ [fun n ("vec2 h=vec2(1e8,0);" ++ concat [bounded i child | (i, child) <- ids] ++ "return h;")])
      Move at child -> unary next child ("p-" ++ vec at)
      RepeatX len child -> unary next child ("vec3(mod(p.x+" ++ show (len / 2) ++ "," ++ show len ++ ")-" ++ show (len / 2) ++ ",p.yz)")
      RepeatZ len child -> unary next child ("vec3(p.xy,mod(p.z+" ++ show (len / 2) ++ "," ++ show len ++ ")-" ++ show (len / 2) ++ ")")
      Box size material -> leaf ("sdBox(p," ++ vec size ++ ")") material
      Ball radius material -> leaf ("length(p)-" ++ show radius) material
      Arch radius thick depth material -> leaf ("sdArch(p," ++ intercalate "," (map show [radius, thick, depth]) ++ ")") material
      where
        leaf expression material = (next + 1, next, [fun next ("return vec2(" ++ expression ++ "," ++ show (fromEnum material) ++ ");")])
    unary next child expression = let (n, i, defs) = compile next child in (n + 1, n, defs ++ [fun n ("return " ++ prefix ++ show i ++ "(" ++ expression ++ ");")])
    bounded i child =
      let (lo, hi) = bounds child
          center = scaleV 0.5 (zipV (+) lo hi)
          size = scaleV 0.5 (subtractV hi lo)
          call = "h=nearest(h," ++ prefix ++ show i ++ "(p));"
       in if primitive child then call else "if(sdBox(p-" ++ vec center ++ "," ++ vec size ++ ")<h.x)" ++ call
    primitive (Move _ child) = primitive child
    primitive (RepeatX _ child) = primitive child
    primitive (RepeatZ _ child) = primitive child
    primitive (Union _) = False
    primitive _ = True
    fun i body = "vec2 " ++ prefix ++ show i ++ "(vec3 p){" ++ body ++ "}"
    vec (x, y, z) = "vec3(" ++ intercalate "," (map show [x, y, z]) ++ ")"
