module Manifold.Objects where

import Data.Map.Strict (Map)
import Data.Map.Strict qualified as M
import Data.Set (Set)
import Data.Set qualified as S
import Manifold.Gravity qualified as G
import Manifold.Scene qualified as Scene

data Phase = Resting | Carried | Moving deriving (Eq, Ord, Show, Enum)

data Cube = Cube {cubeId :: Int, cubeGravity :: G.V, cubeCell :: G.V, cubePhase :: Phase} deriving (Eq, Show)

data World = World {cubes :: Map Int Cube, occupied :: Map G.V Int, active :: Set Int, down :: G.V, held :: Maybe Int, channels :: [Bool]} deriving (Eq, Show)

data Event = Take Int | Put G.V | Turn G.V | Step deriving (Eq, Show)

data Change = Change {changedCubes :: Set Int, changedChannels :: Set Int, visitedObjects :: Int} deriving (Eq, Show)

initial :: [Cube] -> World
initial values = World (M.fromList [(cubeId c, c) | c <- values]) (M.fromList [(cubeCell c, cubeId c) | c <- values, cubePhase c /= Carried]) S.empty (0, -1, 0) Nothing (replicate 16 False)

validateDefinitions :: Scene.Scene -> [Cube] -> Either String ()
validateDefinitions scene values
  | map cubeId values /= [0 .. length values - 1] = Left "Cube identities must be contiguous and ordered"
  | S.size (S.fromList (map cubeCell values)) /= length values = Left "Cube starting cells must be unique"
  | any (\c -> cubeGravity c `notElem` G.downDirections || cubePhase c /= Resting || Scene.canonical scene (cubeCell c) /= cubeCell c) values = Left "Cube definitions require axial gravity, a canonical cell and a resting phase"
  | any (Scene.solidAt scene (repeat False) . cubeCell) values = Left "Cube starting cells must be clear of architecture"
  | otherwise = Right ()

emptyChange :: Change
emptyChange = Change S.empty S.empty 0

apply :: Scene.Scene -> [Scene.Circuit] -> Event -> World -> Either String (World, Change)
apply scene circuits event world = do
  (next, changed, visited) <- case event of
    Take ident -> do
      cube <- maybe (Left "Unknown cube") Right (M.lookup ident (cubes world))
      if held world /= Nothing || cubeGravity cube /= down world || cubePhase cube /= Resting
        then Left "Cube must be resting in the player's gravity with an empty hand"
        else
          Right (world {cubes = M.insert ident (cube {cubePhase = Carried}) (cubes world), occupied = M.delete (cubeCell cube) (occupied world), held = Just ident, active = S.delete ident (active world)}, S.singleton ident, 1)
    Put p -> do
      ident <- maybe (Left "The player carries a cube") Right (held world)
      cube <- maybe (Left "Unknown held cube") Right (M.lookup ident (cubes world))
      let cell = Scene.canonical scene p
      if blocked scene world cell
        then Left "Placement requires an empty cell"
        else
          Right (world {cubes = M.insert ident (cube {cubeCell = cell, cubePhase = Resting}) (cubes world), occupied = M.insert cell ident (occupied world), held = Nothing}, S.singleton ident, 1)
    Turn gravity ->
      if held world /= Nothing || gravity `notElem` G.downDirections
        then Left "A gravity turn requires an empty hand and an axial direction"
        else
          let affected = S.fromList [cubeId c | c <- M.elems (cubes world), cubeGravity c == gravity || cubeId c `S.member` active world]
              frozen = M.map (\c -> if cubePhase c == Moving then c {cubePhase = Resting} else c) (cubes world)
           in Right (world {down = gravity, active = S.empty, cubes = frozen}, affected, S.size affected)
    Step -> Right (foldl advance world (S.toAscList (active world)), active world, S.size (active world))
  let nearby = S.fromList [ident | c <- M.elems (M.restrictKeys (cubes world) changed) ++ M.elems (M.restrictKeys (cubes next) changed), direction <- G.downDirections, Just ident <- [M.lookup (Scene.canonical scene (G.add (cubeCell c) direction)) (occupied next)]]
      reconsider = S.union changed nearby
      awake = foldl (wake scene) next (S.toList reconsider)
      evaluate values circuit = replace (Scene.circuitOutput circuit) (any (powered awake) (Scene.circuitInputs circuit)) values
      outputs = foldl evaluate (channels awake) (filter (\c -> any ((`S.member` changed) . fst) (Scene.circuitInputs c)) circuits)
      dirtyOutputs = S.fromList [i | (i, (a, b)) <- zip [0 ..] (zip (channels world) outputs), a /= b]
      afterOutputs = awake {channels = outputs}
      final = if S.null dirtyOutputs then afterOutputs else foldl (wake scene) afterOutputs [cubeId c | c <- M.elems (cubes afterOutputs), cubeGravity c == down afterOutputs]
      actual = S.fromList [i | i <- S.toList (S.union reconsider (active world)), M.lookup i (cubes world) /= M.lookup i (cubes final)]
  pure (final, Change actual dirtyOutputs (visited + S.size nearby))
  where
    powered state (ident, cell) = maybe False (\c -> cubePhase c /= Carried && cubeCell c == cell) (M.lookup ident (cubes state))
    replace i value values = take i values ++ [value] ++ drop (i + 1) values
    advance current ident = case M.lookup ident (cubes current) of
      Nothing -> current
      Just cube ->
        let target = Scene.canonical scene (G.add (cubeCell cube) (cubeGravity cube))
         in if cubeGravity cube /= down current || blocked scene current target
              then current {cubes = M.insert ident (cube {cubePhase = Resting}) (cubes current), active = S.delete ident (active current)}
              else current {cubes = M.insert ident (cube {cubeCell = target}) (cubes current), occupied = M.insert target ident (M.delete (cubeCell cube) (occupied current))}

blocked :: Scene.Scene -> World -> G.V -> Bool
blocked scene world cell = Scene.solidAt scene (channels world) cell || M.member (Scene.canonical scene cell) (occupied world)

wake :: Scene.Scene -> World -> Int -> World
wake scene world ident = case M.lookup ident (cubes world) of
  Just cube | cubePhase cube /= Carried && cubeGravity cube == down world && not (blocked scene world (Scene.canonical scene (G.add (cubeCell cube) (cubeGravity cube)))) -> world {active = S.insert ident (active world), cubes = M.insert ident (cube {cubePhase = Moving}) (cubes world)}
  _ -> world
