module

public import LinkTiles.Geometry
meta import Oria
meta import LinkTiles.Geometry

namespace LinkTiles.Index

open Oria

private def ray (axis : Nat) (forward : Bool) (i : Val Int32) : Prog IR.Nbt.readGrade Int32 :=
  match axis, forward with
  | 0, false => do return ← state.left[i]
  | 0, true => do return ← state.right[i]
  | _, false => do return ← state.up[i]
  | _, true => do return ← state.down[i]

private def owner (axis : Nat) (i : Val Int32) : Prog IR.Nbt.readGrade Int32 :=
  if axis == 0 then do return ← state.horizontal[i]
  else do return ← state.vertical[i]

private def setOwner (axis : Nat) (i s : Val Int32) : Prog IR.Nbt.writeGrade.handled Unit :=
  if axis == 0 then Prog.ignore do state.horizontal[i] := s
  else Prog.ignore do state.vertical[i] := s

/-- Maintain threshold crossings, rather than rescanning the histogram on each change. -/
@[mcfunction]
private def change (s color delta : Val Int32) : Prog memory Unit := do
  if color <= 0 then return Val.unit
  let n ← state.segments[s].counts[color]
  state.segments[s].counts[color] := n + delta
  let d ← state.segments[s].duplicates
  if n == 1 && delta == 1 then
    state.segments[s].duplicates := d + 1
    if d == 0 then
      let good ← state.good
      state.good := good + 1
  if n == 2 && delta == -1 then
    state.segments[s].duplicates := d - 1
    if d == 1 then
      let good ← state.good
      state.good := good - 1

private def port (s p delta : Val Int32) : Prog memory Unit := do
  if p < 0 then return Val.unit
  let color ← state.tiles[p]
  change.call s color delta

private def retire (s : Val Int32) : Prog memory Unit := do
  if s < 0 then return Val.unit
  let n ← state.segments[s].duplicates
  if n > 0 then
    let good ← state.good
    state.good := good - 1
  state.segments[s].active := 0

private def slot (axis : Nat) (line pos : Val Int32) : Val Int32 :=
  if axis == 0 then line * 12 + pos else pos * 12 + line

/-- Build one empty segment. Longitudinal ports occur only at its two ends;
perpendicular ports occur once at each coordinate. No endpoint is counted twice. -/
private def buildSegment (axis : Nat) (first last : Val Int32) : Prog memory Unit := do
  let step := if axis == 0 then (1 : Val Int32) else 12
  let s := first * 2 + I32.lit (Int32.ofNat axis)
  (Nbt.set state (State.Nbt.segments.at s) (.literal ({active := 1} : Segment))).ignore
  let left ← ray axis false first
  let right ← ray axis true last
  port s left 1
  port s right 1
  let rec cells (p : Val Int32) : Prog memory Unit := do
    if p > last then return Val.unit
    setOwner axis p s
    let up ← ray (1 - axis) false p
    let down ← ray (1 - axis) true p
    port s up 1
    port s down 1
    cells (p + step)
  cells first

/-- Reinitialize derived data. Its subsequent 24 indexing slices leave tiles unchanged. -/
@[mcfunction]
public def reset := show Prog _ Unit from do
  (Nbt.set state State.Nbt.left (.literal absent)).ignore
  (Nbt.set state State.Nbt.right (.literal absent)).ignore
  (Nbt.set state State.Nbt.up (.literal absent)).ignore
  (Nbt.set state State.Nbt.down (.literal absent)).ignore
  (Nbt.set state State.Nbt.horizontal (.literal absent)).ignore
  (Nbt.set state State.Nbt.vertical (.literal absent)).ignore
  (Nbt.set state State.Nbt.segments (.literal (Array.replicate 288 ({} : Segment)))).ignore
  Prog.ignore do state.good := 0
  Prog.ignore do state.adjacent := 0
  Prog.ignore do state.cursor := 0
  Prog.ignore do state.selected := -1
  Prog.ignore do state.phase := 2

private def scan (axis : Nat) (line : Val Int32) : Prog memory Unit := do
  let rec cells (i prev color : Val Int32) : Prog memory Unit := do
    if i >= 12 then return Val.unit
    let p := slot axis line i
    let current ← state.tiles[p]
    if axis == 0 then Prog.ignore do state.left[p] := prev
    else Prog.ignore do state.up[p] := prev
    if current != 0 && current == color then
      let n ← state.adjacent
      state.adjacent := n + 1
    if current != 0 then cells (i + 1) p current
    else cells (i + 1) prev 0
  cells 0 (-1) 0
  let rec reverse (i prev : Val Int32) : Prog memory Unit := do
    if i < 0 then return Val.unit
    let p := slot axis line i
    let current ← state.tiles[p]
    if axis == 0 then Prog.ignore do state.right[p] := prev
    else Prog.ignore do state.down[p] := prev
    if current != 0 then reverse (i - 1) p
    else reverse (i - 1) prev
  reverse 11 (-1)

private def segments (axis : Nat) (line : Val Int32) : Prog memory Unit := do
  let rec findEnd (i : Val Int32) : Prog memory Int32 := do
    if i >= 12 then return 12
    let color ← state.tiles[slot axis line i]
    if color != 0 then return i
    findEnd (i + 1)
  let rec next (i : Val Int32) : Prog memory Unit := do
    if i >= 12 then return Val.unit
    let color ← state.tiles[slot axis line i]
    if color != 0 then next (i + 1)
    else
      let stop ← findEnd (i + 1)
      buildSegment axis (slot axis line i) (slot axis line (stop - 1))
      next stop
  next 0

