module Manifold.Joinery where

import Control.Monad (unless)
import Data.Bits (shiftL, shiftR, (.&.))
import Data.List (find)
import Data.Set (Set)
import Data.Set qualified as S
import Manifold.Gravity qualified as G
import Manifold.Stage (Box (..))

-- Positions are four-block module offsets on a 16³ periodic lattice.
data Rod = Rod {rodId :: Int, rodAxis :: Int, rodBounds :: (G.V, G.V), rodCells :: Set G.V} deriving (Eq, Show)

type Configuration = [G.V]

data Slide = Slide {slideRod :: Int, slideDirection :: G.V} deriving (Eq, Show)

data Obstruction = InvalidRequest | Timber Int deriving (Eq, Show)

rods :: [Rod]
rods =
  [ timber 0 0 (2, 6, 7) (13, 7, 8) [],
    timber 1 0 (2, 8, 7) (13, 9, 8) [(6, 8, 7), (6, 8, 8), (7, 8, 7), (7, 8, 8), (7, 9, 8), (8, 8, 7), (8, 8, 8), (8, 9, 8), (9, 8, 7), (9, 8, 8)],
    timber 2 1 (7, 2, 6) (8, 13, 7) [(7, 6, 7), (7, 7, 7), (7, 8, 7), (7, 9, 7), (8, 6, 7), (8, 7, 7), (8, 8, 7), (8, 9, 7)],
    timber 3 1 (7, 2, 8) (8, 13, 9) [(7, 6, 8), (7, 7, 8), (7, 8, 8), (8, 6, 8), (8, 7, 8), (8, 8, 8)],
    timber 4 2 (6, 7, 2) (7, 8, 13) [(6, 7, 7), (6, 7, 8), (7, 7, 6), (7, 7, 7), (7, 7, 8), (7, 7, 9), (7, 8, 6), (7, 8, 9)],
    timber 5 2 (8, 7, 2) (9, 8, 13) [(8, 7, 6), (8, 7, 7), (8, 7, 8), (8, 7, 9), (8, 8, 6), (8, 8, 9), (9, 7, 7), (9, 7, 8)]
  ]

timber :: Int -> Int -> G.V -> G.V -> [G.V] -> Rod
timber ident axis low high holes = Rod ident axis (low, high) (cells low high holes)

blankCells :: Rod -> Set G.V
blankCells = S.fromList . uncurry points . rodBounds

assemblyEnvelope :: [Rod] -> Set G.V
assemblyEnvelope = S.unions . map blankCells

validateShapes :: [Rod] -> Either String ()
validateShapes definitions = do
  unless (map rodId definitions == [0 .. 5]) (Left "A joinery assembly has six stable member identities")
  unless (all (\r -> not (S.null (rodCells r)) && rodCells r `S.isSubsetOf` blankCells r && connected r) definitions) (Left "Every member is a connected subset of its timber envelope")
  unless (and [S.disjoint (rodCells a) (rodCells b) | a <- definitions, b <- definitions, rodId a < rodId b]) (Left "Assembled members must occupy disjoint volumes")
  unless (S.unions (map rodCells definitions) == assemblyEnvelope definitions) (Left "Assembled members must cover their timber envelopes completely")

cells :: G.V -> G.V -> [G.V] -> Set G.V
cells lo hi holes = S.fromList (points lo hi) S.\\ S.fromList holes

points :: G.V -> G.V -> [G.V]
points (lx, ly, lz) (hx, hy, hz) = [(x, y, z) | x <- [lx .. hx], y <- [ly .. hy], z <- [lz .. hz]]

canonical :: G.V -> G.V
canonical = G.vector . map (`mod` 16) . G.components

initial, assembled :: Configuration
initial = [(8, 0, 0), (0, 1, 0), (0, 1, 0), (0, 1, 0), (15, 0, 0), (1, 0, 0)]
assembled = replicate 6 (0, 0, 0)

occupied :: Rod -> G.V -> Set G.V
occupied rod offset = S.map (canonical . G.add offset) (rodCells rod)

swept :: Rod -> G.V -> G.V -> Set G.V
swept rod offset direction = occupied rod offset `S.union` occupied rod (G.add offset direction)

