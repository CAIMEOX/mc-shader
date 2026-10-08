module Backrooms.Program (pipeline) where

import Backrooms.Domain (rayFixtures)
import Backrooms.Pipeline
import Backrooms.Protocol (packetWords)

pipeline :: Pipeline
pipeline =
  Pipeline
    [ TargetSpec (t "packet_next") (Fixed packetWords 1) False,
      TargetSpec (t "packet") (Fixed packetWords 1) True,
      TargetSpec (t "probe") (Fixed (8 + 4 * length rayFixtures) 1) True,
      TargetSpec (t "scene") (Fixed 960 540) True,
      TargetSpec (t "swap") Screen False
    ]
    [ pass "receive" [Color "Main" mainTarget, Color "Previous" (t "packet")] (t "packet_next"),
      pass "copy" [Color "In" (t "packet_next")] (t "packet"),
      camera "probe" [Color "Packet" (t "packet")] (t "probe"),
      camera "scene" [Color "Packet" (t "packet"), Color "Main" mainTarget, Depth "WorldDepth" mainTarget] (t "scene"),
      pass "composite" [Color "Main" mainTarget, Color "Scene" (t "scene"), Color "Packet" (t "packet")] (t "swap"),
      pass "copy" [Color "In" (t "swap")] mainTarget
    ]
  where
    t = Target
    camera shader inputs output = (pass shader inputs output) {passVertex = "backrooms:post/render"}
