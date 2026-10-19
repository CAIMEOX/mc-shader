module Manifold.Level.DataPack (Hook (..), invoke, resources) where

import Manifold.Atrium.DataPack qualified as Atrium
import Manifold.Joinery.DataPack qualified as Joinery
import Manifold.Rooms.DataPack qualified as Rooms
import Manifold.Runtime qualified as R
import Manifold.Scene qualified as S
import Manifold.ThreeRings qualified as T
import Manifold.ThreeRings.DataPack qualified as Rings

data Hook = Validate | Reset | Activate | Native | Cleanup | CanTurn | Blocked | AirInput | Inside | ActiveTick | GravityChanged | Clip String | Wrap String Bool | Build Int Int

path :: Hook -> String
path hook = case hook of
  Validate -> "validate"
  Reset -> "reset"
  Activate -> "activate"
  Native -> "native"
  Cleanup -> "cleanup"
  CanTurn -> "can_turn"
  Blocked -> "blocked"
  AirInput -> "air_input"
  Inside -> "inside"
  ActiveTick -> "active_tick"
  GravityChanged -> "gravity_changed"
  Clip axis -> "clip/" ++ axis
  Wrap axis positive -> "wrap/" ++ axis ++ if positive then "/positive" else "/negative"
  Build slot frame -> "build/" ++ show slot ++ "/" ++ show frame

invoke :: Hook -> String
invoke hook = "function manifold:level/" ++ path hook

resources :: [(FilePath, String)]
resources =
  Atrium.resources
    ++ Rings.resources
    ++ Joinery.resources
    ++ Rooms.resources
      [ Rooms.Layout 2 [(maybe "" (\c -> R.test ("r.gate" ++ show c) "0") (S.solidChannel solid), S.solidBox solid) | solid <- S.sceneSolids T.scene] (Just "objects/materialize") "objects/activate" [(c, S.solidBox solid) | solid <- S.sceneSolids T.scene, Just c <- [S.solidChannel solid]],
        Rooms.Layout 1 [] (Just "joinery/materialize") "joinery/activate" []
      ]
    ++ concatMap emit hooks
  where
    hooks = [Validate, Reset, Activate, Native, Cleanup, CanTurn, Blocked, AirInput, Inside, ActiveTick, GravityChanged] ++ [Clip a | a <- ["x", "y", "z"]] ++ [Wrap a positive | a <- ["x", "y", "z"], positive <- [False, True]] ++ [Build slot frame | slot <- [0, 1], frame <- [0 .. 23]]
    emit hook =
      ("data/manifold/function/level/" ++ path hook ++ ".mcfunction", unlines ["execute if score #h.level manifold matches " ++ show level ++ " run return run function manifold:level/" ++ show level ++ "/" ++ path hook | level <- [0, 1, 2 :: Int]])
        : [("data/manifold/function/level/" ++ show level ++ "/" ++ path hook ++ ".mcfunction", unlines (adapter level hook)) | level <- [0, 1, 2]]

adapter :: Int -> Hook -> [String]
adapter level hook = case (level, hook) of
  (1, Build _ _) -> ["return run function manifold:rooms/" ++ path hook]
  (1, Clip _) -> ["return run function manifold:joinery/scene/" ++ path hook]
  (1, Inside) -> ["return run function manifold:joinery/scene/inside"]
  (1, Wrap _ _) -> ["return 0"]
  (1, _) -> ["return run function manifold:joinery/" ++ path hook]
  (2, Build _ _) -> ["return run function manifold:rooms/" ++ path hook]
  (2, Clip _) -> ["return run function manifold:scene/" ++ path hook]
  (2, Inside) -> ["return run function manifold:scene/inside"]
  (2, Wrap _ _) -> ["return 0"]
  (2, _) -> ["return run function manifold:three_rings/" ++ path hook]
  (_, ActiveTick) -> ["return 0"]
  (_, GravityChanged) -> ["return 0"]
  (0, Native) -> ["return 0"]
  (0, Activate) -> ["return 0"]
  (0, Validate) -> ["return 1"]
  (0, CanTurn) -> ["return 1"]
  (0, Cleanup) -> ["return 0"]
  (0, Blocked) -> ["return 0"]
  (0, AirInput) -> ["return 0"]
  (0, Wrap _ _) -> ["return 0"]
  (0, _) -> ["return run function manifold:atrium/" ++ path hook]
  _ -> ["return 0"]
