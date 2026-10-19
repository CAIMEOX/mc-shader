module JoinerySpec (checks) where

import Control.Monad (foldM, forM_, unless)
import Data.Either (isLeft)
import Data.Set qualified as S
import Manifold.Gravity qualified as G
import Manifold.Joinery qualified as J
import Manifold.Stage (Box (..))

checks :: IO ()
checks = do
  ensure "Each timber is a connected rigid member" (all J.connected J.rods)
  ensure "Entry and assembled geometry are collision-free" (J.valid J.initial && J.valid J.assembled)
  let expected = J.assemblyEnvelope J.rods
      actual = S.unions [J.occupied rod offset | (rod, offset) <- zip J.rods J.assembled]
      gaps = expected S.\\ actual
  ensure ("The assembled timber envelopes close their joints; missing modules: " ++ show (S.toList gaps)) (S.null gaps)
  either fail pure (J.validateShapes J.rods)
  let damaged = [if J.rodId rod == 0 then rod {J.rodCells = S.deleteMin (J.rodCells rod)} else rod | rod <- J.rods]
  ensure "Shape validation detects a missing joinery module" (isLeft (J.validateShapes damaged))
  final <- foldM operating J.initial J.assemblyRoute
  ensure "The assembly route closes all six members" (final == J.assembled)
  let walk seed state = let moves = J.neighbors state in if null moves then state else snd (moves !! (seed `mod` length moves))
      configurations = scanl (flip walk) J.initial (take 240 (iterate (\x -> (x * 73 + 19) `mod` 65521) 41))
  forM_ configurations $ \configuration -> do
    ensure "Three RGB24 words preserve every xyz offset" (J.unpackConfiguration (J.packConfiguration configuration) == configuration)
    ensure "Packed coordinates fit RGB24" (all (\w -> w >= 0 && w < 16777216) (J.packConfiguration configuration))
    forM_ (J.neighbors configuration) $ \(slide, next) -> do
      ensure "Each permitted translation preserves rigid non-overlap" (J.valid next)
      back <- either (fail . show) pure (J.request next (J.slideRod slide) (G.scale (-1) (J.slideDirection slide)))
      ensure "A reverse translation restores all positions" (J.apply next back == configuration)
    forM_ J.rods $ \rod -> forM_ G.downDirections $ \direction -> do
      let i = J.rodId rod
          target = G.add (configuration !! i) direction
          collisions = [J.rodId other | other <- J.rods, J.rodId other /= i, S.member (J.canonical (G.sub target (configuration !! J.rodId other))) (J.obstructingOffsets rod other)]
      ensure "Compiled relative-offset collisions agree with swept occupancy" (case (J.request configuration i direction, collisions) of (Right _, []) -> True; (Left (J.Timber n), xs) -> n `elem` xs; _ -> False)
  ensure "Transverse moves participate in the state graph" (any (\configuration -> any (\(s, _) -> G.component (J.rodAxis (J.rods !! J.slideRod s)) (J.slideDirection s) == 0) (J.neighbors configuration)) configurations)
  let edge = [(15, 0, 0), (0, 4, 0), (0, 0, 4), (4, 0, 0), (0, 4, 4), (4, 4, 0)]
  ensure "Transport round-trips periodic boundary values" (J.unpackConfiguration (J.packConfiguration edge) == edge)
  forM_ J.rods $ \rod -> do
    let interpreted = S.fromList [(x, y, z) | b <- J.boxes rod, let (lx, ly, lz) = boxLo b, let (hx, hy, hz) = boxHi b, x <- [lx `div` 4 .. hx `div` 4], y <- [ly `div` 4 .. hy `div` 4], z <- [lz `div` 4 .. hz `div` 4]]
    ensure "Merged geometry preserves every notch" (interpreted == J.rodCells rod)
  putStrLn "Passed: six-direction rigid translations, periodic occupancy, transport, reversible moves and complete joint coverage."
  where
    ensure message condition = unless condition (fail message)
    operating configuration planned = do
      slide <- either (fail . show) pure (J.request configuration (J.slideRod planned) (J.slideDirection planned))
      let next = J.apply configuration slide
      ensure "Each assembly step preserves disjoint timber volumes" (J.valid next)
      pure next
