module

public import LinkTiles.Input
meta import Oria
meta import Oria.Datapack
meta import LinkTiles.Input

namespace LinkTiles.Game

open Oria Oria.Std

/-- Exact UUID ownership, independent of names and the nearest-player selector. -/
@[mcfunction]
public def owns := show Prog _ Bool from do
  let a ← Data.get (.entity .self) (some ((Nbt.Path.key "UUID").at 0))
  let b ← Data.get (.entity .self) (some ((Nbt.Path.key "UUID").at 1))
  let c ← Data.get (.entity .self) (some ((Nbt.Path.key "UUID").at 2))
  let d ← Data.get (.entity .self) (some ((Nbt.Path.key "UUID").at 3))
  let w ← state.owner[0]
  let x ← state.owner[1]
  let y ← state.owner[2]
  let z ← state.owner[3]
  return a == w && b == x && c == y && d == z

@[mcfunction]
private def near := show Prog _ Bool from do
  let x ← Data.get (.entity .self) (some ((Nbt.Path.key "Pos").at 0))
  let y ← Data.get (.entity .self) (some ((Nbt.Path.key "Pos").at 1))
  let z ← Data.get (.entity .self) (some ((Nbt.Path.key "Pos").at 2))
  let a ← state.origin[0]
  let b ← state.origin[1]
  let c ← state.origin[2]
  return x >= a - 2 && x <= a + 5 && y >= b - 2 && y <= b + 5 && z >= c - 2 && z <= c + 5

@[mcfunction]
private def remember := show Prog _ Unit from do
  let a ← Data.get (.entity .self) (some ((Nbt.Path.key "UUID").at 0))
  let b ← Data.get (.entity .self) (some ((Nbt.Path.key "UUID").at 1))
  let c ← Data.get (.entity .self) (some ((Nbt.Path.key "UUID").at 2))
  let d ← Data.get (.entity .self) (some ((Nbt.Path.key "UUID").at 3))
  Prog.ignore do state.owner[0] := a
  Prog.ignore do state.owner[1] := b
  Prog.ignore do state.owner[2] := c
  Prog.ignore do state.owner[3] := d
  let x ← Data.get (.entity .self) (some ((Nbt.Path.key "Pos").at 0))
  let y ← Data.get (.entity .self) (some ((Nbt.Path.key "Pos").at 1))
  let z ← Data.get (.entity .self) (some ((Nbt.Path.key "Pos").at 2))
  Prog.ignore do state.origin[0] := x - 1
  Prog.ignore do state.origin[1] := y
  Prog.ignore do state.origin[2] := z - 1
  (Tag.add .self "link_tiles.owner").ignore

@[mcfunction]
private def start := show Prog _ Unit from do
  let phase ← state.phase
  let owner ← owns.call
  if phase != 0 && !owner then
    (Tellraw.text .self "This table belongs to another player.").ignore
    return Val.unit
  if phase == 0 then remember.call
  else
    let close ← near.call
    if !close then
      (Tellraw.text .self "Return to your table before starting a new deal.").ignore
      return Val.unit
  (Advancement.revoke .self (.only Input.id none)).ignore
  let seed ← Random.value (.between 0 1000000000)
  Deal.begin.call seed
  View.create.call
  (Tellraw.text .self "LinkTiles: aim down and right-click two matching tiles. /trigger link.action set 2 for a hint; 3 reshuffles; 4 replays; 5 releases the table.").ignore
  View.controls.call

/-- Create or replace the owner's table in the Overworld. -/
@[mcfunction]
public def newGame := show Prog _ Unit from do
  Execute.forEach [.when (.dimension "minecraft:overworld")] do
    start.call

@[mcfunction]
public def replay := show Prog _ Unit from do
  let owner ← owns.call
  if !owner then return Val.unit
  let seed ← state.seed
  Deal.begin.call seed
  View.hideRoute.call

@[mcfunction]
public def hint := show Prog _ Unit from do
  let owner ← owns.call
  if !owner then return Val.unit
  let found ← Model.hint.call
  if found then
    let a ← state.hintA
    let b ← state.hintB
    View.refresh.call a
    View.refresh.call b
    View.showRoute.call

@[mcfunction]
public def reshuffle := show Prog _ Unit from do
  let owner ← owns.call
  if !owner then return Val.unit
  let phase ← state.phase
  if phase == 3 || phase == 5 then
    Deal.reshuffle.call
    View.hideRoute.call

