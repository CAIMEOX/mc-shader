module

public import Oria
public import Oria.Datapack
meta import Oria
meta import Oria.Datapack

namespace LinkTiles

open Oria

/-- The playable interior of the padded 12 by 12 grid. -/
public def interior (i : Nat) : Bool :=
  i / 12 > 0 && i / 12 < 11 && i % 12 > 0 && i % 12 < 11

public def zeros : Array Int32 := Array.replicate 144 0
public def absent : Array Int32 := Array.replicate 144 (-1)
public def occupied : Array Int32 := (Array.range 144).map fun i => if interior i then 1 else 0

/-- A maximal empty segment's color histogram. Each port denotes a different occupied tile. -/
public structure Segment where
  counts : Array Int32 := Array.replicate 26 0
  duplicates : Int32 := 0
  active : Int32 := 0
  deriving Nbt.Repr

/-- Save format. Indices, display caches and generation workspace can be reconstructed from tiles. -/
public structure State where
  tiles : Array Int32 := zeros
  initial : Array Int32 := zeros
  work : Array Int32 := zeros
  pool : Array Int32 := #[]
  histogram : Array Int32 := Array.replicate 26 0
  solution : Array Int32 := #[]
  left : Array Int32 := absent
  right : Array Int32 := absent
  up : Array Int32 := absent
  down : Array Int32 := absent
  horizontal : Array Int32 := absent
  vertical : Array Int32 := absent
  segments : Array Segment := Array.replicate 288 {}
  good : Int32 := 0
  adjacent : Int32 := 0
  remaining : Int32 := 0
  selected : Int32 := -1
  hintA : Int32 := -1
  hintB : Int32 := -1
  route : Array Int32 := #[]
  routeTicks : Int32 := 0
  phase : Int32 := 0
  cursor : Int32 := 0
  seed : Int32 := 0
  fresh : Int32 := 1
  reshuffles : Int32 := 0
  moves : Int32 := 0
  owner : Array Int32 := #[0, 0, 0, 0]
  origin : Array Int32 := #[0, 0, 0]
  deriving Nbt.Repr

/-- Pack-relative owned document. Phases: 0 idle, 1 dealing, 2 indexing, 3 playing, 4 won, 5 stuck. -/
public def state : Nbt.Global State := Nbt.Global.init "board" (.key "game") {}

@[expose] public def memory : Grade :=
  ⟨Req.none, Eff.memoryRead ||| Eff.memoryWrite ||| Eff.failure⟩

end LinkTiles
