module Manifold.Atrium.DataPack (resources) where

import Manifold.Gravity qualified as G
import Manifold.Messages qualified as M
import Manifold.Protocol
import Manifold.Stage qualified as S
import Manifold.Stage.Collision qualified as C

resources :: [(FilePath, String)]
resources = [("data/manifold/function/atrium/" ++ name ++ ".mcfunction", unlines body) | (name, body) <- functions]

functions :: [(String, [String])]
functions =
  [ ("reset", [setScore "g.x" (8 * fromIntegral G.unit), setScore "g.y" (fromIntegral (G.beamRadius + G.bodyHeight)), setScore "g.z" 0, "tp @s 8.5 202.0 0.5 0 20", "title @s reset"]),
    ("help", [M.chat "aqua" M.AtriumControls, M.chat "white" M.AtriumExplore, M.chat "gray" M.ExitHelp])
  ]
    ++ [(name, [setScore "g.blocked" 0 | name == "inside"] ++ body) | (name, body) <- C.functions]
    ++ [("build/" ++ show slot ++ "/" ++ show frame, S.buildCommands slot frame) | slot <- [0, 1], frame <- [0 .. 23]]
