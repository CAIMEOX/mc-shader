module Manifold.Rooms.DataPack (Layout (..), resources) where

import Manifold.Gravity qualified as G
import Manifold.Runtime qualified as R
import Manifold.Scene qualified as Scene
import Manifold.Stage qualified as S

data Layout = Layout
  { layoutId :: Int,
    layoutGeometry :: [(String, S.Box)],
    layoutMaterialize :: Maybe String,
    layoutActivate :: String,
    layoutDoors :: [(Int, S.Box)]
  }

resources :: [Layout] -> [(FilePath, String)]
resources layouts = R.resources "rooms" (functions layouts)

axes :: [String]
axes = ["x", "y", "z"]

functions :: [Layout] -> R.Functions
functions layouts =
  [ ("activate", [R.when (R.test "h.level" (show (layoutId layout))) (R.call (layoutActivate layout)) | layout <- layouts]),
    ("materialize", [R.when (R.test "h.level" (show (layoutId layout))) (R.call hook) | layout <- layouts, Just hook <- [layoutMaterialize layout]]),
    ("restore", [R.when (R.test ("r.region" ++ show slot) "0..7") (R.op ("r.window" ++ show slot) "=" ("r.region" ++ show slot)) | slot <- [0, 1 :: Int]]),
    ( "region",
      concat [[R.op ("r.n" ++ a) "=" ("g." ++ a), R.op ("r.n" ++ a) "/=" "r.window"] | a <- axes]
        ++ [R.op "r.region" "=" "r.nz", R.op "r.region" "*=" "r.two", R.op "r.region" "+=" "r.ny", R.op "r.region" "*=" "r.two", R.op "r.region" "+=" "r.nx"]
    ),
    ( "sync",
      ["execute store result score #g.grounded manifold run data get entity @s OnGround"]
        ++ ["execute store result score #h.p" ++ a ++ " manifold run data get entity @s Pos[" ++ show i ++ "] 4096" | (i, a) <- zip [0 :: Int ..] axes]
        ++ [R.when (R.test "h.slot" (show slot)) (R.call ("hybrid/origin/" ++ show slot)) | slot <- [0, 1 :: Int]]
        ++ ["scoreboard players add #h.py manifold " ++ show G.bodyHeight]
        ++ [R.when (R.test "g.frame" (show frame)) (R.call ("hybrid/read/" ++ show frame)) | frame <- [0 .. 23 :: Int]]
        ++ concat [[R.op ("r.local" ++ a) "=" ("g." ++ a), R.op "r.tmp" "=" ("r.w" ++ a), R.op "r.tmp" "*=" "r.window", R.op ("g." ++ a) "+=" "r.tmp", R.op ("g." ++ a) "%=" "g.period"] | a <- axes]
        ++ [R.set "r.shift" 0]
        ++ [R.when (R.test ("r.local" ++ a) "..-1") (R.set "r.shift" 1) | a <- axes]
        ++ [R.when (R.test ("r.local" ++ a) "131072..") (R.set "r.shift" 1) | a <- axes]
        ++ [R.when (R.test "h.mode" "1" ++ " " ++ R.test "r.shift" "1") (R.call "rooms/shift")]
    ),
    ( "shift",
      -- Rebase the physical copy by an integer translation. Relative teleport
      -- preserves client momentum; the logical position and motion mode stay live.
      [R.set "r.next" 1, R.op "r.next" "-=" "h.slot"]
        ++ [R.when (R.test "r.next" (show slot) ++ " " ++ R.test "g.frame" (show frame)) (R.call ("rooms/build/" ++ show slot ++ "/" ++ show frame)) | slot <- [0, 1 :: Int], frame <- [0 .. 23 :: Int]]
        ++ concat
          [ [ R.op "r.tmp" "=" ("r.w" ++ a),
              R.op "r.tmp" "*=" "r.window",
              R.op ("r.p" ++ a) "=" ("g." ++ a),
              R.op ("r.p" ++ a) "-=" "r.tmp",
              R.op "r.tmp" "=" ("r.p" ++ a),
              R.op ("r.p" ++ a) "-=" ("r.local" ++ a),
              R.op ("r.p" ++ a) "/=" "g.unit",
              R.op ("r.local" ++ a) "=" "r.tmp"
            ]
          | a <- axes
          ]
        ++ [R.when (R.test "g.frame" (show frame)) (R.call ("rooms/rotate/" ++ show frame)) | frame <- [0 .. 23 :: Int]]
        ++ [R.when (R.test "r.next" "1") (R.add "p.x" 80), R.when (R.test "r.next" "0") (R.add "p.x" (-80))]
        ++ [R.put ("shift." ++ a) ("p." ++ a) | a <- axes]
        ++ [R.op "h.slot" "=" "r.next", R.call "rooms/translate with storage manifold:runtime shift", R.call "rooms/activate"]
    ),
    ("translate", ["$execute at @s run tp @s ~$(x) ~$(y) ~$(z) ~ ~"]),
    ( "place",
      concat [[R.op ("r.saved" ++ a) "=" ("g." ++ a), R.op "r.tmp" "=" ("r.w" ++ a), R.op "r.tmp" "*=" "r.window", R.op ("g." ++ a) "-=" "r.tmp"] | a <- axes]
        ++ [R.when (R.test "g.frame" (show frame)) (R.call ("hybrid/write/" ++ show frame)) | frame <- [0 .. 23 :: Int]]
        ++ [R.op ("g." ++ a) "=" ("r.saved" ++ a) | a <- axes]
        ++ [R.call "hybrid/place_coordinates"]
    ),
    ("tick", ["scoreboard players add #r.age0 manifold 1", "scoreboard players add #r.age1 manifold 1"]),
    ( "cell",
      [R.when (R.test "h.slot" "1") "scoreboard players remove #q.x manifold 80", "scoreboard players remove #q.y manifold 200"]
        ++ [R.op ("r.p" ++ a) "=" ("q." ++ a) | a <- axes]
        ++ [R.when (R.test "g.frame" (show frame)) (R.call ("rooms/inverse/" ++ show frame)) | frame <- [0 .. 23 :: Int]]
        ++ concat [[R.op "r.tmp" "=" ("r.w" ++ a), R.op "r.tmp" "*=" "r.thirtytwo", R.op ("q." ++ a) "+=" "r.tmp", R.op ("q." ++ a) "%=" "r.period"] | a <- axes]
    ),
    ( "point",
      [R.set "r.visible" 1]
        ++ [R.when (R.test "r.target" (show slot)) (R.call ("rooms/origin/" ++ show slot)) | slot <- [0, 1 :: Int]]
        ++ concat [[R.op ("p." ++ a) "=" ("q." ++ a), R.op ("p." ++ a) "-=" ("r.o" ++ a), "scoreboard players add #p." ++ a ++ " manifold 16", R.op ("p." ++ a) "%=" "r.period", "scoreboard players remove #p." ++ a ++ " manifold 16", R.when ("unless score #p." ++ a ++ " manifold matches -6..37") (R.set "r.visible" 0)] | a <- axes]
        ++ [R.when (R.test "r.visible" "0") "return 0"]
        ++ [R.op ("r.p" ++ a) "=" ("p." ++ a) | a <- axes]
        ++ [R.when (R.test "r.frame" (show frame)) (R.call ("rooms/rotate/" ++ show frame)) | frame <- [0 .. 23 :: Int]]
        ++ [R.when (R.test "r.target" "1") "scoreboard players add #p.x manifold 80", "scoreboard players add #p.y manifold 200"]
        ++ [R.put ("point.p" ++ a) ("p." ++ a) | a <- axes]
    ),
    ("block", ["$setblock $(px) $(py) $(pz) $(material)"]),
    ("proxy", ["$summon minecraft:interaction $(px) $(py) $(pz) {Tags:[\"manifold.object.proxy\",\"manifold.object.new\"],width:1.06f,height:1.06f,response:1b}", "$scoreboard players set @e[tag=manifold.object.new] manifold $(id)", "tag @e[tag=manifold.object.new] remove manifold.object.new"]),
    ("entity_point", concat [["execute store result storage manifold:runtime point.p" ++ a ++ " double 0.001 run scoreboard players get #p." ++ a ++ " manifold"] | a <- axes]),
    ( "prefetch",
      [R.call "rooms/region", R.set "r.prefetch" 0]
        ++ concat [[R.when (R.test ("r.local" ++ a) "106496.." ++ " " ++ R.test ("g.v" ++ a) "1..") (R.call ("rooms/prefetch/" ++ a ++ "/positive")), R.when (R.test ("r.local" ++ a) "..24576" ++ " " ++ R.test ("g.v" ++ a) "..-1") (R.call ("rooms/prefetch/" ++ a ++ "/negative"))] | a <- axes]
    )
  ]
    ++ [ ( "prefetch/" ++ axis ++ "/" ++ direction,
           [R.when (R.test "r.prefetch" "1") "return 0", R.set "r.prefetch" 1]
             ++ [R.op ("r.save" ++ a) "=" ("g." ++ a) | a <- axes]
             ++ ["scoreboard players " ++ (if positive then "add" else "remove") ++ " #g." ++ axis ++ " manifold 32768", R.op ("g." ++ axis) "%=" "g.period", R.set "r.target" 1, R.op "r.target" "-=" "h.slot"]
             ++ [R.when (R.test "r.target" (show slot) ++ " " ++ R.test "g.frame" (show frame)) (R.call ("rooms/build/" ++ show slot ++ "/" ++ show frame)) | slot <- [0, 1 :: Int], frame <- [0 .. 23 :: Int]]
             ++ [R.op ("g." ++ a) "=" ("r.save" ++ a) | a <- axes]
             ++ [R.when (R.test "h.slot" (show slot)) (R.call ("rooms/select/" ++ show slot)) | slot <- [0, 1 :: Int]]
         )
       | axis <- axes,
         (direction, positive) <- [("positive", True), ("negative", False)]
       ]
    ++ [("origin/" ++ show slot, [R.op ("r.o" ++ a) "=" ("r.o" ++ a ++ show slot) | a <- axes] ++ [R.op "r.frame" "=" ("h.cache" ++ show slot)]) | slot <- [0, 1 :: Int]]
    ++ [("select/" ++ show slot, concat [[R.op ("r.w" ++ a) "=" ("r.o" ++ a ++ show slot), R.op ("r.w" ++ a) "/=" "r.thirtytwo"] | a <- axes]) | slot <- [0, 1 :: Int]]
    ++ [("rotate/" ++ show frame, concat [let v = S.transformBlock basis unit; index = sum [i | i <- [0 .. 2], G.component i v /= 0]; sign = G.component index v in [R.op ("p." ++ axes !! index) "=" ("r.p" ++ a)] ++ [R.op ("p." ++ axes !! index) "*=" "g.neg" | sign < 0] | (a, unit) <- zip axes G.axes]) | (frame, basis) <- zip [0 :: Int ..] G.frames]
    ++ [("inverse/" ++ show frame, concat [let v = G.apply basis unit; index = sum [i | i <- [0 .. 2], G.component i v /= 0]; sign = G.component index v in [R.op ("q." ++ axes !! index) "=" ("r.p" ++ a)] ++ [R.op ("q." ++ axes !! index) "*=" "g.neg" | sign < 0] | (a, unit) <- zip axes G.axes]) | (frame, basis) <- zip [0 :: Int ..] G.frames]
    ++ [ ( "build/" ++ show slot ++ "/" ++ show frame,
           [ R.call "rooms/region",
             R.set "r.target" slot,
             R.set "r.wait" 0,
             R.when (R.test ("h.cache" ++ show slot) (show frame) ++ " " ++ R.cmp ("r.region" ++ show slot) "=" "r.region") ("return run " ++ R.call ("rooms/ready/" ++ show slot))
           ]
             ++ [R.call ("rooms/clear/" ++ show slot)]
             ++ [R.when (R.test "r.region" (show region)) (R.call ("rooms/build/" ++ show slot ++ "/" ++ show frame ++ "/" ++ show region)) | (region, _) <- regions]
             ++ [R.set ("h.cache" ++ show slot) frame, R.op ("r.region" ++ show slot) "=" "r.region", R.op ("r.window" ++ show slot) "=" "r.region", R.set ("r.age" ++ show slot) 0, R.set "r.wait" 12, R.call ("rooms/select/" ++ show slot), R.call "rooms/materialize"]
         )
       | slot <- [0, 1 :: Int],
         frame <- [0 .. 23 :: Int]
       ]
    ++ [("ready/" ++ show slot, [R.set "r.wait" 12, R.op "r.wait" "-=" ("r.age" ++ show slot), R.when (R.test "r.wait" "..-1") (R.set "r.wait" 0), R.call ("rooms/select/" ++ show slot)]) | slot <- [0, 1 :: Int]]
    ++ [("clear/" ++ show slot, [R.when (R.test ("h.cache" ++ show slot) "0..23") ("return run " ++ R.call ("rooms/clear_known/" ++ show slot))] ++ S.clearSolids slot Nothing) | slot <- [0, 1 :: Int]]
    ++ [("clear_known/" ++ show slot, [R.when (R.test ("h.cache" ++ show slot) (show frame)) ("return run " ++ R.call ("rooms/clear/" ++ show slot ++ "/" ++ show frame)) | frame <- [0 .. 23 :: Int]]) | slot <- [0, 1 :: Int]]
    ++ [("clear/" ++ show slot ++ "/" ++ show frame, S.clearSolids slot (Just frame)) | slot <- [0, 1 :: Int], frame <- [0 .. 23 :: Int]]
    ++ [ ( "build/" ++ show slot ++ "/" ++ show frame ++ "/" ++ show region,
           [R.set ("r.o" ++ a ++ show slot) n | (a, n) <- zip axes (G.components origin)]
             ++ [R.when (R.test "h.level" (show (layoutId layout))) (R.call ("rooms/geometry/" ++ show (layoutId layout) ++ "/" ++ show slot ++ "/" ++ show frame ++ "/" ++ show region)) | layout <- layouts]
         )
       | slot <- [0, 1 :: Int],
         frame <- [0 .. 23 :: Int],
         (region, origin) <- regions
       ]
    ++ [ ( "geometry/" ++ show (layoutId layout) ++ "/" ++ show slot ++ "/" ++ show frame ++ "/" ++ show region,
           concat [map (guard condition) (fillImages slot frame origin box (S.boxMaterial box)) | (condition, box) <- layoutGeometry layout]
         )
       | layout <- layouts,
         slot <- [0, 1],
         frame <- [0 .. 23],
         (region, origin) <- regions
       ]
    ++ [ ( "doors/" ++ show slot ++ "/" ++ show frame ++ "/" ++ show region,
           concat [concat [[R.when (R.test "h.level" (show (layoutId layout)) ++ " " ++ R.test ("r.gate" ++ show channel) (show opened)) command | command <- fillImages slot frame origin box (if opened == 1 then "minecraft:air" else S.boxMaterial box)] | opened <- [0, 1 :: Int]] | layout <- layouts, (channel, box) <- layoutDoors layout]
         )
       | slot <- [0, 1 :: Int],
         frame <- [0 .. 23 :: Int],
         (region, origin) <- regions
       ]
    ++ [("doors", [R.when (R.test ("h.cache" ++ show slot) (show frame) ++ " " ++ R.test ("r.region" ++ show slot) (show region)) (R.call ("rooms/doors/" ++ show slot ++ "/" ++ show frame ++ "/" ++ show region)) | slot <- [0, 1 :: Int], frame <- [0 .. 23 :: Int], (region, _) <- regions])]
  where
    guard "" command = command
    guard condition command = R.when (unwords (words condition)) command
    regions = [(x + 2 * y + 4 * z, (32 * x, 32 * y, 32 * z)) | z <- [0, 1], y <- [0, 1], x <- [0, 1]]
    fillImages slot frame origin box material =
      [ let rotated = S.transformBox (G.frames !! frame) (b {S.boxLo = G.sub (S.boxLo b) origin, S.boxHi = G.sub (S.boxHi b) origin}) in "fill " ++ coords (G.add (S.stageOrigin slot) (S.boxLo rotated)) ++ " " ++ coords (G.add (S.stageOrigin slot) (S.boxHi rotated)) ++ " " ++ material
      | let single = either error id (Scene.compileScene 64 [Scene.Solid box Nothing]),
        b <- Scene.project single origin []
      ]
    coords = unwords . map show . G.components
