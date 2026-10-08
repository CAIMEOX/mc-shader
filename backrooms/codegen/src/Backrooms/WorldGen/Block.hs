module Backrooms.WorldGen.Block (BlockState (..), plain, air, water, passable, supports, climbable) where

data BlockState = BlockState {blockName :: String, properties :: [(String, String)]} deriving (Eq, Ord, Show)

plain :: String -> BlockState
plain name = BlockState name []

air, water :: BlockState
air = plain "minecraft:air"
water = BlockState "minecraft:water" [("level", "0")]

passable :: Maybe BlockState -> Bool
passable Nothing = True
passable (Just state) = blockName state `elem` ["minecraft:air", "minecraft:water", "minecraft:ladder"]

supports :: Maybe BlockState -> Bool
supports Nothing = False
supports (Just state) = blockName state `notElem` ["minecraft:air", "minecraft:water", "minecraft:oak_fence", "minecraft:ladder"]

climbable :: Maybe BlockState -> Bool
climbable = maybe False ((== "minecraft:ladder") . blockName)
