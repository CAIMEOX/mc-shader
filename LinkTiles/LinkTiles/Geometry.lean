module

public import LinkTiles.State
meta import Oria
meta import LinkTiles.State

namespace LinkTiles.Geometry

open Oria

/-- Strict interior occupancy of a horizontal/vertical line. Both endpoints are excluded. -/
@[mcfunction]
public def clear (a b : Val Int32) : Prog IR.Nbt.readGrade Bool := do
  if a == b then return Bool.lit true
  let ar ← a / 12
  let br ← b / 12
  let ac := a - ar * 12
  let bc := b - br * 12
  if ar == br then
    if ac < bc then
      let next ← state.right[a]
      return next < 0 || next >= b
    else
      let next ← state.left[a]
      return next < 0 || next <= b
  if ac == bc then
    if ar < br then
      let next ← state.down[a]
      return next < 0 || next >= b
    else
      let next ← state.up[a]
      return next < 0 || next <= b
  return Bool.lit false

private def emptyCorner (q a b : Val Int32) : Prog IR.Nbt.readGrade Bool := do
  if q == a || q == b then return Bool.lit true
  let n ← state.tiles[q]
  return n == 0

/-- Candidate routes retain their endpoints and bends for the renderer. -/
@[mcfunction]
private def candidate (a p q b : Val Int32) : Prog memory Bool := do
  let ep ← emptyCorner p a b
  if !ep then return Bool.lit false
  let eq ← emptyCorner q a b
  if !eq then return Bool.lit false
  let x ← clear.call a p
  if !x then return Bool.lit false
  let y ← clear.call p q
  if !y then return Bool.lit false
  let z ← clear.call q b
  if !z then return Bool.lit false
  (Nbt.set state State.Nbt.route (.literal (#[] : Array Int32))).ignore
  Nbt.append state State.Nbt.route (.i32 a)
  if p != a && p != b then Nbt.append state State.Nbt.route (.i32 p)
  if q != p && q != a && q != b then Nbt.append state State.Nbt.route (.i32 q)
  Nbt.append state State.Nbt.route (.i32 b)
  return Bool.lit true

/-- Exact at-most-two-bend routing. Checks straight/one-bend routes before two-bend routes. -/
@[mcfunction]
public def route (a b : Val Int32) : Prog memory Bool := do
  if a < 0 || b < 0 || a >= 144 || b >= 144 || a == b then return Bool.lit false
  let x ← state.tiles[a]
  let y ← state.tiles[b]
  if x == 0 || x != y then return Bool.lit false
  let ar ← a / 12
  let br ← b / 12
  let ac := a - ar * 12
  let bc := b - br * 12
  let straight ← clear.call a b
  if straight then
    return ← candidate.call a a b b
  else
    let p := ar * 12 + bc
    let q := br * 12 + ac
    let first ← candidate.call a p p b
    if first then return Bool.lit true
    let second ← candidate.call a q q b
    if second then return Bool.lit true
    let rec rows (r : Val Int32) : Prog memory Bool := do
      if r >= 12 then return Bool.lit false
      let ok ← candidate.call a (r * 12 + ac) (r * 12 + bc) b
      if ok then return Bool.lit true
      rows (r + 1)
    let ok ← rows 0
    if ok then return Bool.lit true
    let rec columns (c : Val Int32) : Prog memory Bool := do
      if c >= 12 then return Bool.lit false
      let ok ← candidate.call a (ar * 12 + c) (br * 12 + c) b
      if ok then return Bool.lit true
      columns (c + 1)
    columns 0

end LinkTiles.Geometry
