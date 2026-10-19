module Manifold.ThreeRings where

import Data.List (intercalate, sortOn)
import Manifold.Gravity qualified as G
import Manifold.Objects qualified as O
import Manifold.Scene
import Manifold.Stage (Box (..))

period :: Int
period = 64

cubes :: [O.Cube]
cubes = [O.Cube 0 (0, 1, 0) (8, 63, 4) O.Resting, O.Cube 1 (-1, 0, 0) (27, 3, 4) O.Resting, O.Cube 2 (0, 0, 1) (53, 3, 28) O.Resting]

cubeMaterial :: O.Cube -> String
cubeMaterial cube =
  "minecraft:" ++ case O.cubeGravity cube of
    (0, 1, 0) -> "light_blue_concrete"
    (-1, 0, 0) -> "orange_concrete"
    (0, 0, 1) -> "lime_concrete"
    (0, -1, 0) -> "yellow_concrete"
    (1, 0, 0) -> "magenta_concrete"
    _ -> "purple_concrete"

data Socket = Socket {socketId :: Int, socketCube :: Int, socketCell :: G.V, socketFinal :: Bool} deriving (Eq, Show)

sockets :: [Socket]
sockets = [Socket 0 0 (26, 63, 4) False, Socket 1 1 (52, 3, 18) False, Socket 2 2 (24, 3, 28) False, Socket 3 0 (38, 63, 12) True, Socket 4 1 (38, 3, 9) True, Socket 5 2 (38, 3, 28) True]

circuits :: [Circuit]
circuits = [Circuit [(0, (26, 63, 4)), (2, (24, 3, 28)), (0, (38, 63, 12))] 0, Circuit [(1, (52, 3, 18)), (1, (38, 3, 9))] 1]

complete :: O.World -> Bool
complete world = all occupiedFinal (filter socketFinal sockets)
  where
    occupiedFinal socket = any (\cube -> O.cubeId cube == socketCube socket && O.cubeCell cube == socketCell socket && O.cubePhase cube /= O.Carried) (O.cubes world)

scene :: Scene
scene = either error id (compileScene period authoredSolids)

solids :: [Solid]
solids = sceneSolids scene

authoredSolids :: [Solid]
authoredSolids =
  [ plain (4, 0, 2) (45, 0, 7),
    plain (6, 0, 0) (12, 0, 9),
    plain (28, 0, 7) (45, 0, 16),
    plain (24, 0, 6) (28, 0, 26),
    plain (29, 0, 7) (31, 0, 29),
    plain (24, -1, 29) (28, 6, 29),
    plain (26, 0, 3) (26, 7, 9),
    plain (26, 0, 1) (30, 0, 2),
    plain (26, 0, 6) (30, 0, 9),
    door 0 (27, 0, 3) (29, 0, 5),
    plain (30, 0, 1) (30, 8, 9),
    plain (26, 8, 1) (30, 8, 9),
    plain (26, 0, 1) (30, 8, 1),
    plain (26, 0, 9) (30, 1, 9),
    plain (26, 6, 9) (30, 8, 9),
    door 0 (27, 2, 9) (29, 5, 9),
    plain (5, 2, 10) (5, 5, 17),
    plain (0, 2, 18) (8, 2, 18),
    plain (51, 1, 16) (51, 7, 28),
    plain (20, -2, 29) (56, 10, 29),
    plain (50, 0, 21) (56, 0, 29),
    plain (50, 8, 21) (56, 8, 29),
    plain (56, 0, 21) (56, 8, 29),
    plain (50, 0, 21) (56, 1, 21),
    plain (50, 6, 21) (56, 8, 21),
    door 1 (52, 2, 21) (55, 5, 21),
    plain (50, 0, 21) (50, 8, 25),
    plain (50, 0, 26) (50, 1, 29),
    plain (50, 6, 26) (50, 8, 29),
    door 1 (50, 2, 26) (51, 5, 28),
    plain (32, 60, 9) (44, 60, 16),
    plain (44, 60, 9) (44, 63, 16),
    plain (32, 60, 9) (44, 63, 9),
    plain (32, 60, 16) (44, 63, 16),
    plain (32, 60, 9) (32, 63, 10),
    plain (32, 60, 14) (32, 63, 16),
    door 0 (32, 61, 11) (32, 63, 13),
    plain (37, 1, 8) (37, 6, 20),
    plain (32, 0, 22) (44, 0, 29),
    plain (32, 8, 22) (44, 8, 29),
    plain (44, 0, 22) (44, 8, 29),
    plain (32, 0, 22) (44, 8, 22),
    plain (32, 0, 22) (32, 8, 25),
    plain (32, 0, 26) (32, 1, 29),
    plain (32, 6, 26) (32, 8, 29),
    door 0 (32, 2, 26) (32, 5, 28),
    plain (36, 12, 16) (40, 42, 20),
    plain (28, 20, 18) (48, 22, 20),
    plain (38, 30, 10) (40, 32, 30),
    plain (0, 16, 40) (2, 46, 42),
    plain (0, 16, 40) (20, 18, 42),
    plain (0, 44, 40) (20, 46, 42),
    plain (18, 16, 40) (20, 46, 42),
    plain (12, 30, 44) (14, 32, 63),
    plain (12, 30, 44) (30, 32, 46)
  ]
  where
    plain low high = Solid (Box low high "minecraft:quartz_block") Nothing
    door channel low high = Solid (Box low high "minecraft:white_concrete") (Just channel)