/-- One bounded rebuild slice: first all nearest-obstacle rays, then maximal segments. -/
@[mcfunction]
public def step : Prog memory Unit := do
  let i ← state.cursor
  if i < 12 then
    scan 0 i
    scan 1 i
  else
    segments 0 (i - 12)
    segments 1 (i - 12)
  state.cursor := i + 1
  if i == 23 then
    let n ← state.remaining
    let good ← state.good
    let adjacent ← state.adjacent
    if n == 0 then Prog.ignore do state.phase := 4
    else if good + adjacent == 0 then Prog.ignore do state.phase := 5
    else Prog.ignore do state.phase := 3

/-- O(1) existence query; completion is distinguished using remaining. -/
@[mcfunction]
public def hasMove : Prog IR.Nbt.readGrade Bool := do
  let n ← state.good
  let adjacent ← state.adjacent
  return n + adjacent > 0

private def endpoint (axis : Nat) (forward : Bool) (p q : Val Int32) :
    Prog IR.Nbt.writeGrade.handled Unit :=
  match axis, forward with
  | 0, false => do if p >= 0 then Prog.ignore do state.left[p] := q
  | 0, true => do if p >= 0 then Prog.ignore do state.right[p] := q
  | _, false => do if p >= 0 then Prog.ignore do state.up[p] := q
  | _, true => do if p >= 0 then Prog.ignore do state.down[p] := q

/-- The opened run changes one perpendicular segment's port at each crossed coordinate. -/
private def openLine (axis : Nat) (p color : Val Int32) : Prog memory Unit := do
  let step := if axis == 0 then (1 : Val Int32) else 12
  let row ← p / 12
  let left ← ray axis false p
  let right ← ray axis true p
  let first ← (show Prog .pure Int32 from do
    if left >= 0 then return left + step
    if axis == 0 then return row * 12 else return p - row * 12)
  let last ← (show Prog .pure Int32 from do
    if right >= 0 then return right - step
    if axis == 0 then return row * 12 + 11 else return p - row * 12 + 132)
  if first < p then
    let s ← owner axis first
    retire s
  if last > p then
    let s ← owner axis last
    retire s
  endpoint axis true left right
  endpoint axis false right left
  let rec cells (q : Val Int32) : Prog memory Unit := do
    if q > last then return Val.unit
    if q != p then
      let s ← owner (1 - axis) q
      change.call s color (-1)
      if q < p then
        endpoint axis true q right
        port s right 1
      else
        endpoint axis false q left
        port s left 1
    cells (q + step)
  cells first
  buildSegment axis first last

/-- Delete one occupied tile, updating only its horizontal/vertical runs and crossed ports.
Callers validate a pair first and publish the final phase after both deletions. -/
@[mcfunction]
public def erase (p : Val Int32) : Prog memory Unit := do
  let color ← state.tiles[p]
  if color == 0 then return Val.unit
  let adjacent (q : Val Int32) : Prog memory Unit := do
    let other ← state.tiles[q]
    if other == color then
      let n ← state.adjacent
      state.adjacent := n - 1
  adjacent (p - 12)
  adjacent (p + 12)
  adjacent (p - 1)
  adjacent (p + 1)
  state.tiles[p] := 0
  openLine 0 p color
  openLine 1 p color
  let n ← state.remaining
  state.remaining := n - 1

private def remember (p color : Val Int32) : Prog memory Unit := do
  if p < 0 then return Val.unit
  let n ← state.tiles[p]
  if n != color then return Val.unit
  let a ← state.hintA
  if a < 0 then state.hintA := p
  else if a != p then Prog.ignore do state.hintB := p

private def witness (axis : Nat) (s color : Val Int32) : Prog memory Unit := do
  let first ← s / 2
  let right ← ray axis true first
  let row ← first / 12
  let stop ← (show Prog .pure Int32 from do
    if right >= 0 then return right
    if axis == 0 then return row * 12 + 12 else return first - row * 12 + 144)
  let step := if axis == 0 then (1 : Val Int32) else 12
  let left ← ray axis false first
  remember left color
  remember right color
  let rec cells (p : Val Int32) : Prog memory Unit := do
    if p >= stop then return Val.unit
    let up ← ray (1 - axis) false p
    let down ← ray (1 - axis) true p
    remember up color
    remember down color
    cells (p + step)
  cells first

/-- Recover a concrete pair from one duplicate histogram, or from the adjacency fallback.
The hint search scans segment metadata, not all candidate tile pairs. -/
@[mcfunction]
public def hint : Prog memory Bool := do
  Prog.ignore do state.hintA := -1
  Prog.ignore do state.hintB := -1
  let rec find (s : Val Int32) : Prog memory Int32 := do
    if s >= 288 then return -1
    let active ← state.segments[s].active
    let n ← state.segments[s].duplicates
    if active != 0 && n > 0 then return s
    find (s + 1)
  let s ← find 0
  if s >= 0 then
    let rec color (c : Val Int32) : Prog memory Int32 := do
      if c > 25 then return 0
      let n ← state.segments[s].counts[c]
      if n >= 2 then return c
      color (c + 1)
    let c ← color 1
    let first ← s / 2
    if s == first * 2 then witness 0 s c else witness 1 s c
  else
    let rec pairs (p : Val Int32) : Prog memory Unit := do
      if p >= 131 then return Val.unit
      let color ← state.tiles[p]
      if color > 0 then
        let right ← state.tiles[p + 1]
        let down ← state.tiles[p + 12]
        if color == right then
          Prog.ignore do state.hintA := p
          Prog.ignore do state.hintB := p + 1
          return Val.unit
        if color == down then
          Prog.ignore do state.hintA := p
          Prog.ignore do state.hintB := p + 12
          return Val.unit
      pairs (p + 1)
    pairs 13
  let a ← state.hintA
  let b ← state.hintB
  if a < 0 || b < 0 then return Bool.lit false
  return ← Geometry.route.call a b

end LinkTiles.Index
