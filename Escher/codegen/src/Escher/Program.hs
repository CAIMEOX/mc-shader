module Escher.Program (pipeline) where

import Escher.Pipeline
import Escher.Protocol (packetWords)
import Escher.Quality

pipeline :: Pipeline
pipeline =
  Pipeline
    ( [ TargetSpec (t "packet_next") (Fixed packetWords 1) False,
        TargetSpec (t "packet") (Fixed packetWords 1) True,
        TargetSpec (t "frame_next") (Fixed 9 1) False,
        TargetSpec (t "frame") (Fixed 9 1) True,
        TargetSpec (t "probe") (Fixed 80 1) True,
        TargetSpec (t "swap") Screen False
      ]
        ++ [TargetSpec (galleryTarget q) (renderExtent q) True | q <- qualities]
    )
    ( [ pass "receive" [Color "Main" mainTarget] (t "packet_next"),
        pass "copy" [Color "In" (t "packet_next")] (t "packet"),
        pass "frame" [Color "Packet" (t "packet"), Color "Previous" (t "frame")] (t "frame_next"),
        pass "copy" [Color "In" (t "frame_next")] (t "frame"),
        camera "probe" (t "probe")
      ]
        ++ [parameterized (parameters q) (camera "gallery" (galleryTarget q)) | q <- qualities]
        ++ [ pass "composite" ([Color "Main" mainTarget, Color "Packet" (t "packet")] ++ [Color ("Gallery" ++ show (qualityId q)) (galleryTarget q) | q <- qualities]) (t "swap"),
             pass "copy" [Color "In" (t "swap")] mainTarget
           ]
    )
  where
    t = Target
    galleryTarget q = t ("gallery_" ++ qualityName q)
    camera shader output = (pass shader [Color "Packet" (t "packet"), Color "Frame" (t "frame")] output) {passVertex = "escher:post/render"}