-- A conservative hierarchy prunes distant wings before evaluating their details.
glslScene :: String
glslScene =
  unlines $
    [ "#ifndef MANIFOLD_RINGS_SCENE",
      "#define MANIFOLD_RINGS_SCENE",
      "uint ringsWord(int id) { return id<4 ? ObjectCache0[id] : (id<8 ? ObjectCache1[id-4] : packetWord(PacketSampler,OBJECT_WORD_OFFSET+id)); }",
      "bool ringsGate(int id) { if(id==0) return RingsData.y>.5; if(id==1) return RingsData.z>.5; return (bits(PacketSampler,FIELD_R_GATES,16) & (1u<<uint(id))) != 0u; }",
      "vec3 ringsOffset(vec3 p, vec3 centre) { return mod(p-centre+32.0,64.0)-32.0; }",
      "float ringsBox(vec3 p, vec3 lo, vec3 hi) { vec3 q=abs(ringsOffset(p,(lo+hi)*.5))-(hi-lo)*.5; return length(max(q,0.0))+min(max(q.x,max(q.y,q.z)),0.0); }",
      "vec3 ringsCube(int id) { uint w=ringsWord(id); return vec3(w&63u,(w>>6u)&63u,(w>>12u)&63u); }",
      "int ringsPhase(int id) { return int((ringsWord(id)>>18u)&3u); }",
      "const vec3 RINGS_GRAVITY[OBJECT_COUNT]=vec3[](" ++ intercalate "," [vec 0 (O.cubeGravity cube) | cube <- cubes] ++ ");",
      "const vec3 RINGS_SOCKET[SOCKET_COUNT]=vec3[](" ++ intercalate "," [vec 0 (socketCell socket) | socket <- sockets] ++ ");",
      "const int RINGS_SOCKET_CUBE[SOCKET_COUNT]=int[](" ++ intercalate "," [show (socketCube socket) | socket <- sockets] ++ ");",
      "float ringsDistance(vec3 p) { float d=1e6;"
    ]
      ++ hierarchy False solids
      ++ [ "for(int i=0;i<OBJECT_COUNT;i++) if(ringsPhase(i)!=1) { vec3 c=ringsCube(i); d=min(d,ringsBox(p,c-.5,c+.5)); }",
           "return d; }",
           "vec4 ringsFinish(vec3 p,vec3 n,float footprint) { float nearest=1e6; vec4 detail=vec4(n,8.0);"
         ]
      ++ hierarchy True solids
      ++ ["return detail; }", "#include <manifold:ray_box.glsl>", "void ringsTraceCell(vec3 ro,vec3 inv,float start,float end,inout float nearest,inout vec3 normal) {"]
      ++ rayHierarchy (canonicalSolids scene)
      ++ ["}", "#include <manifold:rings_trace.glsl>", "#endif"]
  where
    vec offset v = "vec3(" ++ intercalate "," [show (fromIntegral n + offset :: Double) | n <- G.components v] ++ ")"
    hierarchy finish values
      | length values <= 3 = concatMap (leaf finish) values
      | otherwise =
          let low = G.vector [minimum [G.component a (boxLo (solidBox s)) | s <- values] | a <- [0 .. 2]]
              high = G.vector [maximum [G.component a (boxHi (solidBox s)) | s <- values] | a <- [0 .. 2]]
              extent = G.sub high low
              axis = snd (maximum [(G.component a extent, a) | a <- [0 .. 2]])
              ordered = sortOn (\s -> G.component axis (G.add (boxLo (solidBox s)) (boxHi (solidBox s)))) values
              (first, second) = splitAt (length ordered `div` 2) ordered
           in ["if (ringsBox(p," ++ vec (-0.5) low ++ "," ++ vec 0.5 high ++ ") < " ++ (if finish then ".06" else "d") ++ ") {"] ++ hierarchy finish first ++ hierarchy finish second ++ ["}"]
    leaf finish solid =
      let box = solidBox solid
          bounds = vec (-0.5) (boxLo box) ++ "," ++ vec 0.5 (boxHi box)
          condition = maybe "true" (\i -> "!ringsGate(" ++ show i ++ ")") (solidChannel solid)
       in ["if(" ++ condition ++ ") " ++ if finish then "stageBoxFinishPeriod(p,n," ++ bounds ++ ",footprint,64.0,nearest,detail);" else "d=min(d,ringsBox(p," ++ bounds ++ "));"]
    rayHierarchy values
      | length values <= 3 =
          [ let box = solidBox solid
                condition = maybe "true" (\i -> "!ringsGate(" ++ show i ++ ")") (solidChannel solid)
             in "if(" ++ condition ++ ") rayBoxHit(ro,inv," ++ vec (-0.5) (boxLo box) ++ "," ++ vec 0.5 (boxHi box) ++ ",start,end,nearest,normal);"
          | solid <- values
          ]
      | otherwise =
          let low = G.vector [minimum [G.component a (boxLo (solidBox s)) | s <- values] | a <- [0 .. 2]]
              high = G.vector [maximum [G.component a (boxHi (solidBox s)) | s <- values] | a <- [0 .. 2]]
              axis = snd (maximum [(G.component a (G.sub high low), a) | a <- [0 .. 2]])
              ordered = sortOn (\s -> G.component axis (G.add (boxLo (solidBox s)) (boxHi (solidBox s)))) values
              (first, second) = splitAt (length ordered `div` 2) ordered
           in ["if(rayBoxCandidate(ro,inv," ++ vec (-0.5) low ++ "," ++ vec 0.5 high ++ ",start,min(end,nearest))) {"] ++ rayHierarchy first ++ rayHierarchy second ++ ["}"]
