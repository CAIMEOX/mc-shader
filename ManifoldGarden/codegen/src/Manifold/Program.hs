module Manifold.Program (RenderProfile (..), pipeline) where

import Manifold.Pipeline
import Manifold.Protocol (packetWords)
import Manifold.Quality

data RenderProfile = Play | Diagnostic deriving (Eq, Show)

pipeline :: RenderProfile -> Pipeline
pipeline profile =
  Pipeline
    ( [ TargetSpec (t "packet_next") (Fixed packetWords 1) False,
        TargetSpec (t "packet") (Fixed packetWords 1) True,
        TargetSpec (t "frame_next") (Fixed 32 1) False,
        TargetSpec (t "frame") (Fixed 32 1) True,
        TargetSpec (t "swap") Screen True,
        TargetSpec (t "presentation") Screen True,
        TargetSpec (t "joinery_light") (Fixed 640 360) True,
        TargetSpec (t "history") Screen True
      ]
        ++ [TargetSpec (t "probe") (Fixed 256 19) True | profile == Diagnostic]
        ++ [TargetSpec (sceneTarget q) (renderExtent q) True | q <- qualities]
    )
    ( [ pass "receive" [Color "Main" mainTarget, Color "Previous" (t "packet"), Color "Frame" (t "frame")] (t "packet_next"),
        pass "copy" [Color "In" (t "packet_next")] (t "packet"),
        pass "frame" [Color "Packet" (t "packet"), Color "Previous" (t "frame")] (t "frame_next"),
        pass "copy" [Color "In" (t "frame_next")] (t "frame")
      ]
        ++ [(pass "joinery_light" baseCameraInputs (t "joinery_light")) {passVertex = "manifold:post/render"}]
        ++ [(camera "probe" (t "probe")) {passInputs = cameraInputs ++ [Depth "Depth" mainTarget]} | profile == Diagnostic]
        ++ [parameterized (parameters q) (camera "scene" (sceneTarget q)) | q <- qualities]
        ++ [ ( pass
                 "composite"
                 ( [Color "Main" mainTarget, Depth "Depth" mainTarget, Color "History" (t "history")]
                     ++ cameraInputs
                     ++ [Color ("Scene" ++ show (qualityId q)) (sceneTarget q) | q <- qualities]
                 )
                 (t "swap")
             )
               { passVertex = "manifold:post/render"
               },
             (pass "presentation" (LinearColor "In" (t "swap") : baseCameraInputs) (t "presentation")) {passVertex = "manifold:post/render"},
             pass "copy" [Color "In" (t "presentation")] mainTarget,
             pass "copy" [Color "In" (t "presentation")] (t "history")
           ]
    )
  where
    t = Target
    sceneTarget q = t ("scene_" ++ qualityName q)
    baseCameraInputs = [Color "Packet" (t "packet"), Color "Frame" (t "frame")]
    cameraInputs = baseCameraInputs ++ [Color "JoineryLight" (t "joinery_light")]
    camera shader output = (pass shader cameraInputs output) {passVertex = "manifold:post/render"}
