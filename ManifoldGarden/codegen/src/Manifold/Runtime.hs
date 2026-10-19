module Manifold.Runtime where

import Manifold.Protocol (operation, score, setScore)

type Functions = [(String, [String])]

resources :: String -> Functions -> [(FilePath, String)]
resources namespace functions = [("data/manifold/function/" ++ namespace ++ "/" ++ name ++ ".mcfunction", unlines body) | (name, body) <- functions]

set :: String -> Int -> String
set name = setScore name . fromIntegral

add :: String -> Int -> String
add name amount = "scoreboard players " ++ (if amount < 0 then "remove" else "add") ++ " " ++ score name ++ " " ++ show (abs amount)

op :: String -> String -> String -> String
op = operation

test :: String -> String -> String
test name range = "if score " ++ score name ++ " matches " ++ range

cmp :: String -> String -> String -> String
cmp a relation b = "if score " ++ score a ++ " " ++ relation ++ " " ++ score b

when :: String -> String -> String
when condition action = "execute " ++ condition ++ " run " ++ action

call :: String -> String
call name = "function manifold:" ++ name

get :: String -> String -> String
get name path = "execute store result score " ++ score name ++ " run data get storage manifold:runtime " ++ path

put :: String -> String -> String
put path name = "execute store result storage manifold:runtime " ++ path ++ " int 1 run scoreboard players get " ++ score name

-- A generated decision tree visits only the branch containing the requested key.
dispatch :: String -> String -> String -> [(Int, String)] -> Functions
dispatch namespace prefix field entries = go prefix entries
  where
    go name [] = [(name, ["return 0"])]
    go name [(key, target)] = [(name, [when (test field (show key)) ("return run " ++ call target)])]
    go name values =
      let (low, high) = splitAt (length values `div` 2) values
          pivot = fst (last low)
       in (name, [when (test field (".." ++ show pivot)) ("return run " ++ call (namespace ++ "/" ++ name ++ "/lo")), "return run " ++ call (namespace ++ "/" ++ name ++ "/hi")]) : go (name ++ "/lo") low ++ go (name ++ "/hi") high