-- A one-module translation sweeps exactly the union of its two voxel poses.
request :: Configuration -> Int -> G.V -> Either Obstruction Slide
request configuration ident direction
  | length configuration /= length rods || ident < 0 || ident >= length rods || direction `notElem` G.downDirections = Left InvalidRequest
  | any (\p -> canonical p /= p) configuration = Left InvalidRequest
  | Just other <- find blocked rods = Left (Timber (rodId other))
  | otherwise = Right (Slide ident direction)
  where
    volume = swept (rods !! ident) (configuration !! ident) direction
    blocked other = rodId other /= ident && not (S.disjoint volume (occupied other (configuration !! rodId other)))

apply :: Configuration -> Slide -> Configuration
apply configuration (Slide ident direction) = take ident configuration ++ [canonical (G.add (configuration !! ident) direction)] ++ drop (ident + 1) configuration

neighbors :: Configuration -> [(Slide, Configuration)]
neighbors configuration = [(s, apply configuration s) | rod <- rods, direction <- G.downDirections, Right s <- [request configuration (rodId rod) direction]]

valid :: Configuration -> Bool
valid configuration = length configuration == length rods && all (\p -> canonical p == p) configuration && and [S.disjoint (occupied a pa) (occupied b pb) | (a, pa) <- zip rods configuration, (b, pb) <- zip rods configuration, rodId a < rodId b]

-- The relative translations that make two rigid members overlap.
obstructingOffsets :: Rod -> Rod -> Set G.V
obstructingOffsets a b = S.fromList [canonical (G.sub pb pa) | pa <- S.toList (rodCells a), pb <- S.toList (rodCells b)]

connected :: Rod -> Bool
connected rod = visit S.empty [S.findMin (rodCells rod)] == rodCells rod
  where
    visit seen [] = seen
    visit seen (p : ps)
      | S.member p seen = visit seen ps
      | otherwise = visit (S.insert p seen) ([G.add p d | d <- G.downDirections, S.member (G.add p d) (rodCells rod)] ++ ps)

-- Merge adjacent occupied modules into exact box unions for every backend.
mergeCells :: Int -> Set G.V -> [(G.V, G.V)]
mergeCells axis remaining
  | S.null remaining = []
  | otherwise = (lo, hi) : mergeCells axis (remaining S.\\ S.fromList (points lo hi))
  where
    lo = S.findMin remaining
    hi = foldl' extend lo [axis, (axis + 1) `mod` 3, (axis + 2) `mod` 3]
    extend high a = let next = G.add high (G.axes !! a) in if all (`S.member` remaining) (points lo next) then extend next a else high

boxes :: Rod -> [Box]
boxes rod = [Box (G.scale 4 lo) (G.add (G.scale 4 hi) (3, 3, 3)) "minecraft:stripped_oak_wood" | (lo, hi) <- mergeCells (rodAxis rod) (rodCells rod)]

atPose :: Rod -> G.V -> [Box]
atPose rod offset = [b {boxLo = G.add delta (boxLo b), boxHi = G.add delta (boxHi b)} | b <- boxes rod]
  where
    delta = G.scale 4 offset

motionBoxes :: Rod -> G.V -> G.V -> [Box]
motionBoxes rod offset direction = [b {boxLo = G.add (G.vector (map (min 0) ds)) (boxLo b), boxHi = G.add (G.vector (map (max 0) ds)) (boxHi b)} | b <- atPose rod offset]
  where
    ds = G.components (G.scale 4 direction)

-- Two xyz offsets fit exactly into each RGB24 transport word.
packConfiguration :: Configuration -> [Int]
packConfiguration configuration = [word a + shiftL (word b) 12 | (a, b) <- pairs configuration]
  where
    word (x, y, z) = x + shiftL y 4 + shiftL z 8
    pairs (a : b : rest) = (a, b) : pairs rest
    pairs _ = []

unpackConfiguration :: [Int] -> Configuration
unpackConfiguration words' = [G.vector [shiftR word (shift + a * 4) .&. 15 | a <- [0 .. 2]] | word <- words', shift <- [0, 12]]

-- The side members close first; the solid key fills the remaining channel.
assemblyRoute :: [Slide]
assemblyRoute = [Slide 5 (-1, 0, 0), Slide 4 (1, 0, 0), Slide 3 (0, -1, 0), Slide 1 (0, -1, 0), Slide 2 (0, -1, 0)] ++ replicate 8 (Slide 0 (-1, 0, 0))
