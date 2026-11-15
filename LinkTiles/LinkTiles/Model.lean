module

public import LinkTiles.Deal
meta import Oria
meta import LinkTiles.Deal

namespace LinkTiles.Model

open Oria

/-- Observable outcomes of a selection, with normal control flow for rejected input. -/
public inductive Selection where
  | ignored | selected | cancelled | mismatch | removed | stuck | won
  deriving Object

/-- Route, erase both endpoints, and publish the new phase after the index is consistent. -/
@[mcfunction]
public def select (p : Val Int32) : Prog memory Selection := do
  let phase ← state.phase
  if phase != 3 && phase != 5 then return .ignored
  if p < 13 || p > 130 then return .ignored
  let c ← state.tiles[p]
  if c == 0 then return .ignored
  let a ← state.selected
  if a == p then
    state.selected := -1
    return .cancelled
  if a < 0 then
    state.selected := p
    return .selected
  let ok ← Geometry.route.call a p
  if !ok then
    state.selected := p
    return .mismatch
  state.selected := -1
  Index.erase.call a
  Index.erase.call p
  let moves ← state.moves
  state.moves := moves + 1
  Prog.ignore do state.routeTicks := 10
  let n ← state.remaining
  if n == 0 then
    state.phase := 4
    return .won
  let available ← Index.hasMove.call
  if !available then
    Prog.ignore do state.phase := 5
    return .stuck
  return .removed

/-- A hint uses a concrete witness from the incremental index and the normal route renderer. -/
@[mcfunction]
public def hint : Prog memory Bool := do
  let phase ← state.phase
  if phase != 3 then return Bool.lit false
  let found ← Index.hint.call
  if found then Prog.ignore do state.routeTicks := 30
  return found

end LinkTiles.Model
