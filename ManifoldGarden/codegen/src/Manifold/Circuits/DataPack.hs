module Manifold.Circuits.DataPack (resources) where

import Data.List (nub)
import Manifold.Runtime qualified as R
import Manifold.Scene qualified as S

resources :: [S.Circuit] -> [Int] -> [Int] -> [(FilePath, String)]
resources circuits identities goalInputs = R.resources "circuits" functions
  where
    functions =
      [ ("reset", [R.set "r.gates" 0, R.set "c.goal_dirty" 0, "data modify storage manifold:runtime circuits set value []"] ++ concat [[R.set ("r.gate" ++ show channel) 0, R.set ("c.dirty" ++ show channel) 0] | channel <- map S.circuitOutput circuits]),
        ("drain", [R.set "c.changed" 0, R.set "c.visits" 0, R.call "circuits/next"]),
        ("next", ["execute unless data storage manifold:runtime circuits[0] run return 0", "data modify storage manifold:runtime circuit_work set from storage manifold:runtime circuits[0]", "data remove storage manifold:runtime circuits[0]", R.call "circuits/route with storage manifold:runtime circuit_work", R.call "circuits/next"]),
        ("route", ["$function manifold:circuits/node/$(id)"])
      ]
        ++ [ ( "mark/" ++ show ident,
               concat [[R.when ("unless score #c.dirty" ++ show channel ++ " manifold matches 1") ("data modify storage manifold:runtime circuits append value {id:" ++ show channel ++ "}"), R.set ("c.dirty" ++ show channel) 1] | channel <- nub (S.affectedCircuits circuits ident)]
                 ++ [R.set "c.goal_dirty" 1 | ident `elem` goalInputs]
             )
           | ident <- identities
           ]
        ++ [ ( "node/" ++ show channel,
               ["scoreboard players add #c.visits manifold 1", R.set ("c.dirty" ++ show channel) 0, R.op "c.before" "=" field, R.set field 0]
                 ++ concat [[R.set "c.object" (-1), "execute if data storage manifold:runtime cells.\"" ++ key ++ "\" store result score #c.object manifold run data get storage manifold:runtime cells.\"" ++ key ++ "\"", R.when (R.test "c.object" (show ident)) (R.set field 1)] | (ident, (x, y, z)) <- S.circuitInputs circuit, let key = show x ++ "_" ++ show y ++ "_" ++ show z]
                 ++ [R.when (R.test "c.before" "1" ++ " " ++ R.test field "0") (R.op "r.gates" "-=" ("pow" ++ show channel)), R.when (R.test "c.before" "0" ++ " " ++ R.test field "1") (R.op "r.gates" "+=" ("pow" ++ show channel)), R.when ("unless score #c.before manifold = #" ++ field ++ " manifold") (R.set "c.changed" 1)]
             )
           | circuit <- circuits,
             let channel = S.circuitOutput circuit,
             let field = "r.gate" ++ show channel
           ]