@[mcfunction]
public def release := show Prog _ Unit from do
  let owner ← owns.call
  if !owner then return Val.unit
  Execute.forEach [.when (.dimension "minecraft:overworld")] do
    let close ← near.call
    if !close then
      (Tellraw.text .self "Return to your table to release it.").ignore
      return Val.unit
    Prog.ignore do state.phase := 0
    (Kill.run View.entities).ignore
    (Tag.remove .self "link_tiles.owner").ignore

/-- A receipt is consumed even if a spectator clicks; only the UUID owner can mutate the board. -/
@[mcfunction]
public def receive := show Prog _ Unit from do
  let p ← Input.read.call
  let owner ← owns.call
  if !owner || p < 0 then return Val.unit
  let old ← state.selected
  let hintA ← state.hintA
  let hintB ← state.hintB
  Prog.ignore do state.hintA := -1
  Prog.ignore do state.hintB := -1
  Prog.ignore do state.routeTicks := 0
  View.hideRoute.call
  let result ← Model.select.call p
  match result with
  | .ignored => return Val.unit
  | .won =>
    (Tellraw.text .self "Board cleared! /trigger link.action set 1 starts a new game.").ignore
    (Sound.play .self "minecraft:entity.player.levelup" .player).ignore
  | .stuck => (Tellraw.text .self "No moves remain. /trigger link.action set 3 reshuffles the remaining tiles.").ignore
  | .mismatch => (Sound.play .self "minecraft:block.note_block.bass" .block).ignore
  | _ => (Sound.play .self "minecraft:ui.button.click" .ui).ignore
  if old >= 0 then View.refresh.call old
  if hintA >= 0 then View.refresh.call hintA
  if hintB >= 0 then View.refresh.call hintB
  View.refresh.call p
  let ticks ← state.routeTicks
  if ticks > 0 then View.showRoute.call

@[mcfunction]
private def action := show Prog _ Unit from do
  let code ← Scoreboard.get .self "link.action"
  Scoreboard.set .self "link.action" 0
  match code with
  | 1 => newGame.call
  | 2 => hint.call
  | 3 => reshuffle.call
  | 4 => replay.call
  | 5 => release.call
  | _ => return Val.unit

@[mcfunction]
public def setup := show Prog _ Unit from do
  (Scoreboard.Objectives.add "link.action" .trigger).ignore
  (Scoreboard.Objectives.add "link.row" .dummy).ignore
  (Scoreboard.Objectives.add "link.col" .dummy).ignore
  Execute.forEach [.as .allPlayers] do
    (Advancement.revoke .self (.only Input.id none)).ignore

@[mcfunction]
private def advance := show Prog _ Unit from do
  let phase ← state.phase
  if phase == 1 then Deal.step.call
  else if phase == 2 then
    Index.step.call
    let now ← state.phase
    if now >= 3 then View.render.call
  else
    let ticks ← state.routeTicks
    if ticks > 0 then
      state.routeTicks := ticks - 1
      if ticks == 1 then
        View.hideRoute.call
        let a ← state.hintA
        let b ← state.hintB
        if a >= 0 then View.refresh.call a
        if b >= 0 then View.refresh.call b
        Prog.ignore do state.hintA := -1
        Prog.ignore do state.hintB := -1

/-- Synchronous turns. Construction and route animation advance only while the UUID owner
is beside the anchored table, so unloaded scenes never accumulate duplicate entities. -/
@[mcfunction]
public def tick := show Prog _ Unit from do
  Execute.forEach [.as .allPlayers, .at .self, .when (.dimension "minecraft:overworld")] do
    (Scoreboard.enable .self "link.action").ignore
    Execute.forEach [.when (.entity (.self {scores := [("link.action", .atLeast 1)]}))] do
      action.call
    Execute.forEach [.when (.entity (.self {advancements := [(Input.id, .completed true)]}))] do
      receive.call
  let phase ← state.phase
  let ticks ← state.routeTicks
  if phase == 1 || phase == 2 || ticks > 0 then
    Execute.forEach [.as (.allPlayers {tags := [.include "link_tiles.owner"]}), .at .self,
        .when (.dimension "minecraft:overworld")] do
      let owner ← owns.call
      let close ← near.call
      if owner && close then advance.call

end LinkTiles.Game
