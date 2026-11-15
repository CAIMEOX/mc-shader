module

public import LinkTiles.View
public import Lean.Data.Json
meta import Oria
meta import LinkTiles.View

namespace LinkTiles.Input

open Oria Oria.Std Oria.Std.Command.Arg
open Lean (toJson)

public def id : ResourceId := "link_tiles:click"

private def criterion (axis : String) (i : Nat) : Lean.Json := Lean.Json.mkObj [
  ("trigger", "minecraft:player_interacted_with_entity"),
  ("conditions", Lean.Json.mkObj [("entity", Lean.Json.mkObj [
    ("type", "minecraft:entity_properties"), ("entity", "this"),
    ("predicate", Lean.Json.mkObj [("entity_type", "minecraft:interaction"),
      ("nbt", toJson ((nbt% {Tags: ["link_tiles.cell", $(s!"link_tiles.{axis}{i}")]}).format.pretty 100))])])])]

/-- A single native event satisfies a row AND a column. Once complete, listeners stop
until the input is consumed and revoked. No reward function re-enters the runtime. -/
public def advancement : Lean.Json := Lean.Json.mkObj [
  ("criteria", Lean.Json.mkObj ((["r", "c"].flatMap fun axis =>
    (List.range 10).map fun i => (s!"{axis}{i}", criterion axis i)))),
  ("requirements", toJson (["r", "c"].map fun axis => (List.range 10).map fun i => s!"{axis}{i}"))]

private def coordinateGrade : Grade :=
  ⟨Req.executor, Eff.world ||| Eff.scoreboardRead ||| Eff.scoreboardWrite ||| Eff.random⟩

private def keys (axis : String) : Array Oria.Command.Word :=
  if axis == "r" then #["r0", "r1", "r2", "r3", "r4", "r5", "r6", "r7", "r8", "r9"]
  else #["c0", "c1", "c2", "c3", "c4", "c5", "c6", "c7", "c8", "c9"]

private def coordinate (axis : String) (objective : Oria.Command.Objective) : Nat → Prog coordinateGrade Unit
  | 0 => (Prog.pure Val.unit).weaken
  | n + 1 => do
    Execute.forEach [.when (.entity (.self {advancements := [
      (id, .criteria [((keys axis).getD n "invalid", true)])]}))] do
      Scoreboard.set .self objective (.static (Int32.ofNat n))
    coordinate axis objective n

/-- Consume a click before running game logic. Coordinates come from native event criteria. -/
@[mcfunction]
public def read := show Prog _ Int32 from do
  Scoreboard.set .self "link.row" (-1)
  Scoreboard.set .self "link.col" (-1)
  coordinate "r" "link.row" 10
  coordinate "c" "link.col" 10
  let r ← Scoreboard.get .self "link.row"
  let c ← Scoreboard.get .self "link.col"
  (Advancement.revoke .self (.only id none)).ignore
  if r < 0 || c < 0 then return -1
  return (r + 1) * 12 + c + 1

end LinkTiles.Input
