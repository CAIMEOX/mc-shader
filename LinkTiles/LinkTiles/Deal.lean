module

public import LinkTiles.Index
meta import Oria
meta import LinkTiles.Index

namespace LinkTiles.Deal

open Oria Oria.Std

@[expose] public def grade : Grade := memory.seq (Random.grade (some "link_tiles:deal"))

private def pool : Array Int32 := (Array.range 50).map fun i => Int32.ofNat (i / 2 + 1)

@[mcfunction]
private def shuffle : Prog grade Unit := do
  let n ← Nbt.length state State.Nbt.pool
  let rec next (i : Val Int32) : Prog grade Unit := do
    if i <= 0 then return Val.unit
    let j ← Random.value (.between 0 (.dynamic i)) (some "link_tiles:deal")
    if i != j then
      let a ← state.pool[i]
      let b ← state.pool[j]
      Prog.ignore do state.pool[i] := b
      Prog.ignore do state.pool[j] := a
    next (i - 1)
  next (n - 1)

/-- A new seeded deal has 25 kinds, four copies of each, with a recorded clear certificate. -/
@[mcfunction]
public def begin (seed : Val Int32) := show Prog _ Unit from do
  Random.reset (.one "link_tiles:deal")
    (some {value := .dynamic seed, includeWorldSeed := false, includeSequenceId := false})
  (Nbt.set state State.Nbt.work (.literal occupied)).ignore
  (Nbt.set state State.Nbt.tiles (.literal zeros)).ignore
  (Nbt.set state State.Nbt.pool (.literal pool)).ignore
  (Nbt.set state State.Nbt.solution (.literal (#[] : Array Int32))).ignore
  Prog.ignore do state.remaining := 100
  Prog.ignore do state.selected := -1
  Prog.ignore do state.cursor := 0
  Prog.ignore do state.seed := seed
  Prog.ignore do state.fresh := 1
  Prog.ignore do state.phase := 1
  Prog.ignore do state.moves := 0
  Prog.ignore do state.reshuffles := 0
  Prog.ignore do state.routeTicks := 0
  Prog.ignore do state.hintA := -1
  Prog.ignore do state.hintB := -1
  shuffle.call

/-- Re-deal exactly the remaining multiset on exactly the remaining occupied cells. -/
@[mcfunction]
public def reshuffle := show Prog _ Unit from do
  (Nbt.set state State.Nbt.histogram (.literal (Array.replicate 26 (0 : Int32)))).ignore
  (Nbt.copy state State.Nbt.work state State.Nbt.tiles).ignore
  (Nbt.set state State.Nbt.pool (.literal (#[] : Array Int32))).ignore
  (Nbt.set state State.Nbt.solution (.literal (#[] : Array Int32))).ignore
  let rec count (i : Val Int32) : Prog memory Unit := do
    if i >= 144 then return Val.unit
    let c ← state.tiles[i]
    if c > 0 then
      let n ← state.histogram[c]
      state.histogram[c] := n + 1
    count (i + 1)
  count 0
  let rec colors (c : Val Int32) : Prog memory Unit := do
    if c > 25 then return Val.unit
    let n ← state.histogram[c]
    let rec copies (i : Val Int32) : Prog memory Unit := do
      if i >= n then return Val.unit
      Nbt.append state State.Nbt.pool (.i32 c)
      copies (i + 2)
    copies 0
    colors (c + 1)
  colors 1
  let n ← state.reshuffles
  state.reshuffles := n + 1
  Prog.ignore do state.fresh := 0
  Prog.ignore do state.cursor := 0
  Prog.ignore do state.selected := -1
  Prog.ignore do state.routeTicks := 0
  Prog.ignore do state.hintA := -1
  Prog.ignore do state.hintB := -1
  Prog.ignore do state.phase := 1
  shuffle.call

@[mcfunction]
private def top (column : Val Int32) : Prog memory Int32 := do
  let rec rows (r : Val Int32) : Prog memory Int32 := do
    if r > 10 then return -1
    let p := r * 12 + column + 1
    let n ← state.work[p]
    if n != 0 then return p
    rows (r + 1)
  rows 1

@[mcfunction]
private def find (start : Val Int32) : Prog memory Int32 := do
  let rec columns (n : Val Int32) : Prog memory Int32 := do
    if n >= 10 then return -1
    let c ← (show Prog .pure Int32 from do
      if start + n >= 10 then return start + n - 10 else return start + n)
    let p ← top.call c
    if p >= 0 then return p
    columns (n + 1)
  columns 0

/-- One certificate pair per tick. Tops of two columns connect through the top border;
if only one column remains, its first two tiles connect vertically. -/
@[mcfunction]
public def step := show Prog _ Unit from do
  let cursor ← state.cursor
  let n ← Nbt.length state State.Nbt.pool
  if cursor >= n then
    let fresh ← state.fresh
    if fresh != 0 then (Nbt.copy state State.Nbt.initial state State.Nbt.tiles).ignore
    Index.reset.call
    return Val.unit
  let start ← Random.value (.between 0 9) (some "link_tiles:deal")
  let a ← find.call start
  let row ← a / 12
  let column := a - row * 12 - 1
  state.work[a] := 0
  let b ← find.call (column + 1)
  state.work[b] := 0
  let color ← state.pool[cursor]
  Prog.ignore do state.tiles[a] := color
  Prog.ignore do state.tiles[b] := color
  Nbt.append state State.Nbt.solution (.i32 a)
  Nbt.append state State.Nbt.solution (.i32 b)
  state.cursor := cursor + 1

end LinkTiles.Deal
