module Manifold.Joinery.Render (glsl) where

import Data.List (intercalate)
import Data.Set qualified as S
import Manifold.Gravity qualified as G
import Manifold.Joinery qualified as J
import Manifold.Stage (Box (..))

glsl :: String
glsl =
  unlines $
    [ "#ifndef MANIFOLD_JOINERY_SCENE",
      "#define MANIFOLD_JOINERY_SCENE",
      "#include <manifold:ray_box.glsl>",
      "const int JOINERY_AXIS[6]=int[](" ++ intercalate "," (map (show . J.rodAxis) J.rods) ++ ");",
      "ivec3 joineryPose(int id) { uint word=ObjectCache0[id/2]>>uint(12*(id%2)); return ivec3(word&15u,(word>>4u)&15u,(word>>8u)&15u); }",
      "vec3 joineryDirection(int d) { return d==0 ? vec3(0,-1,0) : d==1 ? vec3(0,1,0) : d==2 ? vec3(-1,0,0) : d==3 ? vec3(1,0,0) : d==4 ? vec3(0,0,-1) : vec3(0,0,1); }",
      "vec3 joineryShift(int id) { vec3 p=vec3(joineryPose(id))*4.0; if(int(JoineryMotion.x)==id) p+=joineryDirection(int(JoineryMotion.y))*4.0*smoothstep(0.0,1.0,JoineryMotion.w); return mod(p,64.0); }",
      "bool joineryHome(int id) { return all(equal(joineryPose(id),ivec3(0))); }",
      "float joineryBox(vec3 p,vec3 lo,vec3 hi) { vec3 q=abs(mod(p-(lo+hi)*.5+32.0,64.0)-32.0)-(hi-lo)*.5; return length(max(q,0.0))+min(max(q.x,max(q.y,q.z)),0.0); }",
      "float joineryRodDistance(vec3 p,int id) { p-=joineryShift(id); float d=1e6;"
    ]
      ++ concat [["if(id==" ++ show (J.rodId rod) ++ ") {"] ++ ["d=min(d,joineryBox(p," ++ vec (-0.5) (boxLo b) ++ "," ++ vec 0.5 (boxHi b) ++ "));" | b <- J.boxes rod] ++ ["}"] | rod <- J.rods]
      ++ ["return d; }", "float joineryEnvelopeDistance(vec3 p,int id) { p-=joineryShift(id);"]
      ++ ["if(id==" ++ show (J.rodId rod) ++ ") return joineryBox(p," ++ vec (-0.5) (G.scale 4 lo) ++ "," ++ vec 0.5 (G.add (G.scale 4 hi) (3, 3, 3)) ++ ");" | rod <- J.rods, let (lo, hi) = J.rodBounds rod]
      ++ [ "return 1e6; }",
           "float joineryDistance(vec3 p) { float d=1e6; for(int id=0;id<6;id++) if(joineryEnvelopeDistance(p,id)<d) d=min(d,joineryRodDistance(p,id)); return d; }",
           "int joineryMember(vec3 p) { float nearest=1e6; int member=0; for(int id=0;id<6;id++) { float d=abs(joineryRodDistance(p,id)); if(d<nearest) { nearest=d; member=id; } } return member; }",
           "void joineryTraceCell(vec3 origin,vec3 inv,float start,float end,inout float nearest,inout vec3 normal) {"
         ]
      ++ concat
        [ let boxes = J.boxes rod; low = G.vector [minimum [G.component a (boxLo b) | b <- boxes] | a <- [0 .. 2]]; high = G.vector [maximum [G.component a (boxHi b) | b <- boxes] | a <- [0 .. 2]]
           in ["{ int id=" ++ show (J.rodId rod) ++ "; vec3 shift=joineryShift(id); vec3 low=" ++ vec (-0.5) low ++ ", high=" ++ vec 0.5 high ++ "; ivec3 first=ivec3(greaterThan(low+shift,vec3(63.5))), last=ivec3(greaterThan(high+shift,vec3(63.5))); for(int image=0;image<8;image++) { ivec3 tile=ivec3(image&1,(image>>1)&1,(image>>2)&1); if(any(lessThan(tile,first)) || any(greaterThan(tile,last))) continue; vec3 ro=origin-shift+vec3(tile)*64.0; if(!rayBoxCandidate(ro,inv,low,high,start,min(end,nearest))) continue;"]
                ++ ["rayBoxHit(ro,inv," ++ vec (-0.5) (boxLo b) ++ "," ++ vec 0.5 (boxHi b) ++ ",start,end,nearest,normal);" | b <- boxes]
                ++ ["} }"]
        | rod <- J.rods
        ]
      ++ [ "}",
           "#include <manifold:joinery_trace.glsl>",
           "const uint JOINERY_INTERLOCK[3840]=uint[](" ++ intercalate "," [show word ++ "u" | rod <- J.rods, other <- J.rods, J.rodId rod /= J.rodId other, let { mask = J.obstructingOffsets rod other }, chunk <- [0 .. 127 :: Int], let { word = sum [2 ^ bit :: Integer | bit <- [0 .. 31 :: Int], let cell = chunk * 32 + bit, S.member (cell `mod` 16, (cell `div` 16) `mod` 16, cell `div` 256) mask] }] ++ ");",
           "int joineryBlocker(int id,ivec3 direction) { for(int other=0;other<6;other++) { if(other==id) continue; ivec3 q=(joineryPose(id)+direction-joineryPose(other)+ivec3(16))%16; int cell=q.x+16*q.y+256*q.z; int pair=id*5+other-(other>id ? 1 : 0); if(((JOINERY_INTERLOCK[pair*128+cell/32]>>uint(cell%32))&1u)!=0u) return other; } return -1; }",
           "#endif"
         ]
  where
    vec offset v = "vec3(" ++ intercalate "," [show (fromIntegral n + offset :: Double) | n <- G.components v] ++ ")"
